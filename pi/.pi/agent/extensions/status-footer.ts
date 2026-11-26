/**
 * Status Footer: a clearer replacement for pi's built-in footer.
 *
 *   🧠 claude-opus-5-5 · high · anthropic        ● working 12s  🛡 3  ⏸ plan  codemode
 *   📊 ▰▰▰▱▱▱▱▱▱▱ 31% · 62k / 200k       💰 $0.410 sub  in 243k · out 9.0k · cache 99%
 *   📁 ~/Documents/journal ⎇ main +1 ~2 · pi-setup · 🗂 3 open     🔎 classifier ⠹ 2 running
 *
 * Line 1: model, thinking level, provider, routed model (virtual models);
 *   on the right: busy/idle state, active safety extensions (flashes when one
 *   blocks something), modes reported by other extensions, codemode.
 * Line 2: context bar (green/yellow/red), session cost, tokens, cache hits.
 *   Cost turns yellow past the budget and red past twice the budget. Only
 *   money actually billed counts towards the budget: usage on providers
 *   logged in with a subscription is excluded.
 * Line 3: folder, git branch with changed files (+new ~modified -deleted),
 *   session name, open pi-memory scratchpad items; classifier activity.
 *
 * Settings (environment variables):
 *   PI_FOOTER_BUDGET  session budget in USD for billed usage (default 1)
 *
 * `/footer` switches between this footer and the built-in one.
 * Classifier calls made directly by extensions are shown when the extension
 * reports them on pi.events (`classifier:start` / `classifier:end`), as
 * model-router does; other direct calls are not visible.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const DONE_VISIBLE_MS = 20_000;
const BLOCK_VISIBLE_MS = 10_000;
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const BUDGET = (() => {
	const n = Number(process.env.PI_FOOTER_BUDGET);
	return Number.isFinite(n) && n > 0 ? n : 1;
})();

type CallRow = { name: string; args: string; status: string; cost?: number; durationMs?: number };
type ClassifierSummary = { calls: number; errors: number; cost: number; ms: number };
type Usage = { input: number; output: number; cacheRead: number; cacheWrite: number; cost: { total: number } };

const fmtTokens = (n: number) =>
	n < 1000 ? `${n}` : n < 10_000 ? `${(n / 1000).toFixed(1)}k` : n < 1e6 ? `${Math.round(n / 1000)}k` : `${(n / 1e6).toFixed(1)}M`;
const fmtCost = (n: number) => (n === 0 ? "$0" : n < 0.01 ? `$${n.toFixed(4)}` : `$${n.toFixed(3)}`);
const fmtElapsed = (ms: number) => {
	const s = Math.floor(ms / 1000);
	return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
};
const shortModel = (ref: string) => ref.split("/").pop() ?? ref;

/** Keep segments in order while they fit (first segment always kept). */
function fit(width: number, segments: string[], sep: string): string[] {
	const out: string[] = [];
	for (const s of segments) {
		if (out.length === 0 || visibleWidth([...out, s].join(sep)) <= width) out.push(s);
	}
	return out;
}

/**
 * Left segments joined with sep; right parts added in priority order while
 * they fit. A right part may be a list of alternatives, longest first.
 */
function line(width: number, left: string[], right: (string | string[])[], sep: string): string {
	let l = fit(width, left, sep).join(sep);
	const r: string[] = [];
	for (const part of right) {
		const forms = Array.isArray(part) ? part : [part];
		const ok = forms.find((f) => visibleWidth(l) + 2 + visibleWidth([...r, f].join("  ")) <= width);
		if (ok) r.push(ok);
	}
	const rs = r.join("  ");
	if (!rs) return truncateToWidth(l, width, "…");
	l = truncateToWidth(l, Math.max(1, width - visibleWidth(rs) - 2), "…");
	return l + " ".repeat(Math.max(2, width - visibleWidth(l) - visibleWidth(rs))) + rs;
}

/** Like line(), but the right side is never dropped: pick the first form that fits, shorten the left. */
function lineKeepRight(width: number, left: string[], rightForms: string[], sep: string): string {
	const l = fit(width, left, sep).join(sep);
	if (rightForms.length === 0) return truncateToWidth(l, width, "…");
	const r = rightForms.find((f) => visibleWidth(l) + 2 + visibleWidth(f) <= width) ?? rightForms[rightForms.length - 1];
	const lt = truncateToWidth(l, Math.max(1, width - visibleWidth(r) - 2), "…");
	return lt + " ".repeat(Math.max(2, width - visibleWidth(lt) - visibleWidth(r))) + r;
}

export default function (pi: ExtensionAPI) {
	let enabled = true;
	let ctxRef: ExtensionContext | undefined;
	let requestRender: (() => void) | undefined;
	let footerData: { getGitBranch(): string | null; getExtensionStatuses(): ReadonlyMap<string, string> } | undefined;
	const render = () => requestRender?.();

	// 1. Busy / idle
	let busySince: number | undefined;

	// 2. Safety
	const safety = new Set<string>();
	let lastBlock: { reason: string; at: number } | undefined;

	// 3. Git changes
	let git = { added: 0, modified: 0, deleted: 0 };
	let gitRunning = false;
	let gitAgain = false;

	// 5. Memory scratchpad
	let openItems = 0;

	// Classifier tracking (rows per codemode tool call)
	const running = new Map<string, CallRow[]>();
	let lastRun: ClassifierSummary | undefined;
	let lastRunAt = 0;

	// Usage cache
	let usageKey = "";
	let usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, billed: 0, cacheHit: undefined as number | undefined };
	let routed: string | undefined;
	/** Provider and model of the latest response (the routed model under a virtual model). */
	let answered: { provider: string; model: string } | undefined;
	const subscription = new Map<string, boolean>();

	// One timer drives the spinner and the elapsed time; it runs only when needed.
	let frame = 0;
	let ticker: ReturnType<typeof setInterval> | undefined;
	const timers = new Set<ReturnType<typeof setTimeout>>();

	const classifierRows = () => [...running.values()].flat().filter((r) => r.name === "models.classify");
	const classifierActive = () => classifierRows().some((r) => r.status === "running");

	function updateTicker() {
		const needed = busySince !== undefined || classifierActive();
		if (needed && !ticker) {
			ticker = setInterval(() => {
				frame = (frame + 1) % SPINNER.length;
				render();
			}, 100);
		} else if (!needed && ticker) {
			clearInterval(ticker);
			ticker = undefined;
		}
		render();
	}

	/** Re-render once after a temporary message expires. */
	function renderLater(ms: number) {
		const t = setTimeout(() => {
			timers.delete(t);
			render();
		}, ms + 50);
		timers.add(t);
	}

	async function refreshGit(ctx: ExtensionContext) {
		if (gitRunning) {
			gitAgain = true;
			return;
		}
		gitRunning = true;
		try {
			const r = await pi.exec("git", ["status", "--porcelain"], { cwd: ctx.cwd, timeout: 5000 });
			const next = { added: 0, modified: 0, deleted: 0 };
			if (r.code === 0) {
				for (const l of r.stdout.split("\n")) {
					if (!l.trim()) continue;
					const xy = l.slice(0, 2);
					if (xy === "??" || xy.includes("A")) next.added++;
					else if (xy.includes("D")) next.deleted++;
					else next.modified++;
				}
			}
			git = next;
			render();
		} finally {
			gitRunning = false;
			if (gitAgain) {
				gitAgain = false;
				void refreshGit(ctx);
			}
		}
	}

	function refreshScratchpad() {
		const dir = process.env.PI_MEMORY_DIR || join(process.env.HOME ?? "", ".pi", "agent", "memory");
		try {
			openItems = (readFileSync(join(dir, "SCRATCHPAD.md"), "utf-8").match(/^\s*- \[ \]/gm) ?? []).length;
		} catch {
			openItems = 0;
		}
		render();
	}

	function isSubscription(ctx: ExtensionContext, provider: string, modelId: string): boolean {
		const key = `${provider}/${modelId}`;
		if (!subscription.has(key)) {
			const m = ctx.modelRegistry.find(provider, modelId);
			subscription.set(key, m ? ctx.modelRegistry.isUsingOAuth(m) : false);
		}
		return subscription.get(key) ?? false;
	}

	function computeUsage(ctx: ExtensionContext) {
		const sm = ctx.sessionManager;
		const key = `${sm.getSessionId()}|${sm.getLeafId()}|${sm.getEntries().length}`;
		if (key === usageKey) return;
		usageKey = key;
		const u = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, billed: 0, cacheHit: undefined as number | undefined };
		const add = (x: Usage | undefined, billed: boolean) => {
			if (!x) return;
			u.input += x.input;
			u.output += x.output;
			u.cacheRead += x.cacheRead;
			u.cacheWrite += x.cacheWrite;
			u.cost += x.cost.total;
			if (billed) u.billed += x.cost.total;
		};
		let last: AssistantMessage | undefined;
		for (const e of sm.getEntries() as any[]) {
			if (e.type === "usage") add(e.usage, true);
			else if ((e.type === "compaction" || e.type === "branch_summary") && e.usage) add(e.usage, true);
			else if (e.type === "message" && e.message.role === "toolResult") add(e.message.usage, true);
			else if (e.type === "message" && e.message.role === "assistant") {
				const m = e.message as AssistantMessage;
				add(m.usage, !isSubscription(ctx, m.provider, m.model));
				last = m;
				const prompt = m.usage.input + m.usage.cacheRead + m.usage.cacheWrite;
				u.cacheHit = prompt > 0 ? (m.usage.cacheRead / prompt) * 100 : undefined;
			}
		}
		usage = u;
		routed = last && ctx.model && last.model !== ctx.model.id ? last.model : undefined;
		answered = last ? { provider: last.provider, model: last.model } : undefined;
	}

	function renderFooter(width: number, theme: Theme): string[] {
		const ctx = ctxRef;
		if (!ctx) return [];
		computeUsage(ctx);
		const sep = theme.fg("dim", " · ");
		const model = ctx.model;
		const now = Date.now();

		// Line 1: model | state, safety, modes
		const level = pi.getThinkingLevel();
		const levelColor = `thinking${level[0].toUpperCase()}${level.slice(1)}` as any;
		const modelLeft = [
			`🧠 ${theme.bold(theme.fg("accent", model?.id ?? "no model"))}`,
			...(routed ? [theme.fg("accent", `→ ${routed}`)] : []),
			...(model?.reasoning ? [theme.fg(levelColor, level === "off" ? "thinking off" : level)] : []),
			...(model ? [theme.fg("muted", model.provider)] : []),
		];
		const state =
			busySince !== undefined
				? theme.fg("accent", `● working ${fmtElapsed(now - busySince)}`)
				: theme.fg("success", "○ waiting for you");
		let shield: (string | string[])[] = [];
		if (lastBlock && now - lastBlock.at < BLOCK_VISIBLE_MS) {
			// Shown before the busy state so it is the last thing dropped.
			shield = [[theme.fg("warning", `🛡 blocked: ${lastBlock.reason}`), theme.fg("warning", "🛡 blocked")]];
		} else if (safety.size > 0) {
			shield = [theme.fg("muted", `🛡 ${safety.size}`)];
		}
		const statuses = [...(footerData?.getExtensionStatuses() ?? new Map<string, string>()).entries()]
			.sort(([a], [b]) => a.localeCompare(b))
			.map(([, v]) => v.replace(/\s+/g, " ").trim());
		const codemode = pi.getActiveTools().includes("codemode") ? [theme.fg("dim", "codemode")] : [];
		const blocking = lastBlock !== undefined && now - lastBlock.at < BLOCK_VISIBLE_MS;
		const right1 = blocking ? [...shield, state, ...statuses, ...codemode] : [state, ...shield, ...statuses, ...codemode];
		const line1 = line(width, modelLeft, right1, sep);

		// Line 2: context | cost, tokens
		const cu = ctx.getContextUsage();
		const pct = cu?.percent ?? null;
		const color = pct === null ? "muted" : pct > 85 ? "error" : pct > 65 ? "warning" : "success";
		const filled = pct === null ? 0 : Math.min(10, Math.round(pct / 10));
		const bar = theme.fg(color, "▰".repeat(filled)) + theme.fg("dim", "▱".repeat(10 - filled));
		const ctxText =
			pct === null
				? theme.fg("muted", `? / ${fmtTokens(cu?.contextWindow ?? model?.contextWindow ?? 0)}`)
				: theme.fg(color, `${pct.toFixed(0)}%`) +
					theme.fg("muted", ` · ${fmtTokens(cu?.tokens ?? 0)} / ${fmtTokens(cu?.contextWindow ?? 0)}`);
		// Billing follows the model that answered last (the routed one under router/auto).
		const sub = answered
			? isSubscription(ctx, answered.provider, answered.model)
			: model
				? ctx.modelRegistry.isUsingOAuth(model)
				: false;
		const costColor = usage.billed >= BUDGET * 2 ? "error" : usage.billed >= BUDGET ? "warning" : "text";
		const billedNote =
			sub && usage.billed > 0 ? theme.fg(costColor === "text" ? "muted" : costColor, ` · billed ${fmtCost(usage.billed)}`) : "";
		const costText = `💰 ${theme.fg(sub ? "text" : costColor, fmtCost(usage.cost))}${sub ? theme.fg("muted", " sub") : ""}${billedNote}`;
		const tokens = [
			`in ${fmtTokens(usage.input + usage.cacheRead + usage.cacheWrite)}`,
			`out ${fmtTokens(usage.output)}`,
			...(usage.cacheHit !== undefined ? [`cache ${usage.cacheHit.toFixed(0)}%`] : []),
		].join(" · ");
		const line2 = line(width, [`📊 ${bar} ${ctxText}`], [costText, theme.fg("muted", tokens)], sep);

		// Line 3: folder, git, session, scratchpad | classifier
		const home = process.env.HOME ?? "";
		let cwd = home && ctx.cwd.startsWith(home) ? `~${ctx.cwd.slice(home.length)}` : ctx.cwd;
		// Long paths keep only the last two folders so branch and changes stay visible.
		if (visibleWidth(cwd) > Math.max(20, Math.floor(width / 3))) cwd = `…/${cwd.split("/").slice(-2).join("/")}`;
		const branch = footerData?.getGitBranch();
		const changes = [
			git.added ? theme.fg("success", `+${git.added}`) : "",
			git.modified ? theme.fg("warning", `~${git.modified}`) : "",
			git.deleted ? theme.fg("error", `-${git.deleted}`) : "",
		]
			.filter(Boolean)
			.join(" ");
		const name = ctx.sessionManager.getSessionName();
		const where = [
			`📁 ${theme.fg("text", cwd)}${branch ? theme.fg("muted", ` ⎇ ${branch}`) : ""}${changes ? ` ${changes}` : ""}`,
			...(name ? [theme.fg("muted", name)] : []),
			...(openItems > 0 ? [theme.fg("muted", `🗂 ${openItems} open`)] : []),
		];
		const rows = classifierRows();
		const active = rows.filter((r) => r.status === "running");
		let cls: string[] = [];
		if (active.length > 0) {
			const models = [...new Set(active.map((r) => shortModel(r.args)))].join(", ");
			const spin = theme.fg("accent", `classifier ${SPINNER[frame]} ${active.length} running`);
			cls = [`🔎 ${spin}${theme.fg("muted", ` · ${models}`)}`, `🔎 ${spin}`, `🔎 ${theme.fg("accent", `${SPINNER[frame]} ${active.length}`)}`];
		} else if (lastRun && now - lastRunAt < DONE_VISIBLE_MS) {
			const parts = [`${lastRun.calls} call${lastRun.calls === 1 ? "" : "s"}`, `${(lastRun.ms / 1000).toFixed(1)}s`, fmtCost(lastRun.cost)];
			const err = lastRun.errors ? theme.fg("error", ` · ${lastRun.errors} failed`) : "";
			const errShort = lastRun.errors ? theme.fg("error", ` ${lastRun.errors}✗`) : "";
			cls = [
				`🔎 ${theme.fg("success", "classifier done")}${theme.fg("muted", ` · ${parts.join(" · ")}`)}${err}`,
				`🔎 ${theme.fg("success", `✓ ${lastRun.calls}`)}${errShort}`,
			];
		}
		const line3 = lineKeepRight(width, where, cls, sep);

		return [line1, line2, line3];
	}

	function install(ctx: ExtensionContext) {
		if (!ctx.hasUI || !enabled) return;
		ctx.ui.setFooter((tui, theme, data) => {
			footerData = data;
			requestRender = () => tui.requestRender();
			const unsub = data.onBranchChange(() => {
				void refreshGit(ctx);
				tui.requestRender();
			});
			return {
				dispose() {
					unsub();
					requestRender = undefined;
				},
				invalidate() {},
				render: (width: number) => renderFooter(width, theme),
			};
		});
	}

	const rowsFrom = (details: unknown): CallRow[] => {
		const calls = (details as { calls?: CallRow[] } | undefined)?.calls;
		return Array.isArray(calls) ? calls.filter((c) => c && typeof c.name === "string") : [];
	};

	// Event bus: safety extensions announce themselves and report blocks.
	pi.events.on("safety:active", (data) => {
		const name = (data as { name?: string })?.name;
		if (name) safety.add(name);
		render();
	});
	pi.events.on("safety:blocked", (data) => {
		lastBlock = { reason: String((data as { reason?: string })?.reason ?? "action"), at: Date.now() };
		renderLater(BLOCK_VISIBLE_MS);
		render();
	});

	// Event bus: classifier calls made directly by extensions (e.g. model-router).
	pi.events.on("classifier:start", (data) => {
		const d = data as { id?: string; model?: string };
		if (!d?.id) return;
		running.set(d.id, [{ name: "models.classify", args: String(d.model ?? "classifier"), status: "running" }]);
		updateTicker();
	});
	pi.events.on("classifier:end", (data) => {
		const d = data as { id?: string; status?: string; cost?: number; durationMs?: number };
		if (!d?.id) return;
		running.delete(d.id);
		lastRun = { calls: 1, errors: d.status === "error" ? 1 : 0, cost: d.cost ?? 0, ms: d.durationMs ?? 0 };
		lastRunAt = Date.now();
		renderLater(DONE_VISIBLE_MS);
		updateTicker();
	});

	pi.on("session_start", async (_event, ctx) => {
		ctxRef = ctx;
		usageKey = "";
		subscription.clear();
		running.clear();
		busySince = undefined;
		install(ctx);
		pi.events.emit("safety:ping", {});
		refreshScratchpad();
		void refreshGit(ctx);
	});

	pi.on("agent_start", async (_event, ctx) => {
		ctxRef = ctx;
		busySince ??= Date.now();
		updateTicker();
	});

	pi.on("agent_settled", async (_event, ctx) => {
		ctxRef = ctx;
		busySince = undefined;
		updateTicker();
		refreshScratchpad();
		void refreshGit(ctx);
	});

	for (const evt of ["model_select", "thinking_level_select", "turn_end"] as const) {
		pi.on(evt, async (_event, ctx) => {
			ctxRef = ctx;
			render();
		});
	}

	pi.on("tool_execution_update", async (event: any, ctx) => {
		if (event.toolName !== "codemode") return;
		ctxRef = ctx;
		running.set(event.toolCallId, rowsFrom(event.partialResult?.details));
		updateTicker();
	});

	pi.on("tool_execution_end", async (event: any, ctx) => {
		ctxRef = ctx;
		if (["write", "edit", "bash", "codemode"].includes(event.toolName)) void refreshGit(ctx);
		if (event.toolName === "scratchpad" || event.toolName === "codemode") refreshScratchpad();
		if (event.toolName !== "codemode") return;
		const rows = rowsFrom(event.result?.details).filter((r) => r.name === "models.classify");
		running.delete(event.toolCallId);
		if (rows.length > 0) {
			lastRun = {
				calls: rows.length,
				errors: rows.filter((r) => r.status === "error").length,
				cost: rows.reduce((s, r) => s + (r.cost ?? 0), 0),
				ms: event.durationMs ?? Math.max(...rows.map((r) => r.durationMs ?? 0)),
			};
			lastRunAt = Date.now();
			renderLater(DONE_VISIBLE_MS);
		}
		updateTicker();
	});

	pi.on("session_shutdown", async () => {
		if (ticker) clearInterval(ticker);
		ticker = undefined;
		for (const t of timers) clearTimeout(t);
		timers.clear();
	});

	pi.registerCommand("footer", {
		description: "Toggle between the status footer and pi's built-in footer",
		handler: async (_args, ctx) => {
			enabled = !enabled;
			ctxRef = ctx;
			if (enabled) install(ctx);
			else ctx.ui.setFooter(undefined);
			ctx.ui.notify(enabled ? "Status footer enabled" : "Built-in footer restored", "info");
		},
	});
}

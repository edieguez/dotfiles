/**
 * Status Footer: a clearer replacement for pi's built-in footer.
 *
 *   🧠 claude-opus-5-5 · anthropic · high                  ⏸ plan  codemode
 *   📊 ▰▰▰▱▱▱▱▱▱▱ 31% · 62k / 200k    💰 $0.412 sub    in 120k · out 9k · cache 92%
 *   📁 ~/Documents/journal ⎇ main · pi-setup        🔎 classifier ⠹ 3 running
 *
 * - Model line: selected model, provider, thinking level (theme colour), the
 *   model that actually answered when a virtual model routes requests, and
 *   modes reported by other extensions (e.g. plan mode) plus codemode.
 * - Usage line: context bar (green/yellow/red), session cost ("sub" when the
 *   provider is used through a subscription login), tokens and cache hit rate.
 * - Location line: folder, git branch, session name, and classifier activity:
 *   a spinner while `models.classify()` calls run inside codemode scripts,
 *   then a summary (calls, time, cost, errors) for 20 seconds.
 *
 * Segments are dropped by priority when the terminal is narrow.
 * `/footer` switches between this footer and the built-in one.
 *
 * Limitation: classifier calls made directly by extensions
 * (ctx.modelRegistry.classify) are not visible to other extensions.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, Theme } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const STATUS_KEY = "status-footer";
const DONE_VISIBLE_MS = 20_000;
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

type CallRow = { name: string; args: string; status: string; cost?: number; durationMs?: number };
type ClassifierSummary = { calls: number; errors: number; cost: number; ms: number; models: Set<string> };

const fmtTokens = (n: number) =>
	n < 1000 ? `${n}` : n < 10_000 ? `${(n / 1000).toFixed(1)}k` : n < 1e6 ? `${Math.round(n / 1000)}k` : `${(n / 1e6).toFixed(1)}M`;
const fmtCost = (n: number) => (n === 0 ? "$0" : n < 0.01 ? `$${n.toFixed(4)}` : `$${n.toFixed(3)}`);
const shortModel = (ref: string) => ref.split("/").pop() ?? ref;

/** Join left and right parts on one line; drop right parts that do not fit. */
function line(width: number, left: string[], right: string[], sep: string): string {
	let l = left.join(sep);
	const r: string[] = [];
	for (const part of right) {
		const candidate = [...r, part].join("  ");
		if (visibleWidth(l) + 2 + visibleWidth(candidate) <= width) r.push(part);
	}
	const rs = r.join("  ");
	if (!rs) return truncateToWidth(l, width, "…");
	l = truncateToWidth(l, Math.max(1, width - visibleWidth(rs) - 2), "…");
	return l + " ".repeat(Math.max(2, width - visibleWidth(l) - visibleWidth(rs))) + rs;
}

/** Keep left segments in order while they fit (first segment always kept). */
function fit(width: number, segments: string[], sep: string): string[] {
	const out: string[] = [];
	for (const s of segments) {
		if (out.length === 0 || visibleWidth([...out, s].join(sep)) <= width) out.push(s);
	}
	return out;
}

export default function (pi: ExtensionAPI) {
	let enabled = true;
	let ctxRef: ExtensionContext | undefined;
	let requestRender: (() => void) | undefined;

	// Classifier tracking: rows per codemode tool call
	const running = new Map<string, CallRow[]>();
	let lastRun: ClassifierSummary | undefined;
	let lastRunAt = 0;
	let spinnerFrame = 0;
	let spinnerTimer: ReturnType<typeof setInterval> | undefined;
	let hideTimer: ReturnType<typeof setTimeout> | undefined;

	// Usage cache (the footer renders often)
	let usageKey = "";
	let usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, cacheHit: undefined as number | undefined };
	let routed: string | undefined;

	function classifierRows(): CallRow[] {
		return [...running.values()].flat().filter((r) => r.name === "models.classify");
	}

	function updateSpinner() {
		const active = classifierRows().some((r) => r.status === "running");
		if (active && !spinnerTimer) {
			spinnerTimer = setInterval(() => {
				spinnerFrame = (spinnerFrame + 1) % SPINNER.length;
				requestRender?.();
			}, 100);
		} else if (!active && spinnerTimer) {
			clearInterval(spinnerTimer);
			spinnerTimer = undefined;
		}
		requestRender?.();
	}

	function rowsFrom(details: unknown): CallRow[] {
		const calls = (details as { calls?: CallRow[] } | undefined)?.calls;
		return Array.isArray(calls) ? calls.filter((c) => c && typeof c.name === "string") : [];
	}

	function computeUsage(ctx: ExtensionContext) {
		const sm = ctx.sessionManager;
		const key = `${sm.getSessionId()}|${sm.getLeafId()}|${sm.getEntries().length}`;
		if (key === usageKey) return;
		usageKey = key;
		const u = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, cacheHit: undefined as number | undefined };
		const add = (x?: { input: number; output: number; cacheRead: number; cacheWrite: number; cost: { total: number } }) => {
			if (!x) return;
			u.input += x.input;
			u.output += x.output;
			u.cacheRead += x.cacheRead;
			u.cacheWrite += x.cacheWrite;
			u.cost += x.cost.total;
		};
		let last: AssistantMessage | undefined;
		for (const e of sm.getEntries() as any[]) {
			if (e.type === "usage") add(e.usage);
			else if ((e.type === "compaction" || e.type === "branch_summary") && e.usage) add(e.usage);
			else if (e.type === "message" && e.message.role === "toolResult") add(e.message.usage);
			else if (e.type === "message" && e.message.role === "assistant") {
				const m = e.message as AssistantMessage;
				add(m.usage);
				last = m;
				const prompt = m.usage.input + m.usage.cacheRead + m.usage.cacheWrite;
				u.cacheHit = prompt > 0 ? (m.usage.cacheRead / prompt) * 100 : undefined;
			}
		}
		usage = u;
		routed = last && ctx.model && last.model !== ctx.model.id ? last.model : undefined;
	}

	function renderFooter(width: number, theme: Theme): string[] {
		const ctx = ctxRef;
		if (!ctx) return [];
		computeUsage(ctx);
		const sep = theme.fg("dim", " · ");
		const model = ctx.model;

		// Line 1: model
		const level = pi.getThinkingLevel();
		const levelColor = (`thinking${level[0].toUpperCase()}${level.slice(1)}`) as any;
		const modelLeft = [
			`🧠 ${theme.bold(theme.fg("accent", model?.id ?? "no model"))}`,
			...(routed ? [theme.fg("accent", `→ ${routed}`)] : []),
			...(model?.reasoning ? [theme.fg(levelColor, level === "off" ? "thinking off" : level)] : []),
			...(model ? [theme.fg("muted", model.provider)] : []),
		];
		const statuses = [...((footerData?.getExtensionStatuses() ?? new Map()) as ReadonlyMap<string, string>).entries()]
			.filter(([k]) => k !== STATUS_KEY)
			.sort(([a], [b]) => a.localeCompare(b))
			.map(([, v]) => v.replace(/\s+/g, " ").trim());
		const modes = [...statuses, ...(pi.getActiveTools().includes("codemode") ? [theme.fg("dim", "codemode")] : [])];
		const line1 = line(width, fit(width, modelLeft, sep), modes, sep);

		// Line 2: context, cost, tokens
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
		const sub = model && ctx.modelRegistry.isUsingOAuth(model);
		const costText = `💰 ${theme.fg("text", fmtCost(usage.cost))}${sub ? theme.fg("muted", " sub") : ""}`;
		const tokens = [
			`in ${fmtTokens(usage.input + usage.cacheRead + usage.cacheWrite)}`,
			`out ${fmtTokens(usage.output)}`,
			...(usage.cacheHit !== undefined ? [`cache ${usage.cacheHit.toFixed(0)}%`] : []),
		].join(" · ");
		const line2 = line(width, [`📊 ${bar} ${ctxText}`], [costText, theme.fg("muted", tokens)], sep);

		// Line 3: location + classifier
		const home = process.env.HOME ?? "";
		const cwd = ctx.cwd.startsWith(home) ? `~${ctx.cwd.slice(home.length)}` : ctx.cwd;
		const branch = footerData?.getGitBranch();
		const name = ctx.sessionManager.getSessionName();
		const where = [
			`📁 ${theme.fg("text", cwd)}${branch ? theme.fg("muted", ` ⎇ ${branch}`) : ""}`,
			...(name ? [theme.fg("muted", name)] : []),
		];
		const rows = classifierRows();
		const active = rows.filter((r) => r.status === "running");
		// Classifier status, longest form first; the first form that fits is used.
		let cls: string[] = [];
		if (active.length > 0) {
			const models = [...new Set(active.map((r) => shortModel(r.args)))].join(", ");
			const spin = theme.fg("accent", `classifier ${SPINNER[spinnerFrame]} ${active.length} running`);
			cls = [
				`🔎 ${spin}${theme.fg("muted", ` · ${models}`)}`,
				`🔎 ${spin}`,
				`🔎 ${theme.fg("accent", `${SPINNER[spinnerFrame]} ${active.length}`)}`,
			];
		} else if (lastRun && Date.now() - lastRunAt < DONE_VISIBLE_MS) {
			const parts = [`${lastRun.calls} call${lastRun.calls === 1 ? "" : "s"}`, `${(lastRun.ms / 1000).toFixed(1)}s`, fmtCost(lastRun.cost)];
			const err = lastRun.errors ? theme.fg("error", ` · ${lastRun.errors} failed`) : "";
			const errShort = lastRun.errors ? theme.fg("error", ` ${lastRun.errors}✗`) : "";
			cls = [
				`🔎 ${theme.fg("success", "classifier done")}${theme.fg("muted", ` · ${parts.join(" · ")}`)}${err}`,
				`🔎 ${theme.fg("success", `✓ ${lastRun.calls}`)}${errShort}`,
			];
		}
		const whereFit = fit(width, where, sep);
		const clsForm = cls.find((c) => visibleWidth(whereFit.join(sep)) + 2 + visibleWidth(c) <= width) ?? cls[cls.length - 1];
		// The classifier is never dropped: the folder is truncated instead.
		const line3 = clsForm
			? (() => {
					const l = truncateToWidth(whereFit.join(sep), Math.max(1, width - visibleWidth(clsForm) - 2), "…");
					return l + " ".repeat(Math.max(2, width - visibleWidth(l) - visibleWidth(clsForm))) + clsForm;
				})()
			: truncateToWidth(whereFit.join(sep), width, "…");

		return [line1, line2, line3];
	}

	let footerData: { getGitBranch(): string | null; getExtensionStatuses(): ReadonlyMap<string, string> } | undefined;

	function install(ctx: ExtensionContext) {
		if (!ctx.hasUI || !enabled) return;
		ctx.ui.setFooter((tui, theme, data) => {
			footerData = data;
			requestRender = () => tui.requestRender();
			const unsub = data.onBranchChange(() => tui.requestRender());
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

	pi.on("session_start", async (_event, ctx) => {
		ctxRef = ctx;
		usageKey = "";
		running.clear();
		install(ctx);
	});

	for (const evt of ["model_select", "thinking_level_select", "turn_end", "agent_settled"] as const) {
		pi.on(evt, async (_event, ctx) => {
			ctxRef = ctx;
			requestRender?.();
		});
	}

	pi.on("tool_execution_update", async (event: any, ctx) => {
		if (event.toolName !== "codemode") return;
		ctxRef = ctx;
		running.set(event.toolCallId, rowsFrom(event.partialResult?.details));
		updateSpinner();
	});

	pi.on("tool_execution_end", async (event: any, ctx) => {
		if (event.toolName !== "codemode") return;
		ctxRef = ctx;
		const rows = rowsFrom(event.result?.details).filter((r) => r.name === "models.classify");
		running.delete(event.toolCallId);
		if (rows.length > 0) {
			lastRun = {
				calls: rows.length,
				errors: rows.filter((r) => r.status === "error").length,
				cost: rows.reduce((s, r) => s + (r.cost ?? 0), 0),
				ms: event.durationMs ?? Math.max(...rows.map((r) => r.durationMs ?? 0)),
				models: new Set(rows.map((r) => r.args)),
			};
			lastRunAt = Date.now();
			if (hideTimer) clearTimeout(hideTimer);
			hideTimer = setTimeout(() => requestRender?.(), DONE_VISIBLE_MS + 50);
		}
		updateSpinner();
	});

	pi.on("session_shutdown", async () => {
		if (spinnerTimer) clearInterval(spinnerTimer);
		if (hideTimer) clearTimeout(hideTimer);
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

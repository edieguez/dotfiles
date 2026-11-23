/**
 * Permission Gate (adapted from pi's examples/extensions/permission-gate.ts)
 *
 * Asks for confirmation before risky shell commands. Also applies to bash
 * calls made from codemode scripts, which go through the same tool_call hook.
 * Without a UI (print/JSON mode) the command is blocked.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * `git restore` discards work unless it only unstages (`--staged`/`-S`
 * without `--worktree`/`-W`).
 */
function restoreDiscards(command: string): boolean {
	for (const m of command.matchAll(/\bgit\s+restore\b([^|;&\n]*)/g)) {
		const args = ` ${m[1]} `;
		const staged = /\s(?:--staged|-[a-zA-Z]*S[a-zA-Z]*)(?=\s)/.test(args);
		const worktree = /\s(?:--worktree|-[a-zA-Z]*W[a-zA-Z]*)(?=\s)/.test(args);
		if (!staged || worktree) return true;
	}
	return false;
}

export const RULES: { label: string; test: (command: string) => boolean }[] = [
	// rm with -r/-R/--recursive anywhere in its arguments: -rf, -fr, -r -f, `rm dir -rf`
	{ label: "recursive delete", test: (c) => /\brm\b[^|;&\n]*\s(?:-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)(?=\s|$)/.test(c) },
	{ label: "find -delete", test: (c) => /\bfind\b[^|;&\n]*\s-delete\b/.test(c) },
	{ label: "sudo", test: (c) => /\bsudo\b/.test(c) },
	{ label: "world-writable permissions", test: (c) => /\b(?:chmod|chown)\b.*\b777\b/.test(c) },
	// -f, --force, --force-with-lease, or a +refspec (`git push origin +main`)
	{ label: "force push", test: (c) => /\bgit\s+push\b[^|;&\n]*(?:\s-[a-zA-Z]*f\b|--force|\s\+\S)/.test(c) },
	{
		label: "discard git changes",
		test: (c) => /\bgit\s+(?:reset\s+--hard|clean\s+-[a-zA-Z]*f|checkout\s+--\s)/.test(c) || restoreDiscards(c),
	},
	{ label: "download and execute", test: (c) => /\b(?:curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:ba|z)?sh\b/.test(c) },
	{ label: "disk-level write", test: (c) => /\b(?:dd\s+.*\bof=|mkfs|diskutil\s+(?:erase|partition))/.test(c) },
];

export const risks = (command: string) => RULES.filter((r) => r.test(command)).map((r) => r.label);

export default function (pi: ExtensionAPI) {
	// Announce to the status footer (shared event bus); answer its ping too.
	const announce = () => pi.events.emit("safety:active", { name: "permission-gate" });
	pi.on("session_start", async () => announce());
	pi.events.on("safety:ping", announce);
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = String(event.input.command ?? "");
		const matched = risks(command);
		if (matched.length === 0) return undefined;

		if (!ctx.hasUI) {
			pi.events.emit("safety:blocked", { name: "permission-gate", reason: matched.join(", ") });
			return { block: true, reason: `Risky command blocked (${matched.join(", ")}); no UI to confirm` };
		}

		const choice = await ctx.ui.select(`⚠️ Risky command (${matched.join(", ")}):\n\n  ${command}\n\nAllow?`, [
			"Yes",
			"No",
		]);
		if (choice !== "Yes") {
			pi.events.emit("safety:blocked", { name: "permission-gate", reason: matched.join(", ") });
			return { block: true, reason: "Blocked by user" };
		}
		return undefined;
	});
}

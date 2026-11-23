/**
 * Permission Gate (adapted from pi's examples/extensions/permission-gate.ts)
 *
 * Asks for confirmation before risky shell commands. Also applies to bash
 * calls made from codemode scripts, which go through the same tool_call hook.
 * Without a UI (print/JSON mode) the command is blocked.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RULES: { label: string; pattern: RegExp }[] = [
	// rm with -r/-R/--recursive in any flag combination: -rf, -fr, -r -f, -Rf
	{ label: "recursive delete", pattern: /\brm\s+(?:-[a-zA-Z]+\s+)*-[a-zA-Z]*[rR]|\brm\s+.*--recursive/ },
	{ label: "sudo", pattern: /\bsudo\b/ },
	{ label: "world-writable permissions", pattern: /\b(?:chmod|chown)\b.*\b777\b/ },
	{ label: "force push", pattern: /\bgit\s+push\b.*(?:\s-f\b|--force)/ },
	{ label: "discard git changes", pattern: /\bgit\s+(?:reset\s+--hard|clean\s+-[a-zA-Z]*f|checkout\s+--\s|restore\b)/ },
	{ label: "download and execute", pattern: /\b(?:curl|wget)\b[^|]*\|\s*(?:sudo\s+)?(?:ba|z)?sh\b/ },
	{ label: "disk-level write", pattern: /\b(?:dd\s+.*\bof=|mkfs|diskutil\s+(?:erase|partition))/ },
];

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = String(event.input.command ?? "");
		const matched = RULES.filter((r) => r.pattern.test(command)).map((r) => r.label);
		if (matched.length === 0) return undefined;

		if (!ctx.hasUI) {
			return { block: true, reason: `Risky command blocked (${matched.join(", ")}); no UI to confirm` };
		}

		const choice = await ctx.ui.select(`⚠️ Risky command (${matched.join(", ")}):\n\n  ${command}\n\nAllow?`, [
			"Yes",
			"No",
		]);
		if (choice !== "Yes") {
			return { block: true, reason: "Blocked by user" };
		}
		return undefined;
	});
}

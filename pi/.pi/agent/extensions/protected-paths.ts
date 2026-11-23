/**
 * Protected Paths (adapted from pi's examples/extensions/protected-paths.ts)
 *
 * Blocks the read/write/edit tools on sensitive paths. Paths are resolved
 * against the session's working directory and `~` is expanded, so relative
 * and absolute spellings are treated the same. Also applies to calls made from
 * codemode scripts.
 *
 * Limitation: this guards pi's file tools only. A bash command could still
 * touch these files; permission-gate.ts covers the most destructive commands.
 */

import { homedir } from "node:os";
import { basename, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HOME = homedir();

/** Secrets: never read or changed through pi's file tools. */
const SECRET_DIRS = [`${HOME}/.ssh`, `${HOME}/.aws`, `${HOME}/.gnupg`];
const SECRET_FILES = [`${HOME}/.pi/agent/auth.json`];

/** Not edited directly (managed by tools), but may be read. */
const NO_WRITE_SEGMENTS = [`${sep}.git${sep}`, `${sep}node_modules${sep}`];

function isEnvFile(path: string): boolean {
	const name = basename(path);
	// .env, .env.local, .env.production... but not templates like .env.example
	return /^\.env(\..+)?$/.test(name) && !/\.(example|sample|template)$/.test(name);
}

function normalize(input: string, cwd: string): string {
	const expanded = input === "~" ? HOME : input.startsWith("~/") ? HOME + input.slice(1) : input;
	return resolve(cwd, expanded);
}

function isSecret(path: string): boolean {
	return (
		SECRET_FILES.includes(path) ||
		SECRET_DIRS.some((dir) => path === dir || path.startsWith(dir + sep)) ||
		isEnvFile(path)
	);
}

export default function (pi: ExtensionAPI) {
	// Announce to the status footer (shared event bus); answer its ping too.
	const announce = () => pi.events.emit("safety:active", { name: "protected-paths" });
	pi.on("session_start", async () => announce());
	pi.events.on("safety:ping", announce);
	pi.on("tool_call", async (event, ctx) => {
		const tool = event.toolName;
		if (tool !== "read" && tool !== "write" && tool !== "edit") return undefined;

		const raw = event.input.path;
		if (typeof raw !== "string" || raw.length === 0) return undefined;
		const path = normalize(raw, ctx.cwd);

		let reason: string | undefined;
		if (isSecret(path)) {
			reason = `"${raw}" holds secrets and is protected from ${tool}`;
		} else if (tool !== "read" && NO_WRITE_SEGMENTS.some((s) => (path + sep).includes(s))) {
			reason = `"${raw}" is managed by tools (git/npm) and is protected from ${tool}`;
		}
		if (!reason) return undefined;

		if (ctx.hasUI) ctx.ui.notify(`Blocked: ${reason}`, "warning");
		pi.events.emit("safety:blocked", { name: "protected-paths", reason: `protected ${basename(path)}` });
		return { block: true, reason };
	});
}

/**
 * Protected Paths (adapted from pi's examples/extensions/protected-paths.ts)
 *
 * Blocks the read/write/edit tools on sensitive paths. Paths are resolved
 * against the session's working directory and `~` is expanded, so relative
 * and absolute spellings are treated the same. Symlinks are resolved too, so a
 * link pointing into a protected folder is blocked. Also applies to calls made
 * from codemode scripts.
 *
 * Limitation: this guards pi's file tools only. A bash command could still
 * touch these files; permission-gate.ts covers the most destructive commands.
 */

import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HOME = homedir();

/** Secrets: never read or changed through pi's file tools. */
const SECRET_DIRS = [`${HOME}/.ssh`, `${HOME}/.aws`, `${HOME}/.gnupg`];
const SECRET_FILES = [`${HOME}/.pi/agent/auth.json`, `${HOME}/.git-credentials`];

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

/**
 * Resolves symlinks. For a path that does not exist yet (a new file), resolves
 * its nearest existing parent and keeps the rest as written.
 */
export function realPath(path: string): string {
	const rest: string[] = [];
	let dir = path;
	while (true) {
		try {
			return join(realpathSync(dir), ...rest.reverse());
		} catch {
			const parent = dirname(dir);
			if (parent === dir) return path;
			rest.push(basename(dir));
			dir = parent;
		}
	}
}

const SECRET_DIRS_REAL = SECRET_DIRS.map(realPath);
const SECRET_FILES_REAL = SECRET_FILES.map(realPath);

function isSecret(path: string): boolean {
	return (
		[...SECRET_FILES, ...SECRET_FILES_REAL].includes(path) ||
		[...SECRET_DIRS, ...SECRET_DIRS_REAL].some((dir) => path === dir || path.startsWith(dir + sep)) ||
		isEnvFile(path)
	);
}

/** Why a tool may not touch this path, or undefined when allowed. Checks the path as written and resolved. */
export function protectedReason(raw: string, tool: string, cwd: string): string | undefined {
	const path = normalize(raw, cwd);
	const paths = [path, realPath(path)];
	if (paths.some(isSecret)) return `"${raw}" holds secrets and is protected from ${tool}`;
	if (tool !== "read" && paths.some((p) => NO_WRITE_SEGMENTS.some((s) => (p + sep).includes(s)))) {
		return `"${raw}" is managed by tools (git/npm) and is protected from ${tool}`;
	}
	return undefined;
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
		const reason = protectedReason(raw, tool, ctx.cwd);
		if (!reason) return undefined;

		if (ctx.hasUI) ctx.ui.notify(`Blocked: ${reason}`, "warning");
		pi.events.emit("safety:blocked", { name: "protected-paths", reason: `protected ${basename(raw)}` });
		return { block: true, reason };
	});
}

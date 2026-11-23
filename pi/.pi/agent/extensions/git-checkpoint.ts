/**
 * Git Checkpoint (adapted from pi's examples/extensions/git-checkpoint.ts)
 *
 * Before each agent turn, snapshots the working tree with `git stash create`
 * (does not touch your files or the stash list). When you /fork from an
 * earlier message, offers to restore tracked files to how they were then.
 *
 * Changes from the example:
 * - Checkpoints are kept for the whole session. The example cleared them when
 *   each run ended, which is exactly when /fork is used, so it never restored.
 * - A clean tree is recorded as HEAD instead of being skipped.
 * - Restore replaces tracked files with the snapshot (`git restore`) instead of
 *   merging it (`git stash apply`), and first saves the current state to the
 *   stash list so the restore can be undone.
 *
 * Limitations: only inside a git repository; untracked files are neither
 * captured nor deleted; checkpoints live in memory (lost when pi exits).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MAX_CHECKPOINTS = 200;

export default function (pi: ExtensionAPI) {
	// Announce to the status footer (shared event bus); answer its ping too.
	const announce = () => pi.events.emit("safety:active", { name: "git-checkpoint" });
	pi.on("session_start", async () => announce());
	pi.events.on("safety:ping", announce);
	const checkpoints = new Map<string, string>();

	async function git(cwd: string, args: string[]) {
		return pi.exec("git", args, { cwd, timeout: 15_000 });
	}

	async function snapshot(cwd: string): Promise<string | undefined> {
		const inside = await git(cwd, ["rev-parse", "--is-inside-work-tree"]);
		if (inside.code !== 0) return undefined;
		const stash = await git(cwd, ["stash", "create"]);
		const ref = stash.stdout.trim();
		if (ref) return ref;
		const head = await git(cwd, ["rev-parse", "HEAD"]);
		return head.code === 0 ? head.stdout.trim() : undefined;
	}

	pi.on("session_start", async () => {
		checkpoints.clear();
	});

	pi.on("turn_start", async (_event, ctx) => {
		const entryId = ctx.sessionManager.getLeafId();
		if (!entryId || checkpoints.has(entryId)) return;
		const ref = await snapshot(ctx.cwd);
		if (!ref) return;
		checkpoints.set(entryId, ref);
		if (checkpoints.size > MAX_CHECKPOINTS) {
			const oldest = checkpoints.keys().next().value;
			if (oldest) checkpoints.delete(oldest);
		}
	});

	pi.on("session_before_fork", async (event, ctx) => {
		const ref = checkpoints.get(event.entryId);
		if (!ref || !ctx.hasUI) return;

		const choice = await ctx.ui.select("Restore code to how it was at that message?", [
			"Yes, restore tracked files",
			"No, keep current code",
		]);
		if (!choice?.startsWith("Yes")) return;

		// Keep the current state recoverable: `git stash list` shows it.
		const current = (await git(ctx.cwd, ["stash", "create"])).stdout.trim();
		if (current) {
			await git(ctx.cwd, ["stash", "store", "-m", "pi git-checkpoint: before restore", current]);
		}

		const restore = await git(ctx.cwd, ["restore", `--source=${ref}`, "--staged", "--worktree", "--", "."]);
		if (restore.code === 0) {
			const undo = current ? " Previous state saved in `git stash list`." : "";
			ctx.ui.notify(`Code restored to checkpoint ${ref.slice(0, 8)}.${undo}`, "info");
		} else {
			ctx.ui.notify(`Restore failed: ${restore.stderr.trim()}`, "error");
		}
	});
}

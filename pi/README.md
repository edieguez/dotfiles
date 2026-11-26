# pi

Configuration for the [Pi coding agent](https://pi.dev), stowed into
`~/.pi/agent/`.

## Contents

- `settings.json`: default model (`router/auto`), tools (`+codemode`),
  `/share` destination (`auto`: Radius when logged in, otherwise a gist) and
  packages (`pi-memory`, installed automatically by Pi at startup).
- `AGENTS.md`: user-wide instructions (Markdown rules, classifier choice).
- `mcp.json`: MCP servers. Credentials are not stored here.
- `extensions/`:
  - `permission-gate.ts`: asks before risky shell commands.
  - `protected-paths.ts`: blocks file tools on secrets, `.git/` and
    `node_modules/`.
  - `git-checkpoint.ts`: restores code when using `/fork`.
  - `status-footer.ts`: clearer footer with classifier activity (`/footer`).
  - `model-router/`: `router/auto` picks a model per task (easy, medium,
    hard) with the free classifier; `/route` forces a level. Models,
    classifier and private folders are in `model-router/config.json`; a
    machine can override them in `~/.pi/agent/model-router.json` (not
    versioned, e.g. `{ "tiers": { "easy": ["anthropic/claude-haiku-5-5"] } }`).
    Tiers without credentials fall back to other tiers, then to any logged-in
    model, so the default `router/auto` works with any provider.
  - `plan-mode`, `subagent`: copies of Pi's bundled examples (not links, so
    they work wherever Pi is installed; refresh them by hand after major Pi
    upgrades).
- `agents/`, `prompts/`: the subagent example's agents and prompts (copies).
- `bootstrap.sh`: sets up a new machine (see below).
- `prompts/commit.md`, `prompts/review.md`: `/commit` proposes a commit in
  the repository's style and commits only after approval (never pushes);
  `/review` reviews uncommitted changes or a range without editing.

## Not versioned

These stay only in `~/.pi/agent/` because they are secret, personal or
generated: `auth.json`, `sessions/`, `memory/`, `models-store.json`, `npm/`.
The root `.gitignore` also excludes them in case they end up in the package.

Skills live in `~/.agents/skills/`. This package versions `pdf-tools`
(`.agents/skills/pdf-tools`, stowed as a link): it reads PDFs with poppler
(`brew install poppler`), including pages rendered as images. Not versioned:

- `rex`: a stub installed by `rex skill setup`; reinstall it with that
  command.
- `whatsapp`: contains personal data, so it is not versioned yet. Back it up
  separately until it is made generic.

## Setup on a new machine

```sh
brew install pi-coding-agent stow jq
cd ~/.dotfiles && pi/bootstrap.sh    # stow, git filter, login check
pi auth login anthropic              # main models (any provider works)
pi auth login openrouter --api-key   # optional: router classifier
pi auth login github-copilot         # optional: router "easy" tier
pi auth login radius                 # optional: MCP server and web search
rex skill setup                      # Rex skill for agents (optional)
```

Pi writes `settings.json` and `mcp.json` in place, so changes made with
`/settings`, `pi install` or `pi mcp add` go through the symlinks into this
repository. Review them with `git diff` before committing.

Pi also records its own version fields in `settings.json`
(`lastChangelogVersion`, `extensionChangelogVersions`). A git filter in the
root `.gitattributes` leaves them out of diffs and commits; the file on disk
keeps them. The filter itself is not versioned, and `bootstrap.sh` sets it up.

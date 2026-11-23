# pi

Configuration for the [Pi coding agent](https://pi.dev), stowed into
`~/.pi/agent/`.

## Contents

- `settings.json`: default model, tools (`+codemode`) and packages
  (`pi-memory`, installed automatically by Pi at startup).
- `AGENTS.md`: user-wide instructions (Markdown rules, classifier choice).
- `mcp.json`: MCP servers. Credentials are not stored here.
- `extensions/`:
  - `permission-gate.ts`: asks before risky shell commands.
  - `protected-paths.ts`: blocks file tools on secrets, `.git/` and
    `node_modules/`.
  - `git-checkpoint.ts`: restores code when using `/fork`.
  - `status-footer.ts`: clearer footer with classifier activity (`/footer`).
  - `model-router.ts`: `router/auto` picks Opus, Sonnet or Copilot per task
    with the free classifier; `/route` forces a level.
  - `plan-mode`, `subagent`: links to Pi's bundled examples (Homebrew).
- `agents/`, `prompts/`: links to the subagent example's agents and prompts.

## Not versioned

These stay only in `~/.pi/agent/` because they are secret, personal or
generated: `auth.json`, `sessions/`, `memory/`, `models-store.json`, `npm/`.
The root `.gitignore` also excludes them in case they end up in the package.

## Setup on a new machine

```sh
brew install pi-coding-agent
cd ~/.dotfiles && stow pi
pi auth login openrouter --api-key   # classifiers
pi auth login radius                 # MCP server and web search
rex skill setup                      # Rex skill for agents (optional)
```

Pi writes `settings.json` and `mcp.json` in place, so changes made with
`/settings`, `pi install` or `pi mcp add` go through the symlinks into this
repository. Review them with `git diff` before committing.

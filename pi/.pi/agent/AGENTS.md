# Guidelines

## Environment

- Editor: Neovim. Terminal: Rex from Superlogical. Shell: ZSH
- Operating system: macOS (MacBook Pro)
- Available CLI tools: `rg`, `fd`, `jq`, `gh`, `bat`, `delta`, `uv`, `bun`.
  - Prefer them over slower or missing alternatives.
  - If they are not installed, offer the command to do so. Ask if the user wants to manually installed them or want you
    to do so.
- Python: use `uv` (`uv run`, `uv add`); never `pip install` globally.
- Many files in `~` are GNU Stow symlinks into `~/.dotfiles`. Check with
  `ls -l` before editing; edit the target and never replace a symlink with
  a regular file.

## Working style

- Make small, focused changes and match the existing code style.
- Do not reformat code or text you were not asked to change.
- Ask before large or ambiguous changes, and before adding dependencies.
- Before saying a task is done, run the relevant tests or linters. Say what
  you could not verify.

## Git

- Never commit, push, amend, rebase or discard changes unless asked.
- Follow each repository's commit style; check `git log` first.
- Stage files explicitly; never commit secrets or generated files.
- Do not add co authorship

## Memory

- MEMORY.md: durable decisions and preferences only.
- Daily log: running context of the current work.
- Scratchpad: follow-ups to do later.

## Markdown

- When creating or editing Markdown files, follow markdownlint rules: the
  project's `.markdownlint*` file if present, otherwise the Neovim config
  `~/.config/nvim/.markdownlint.yaml`.
- Check edited files and fix the errors you introduced before finishing:
  `npx -y markdownlint-cli2 <file>` in projects with their own config,
  otherwise `npx -y markdownlint-cli2 --config ~/.config/nvim/.markdownlint.yaml <file>`.
- Common rules: lines up to 120 characters (MD013 is off in the Neovim config, so the linter
  does not check it), nested list indent of
  2 spaces (MD007), spaces around table pipes (MD060), blank lines around
  headings, lists and code blocks.

## Classifier models

- Default classifier: `openrouter/perplexity/pplx-decider-v1.3:free` (free).
  Use it for all `models.classify()` calls unless told otherwise.
- `openrouter/typesafe/jev-1.14` is paid (OpenRouter credits, limited PoC
  budget). Use it only when the user explicitly asks for Jev.
- Free models may log requests: do not send private journal content
  (`~/Documents/journal`) to them without asking; suggest Jev for sensitive
  data.
- If the free model is rate-limited, slow down or ask before falling back to
  Jev.

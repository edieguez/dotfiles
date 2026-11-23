# User preferences

## Markdown

- When creating or editing Markdown files, follow markdownlint rules
  (default config, or the project's `.markdownlint*` file if present).
- Check edited files with `npx -y markdownlint-cli2 <file>` and fix the errors
  you introduced before finishing.
- Common rules: lines up to 80 characters (MD013), nested list indent of
  2 spaces (MD007), spaces around table pipes (MD060), blank lines around
  headings, lists and code blocks.
- Tables cannot be wrapped: if rows exceed 80 characters, use lists instead.
- Do not reformat parts of a file you were not asked to change.

## Classifier models

- Default classifier: `openrouter/perplexity/pplx-decider-v1.3:free` (free).
  Use it for all `models.classify()` calls unless told otherwise.
- `openrouter/typesafe/jev-1.14` is paid (OpenRouter credits, limited PoC
  budget). Use it only when the user explicitly asks for Jev.
- Free models may log requests: do not send private journal content to them
  without asking; suggest Jev for sensitive data.
- If the free model is rate-limited, slow down or ask before falling back to
  Jev.

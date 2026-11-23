---
description: Propose a commit in the repository's style and commit on approval
argument-hint: "[hint]"
---
Prepare a git commit for the current changes.

Extra instructions: ${@:-none}

1. Run `git status`, `git diff` and `git diff --staged`. Read
   `git log --oneline -15` to learn the repository's commit style
   (prefixes, tags, language, tense, length).
2. Decide which files belong in this commit. Leave out secrets, generated
   files and unrelated changes; mention anything you left out and why.
3. Show me the proposed message and the exact list of files to stage, then
   stop and wait for my approval.
4. After I approve, stage those files by name (never `git add -A` or
   `git add .`) and commit with the approved message.

Never push, amend, rebase or add co-authors.

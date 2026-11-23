---
description: Review uncommitted changes or a git range, without editing
argument-hint: "[ref or range]"
---
Review ${@:-the uncommitted changes (staged and unstaged)}.

1. Read the diff (`git diff`, `git diff --staged`, or `git diff <range>`).
   Open the surrounding code when the diff alone is not enough to judge.
2. Report findings ordered by severity:
   1. Bugs and incorrect behavior
   2. Security and privacy issues
   3. Missing edge cases, error handling and tests
   4. Style and readability, only where it matters
3. For each finding, give the file and line, the problem, and a suggested
   fix. Say so when something is a guess rather than a certainty.
4. End with a short overall verdict.

Do not edit files, stage or commit. Wait for me to choose what to fix.

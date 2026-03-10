---
name: claude-review
description: "Self-review quality gate using Claude CLI. When the user says 'review your work', 'use review-work', or 'check your output', identify every file you created or modified and run `review-work <file> \"<task>\"` on each one. You determine file paths and task description yourself — the user does NOT need to specify them. Requires `claude` CLI installed."
license: MIT
metadata:
  version: "1.2.0"
  tags:
    - quality
    - review
    - self-review
    - code review
    - quality gate
    - claude cli
    - learnings
  triggers:
    - "review your work"
    - "use review-work"
    - "check your output"
    - "self-review"
    - "quality check"
    - "review before finishing"
---

# claude-review — Self-Review Quality Gate

Uses Claude CLI (`claude --print`) as an independent reviewer to catch errors, missed requirements, and quality issues in your work before delivering to the user.

## How It Works

1. You complete your task and save output to file(s)
2. `review-work` sends each file to a separate Claude instance for independent review
3. The reviewer checks for accuracy, completeness, quality, and missed requirements
4. Issues are returned with severity ratings (critical / major / minor)
5. You fix issues and re-review until clean

The reviewer is a **separate Claude instance** — it has no context of your conversation, so it reviews purely on merit. This catches blind spots you'd miss reviewing your own work.

**Auto-learning:** When a review fails (VERDICT: FAIL), critical and major issues are automatically logged to `LESSONS.md`. This builds a persistent record of common mistakes so you can avoid repeating them. Check this file before starting tasks in areas you've worked before.

## Prerequisites

- `claude` CLI must be installed and available in PATH (`npm install -g @anthropic-ai/claude-code`)
- Valid API key configured for Claude CLI

## Command

```bash
review-work <file_path> "<task_description>" [--skill <skill_file>]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `file_path` | Yes | Path to the file to review |
| `task_description` | No | What the file was supposed to accomplish |
| `--skill <path>` | No | Path to the SKILL.md that was used for this task. The reviewer will use its requirements as a definition of done and verify each one. |

**Important:** If a skill was involved in producing the work, always pass `--skill`. This gives the reviewer the full context of what the output should look like, what format to follow, and what quality standards apply. Without it, the review is generic.

The script handles file size limits automatically — files over 100KB are truncated with a warning to keep token costs reasonable.

## Workflow

When instructed to review your work (or when you should review before finishing):

1. **Identify** every file you created or modified during the task
2. **Run** `review-work <file_path> "<what you were asked to do>"` on each file
3. **Read** the review output — look for the verdict at the bottom (PASS / FAIL)
4. **Fix** any critical or major issues found
5. **Re-run** `review-work` after fixing to confirm (up to 3 cycles)
6. **Report** the review summary in your final output

## Examples

Basic review (no skill):

```bash
review-work /tmp/email.py "Write a Python email validator"
```

Review with skill context (reviewer checks against skill requirements):

```bash
review-work /tmp/blog.md "Write an SEO blog about class action lawsuits" --skill ~/.openclaw/workspace/skills/seo-content-writer/SKILL.md
```

Multiple files with skill:

```bash
review-work /tmp/scraper.py "Build a web scraper" --skill ~/.openclaw/workspace/skills/data-scraper/SKILL.md
review-work /tmp/results.csv "Build a web scraper" --skill ~/.openclaw/workspace/skills/data-scraper/SKILL.md
```

## Rules

1. Review **every** file you created or modified — not just the main one
2. If the review reports critical or major issues → fix them → re-review (up to 3 cycles)
3. Only finish after the verdict is **PASS** (zero critical/major issues)
4. Include the review summary in your final output
5. After 3 failed cycles, finish but attach the full review report

## What NOT to Do

- Do NOT ask the user for file paths — you already know what files you created
- Do NOT say "review passed" without actually running the command
- Do NOT fabricate review results — the command produces real output
- Do NOT skip binary files silently — the script auto-detects and skips them

## Learnings File

Failed reviews are auto-logged to `LESSONS.md` (default: `~/.openclaw/workspace/LESSONS.md`). Override the path with the `LESSONS_FILE` environment variable:

```bash
LESSONS_FILE=/path/to/LESSONS.md review-work /tmp/script.py "task"
```

Each entry records the file, task, verdict, and critical/major issues. Before starting work in an area with past failures, scan the file:

```bash
cat ~/.openclaw/workspace/LESSONS.md
```

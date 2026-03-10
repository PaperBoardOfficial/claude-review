# claude-review

Self-review quality gate for [OpenClaw](https://github.com/openclaw/openclaw) agents. Uses Claude CLI (`claude --print`) as an independent reviewer to catch errors, missed requirements, and quality issues before delivering work to the user.

## How It Works

When an agent finishes a task, it runs `review-work` on its output. The script sends the work to a **separate Claude instance** for independent review — the reviewer has no context of the original conversation, so it evaluates purely on merit.

```
Agent writes code → review-work sends to Claude CLI → gets issues back → fixes → re-reviews → delivers
```

The reviewer returns issues rated by severity (critical / major / minor) and a clear PASS/FAIL verdict.

## Installation

### Prerequisites

- [Claude CLI](https://github.com/anthropics/claude-code) installed and configured (`npm install -g @anthropic-ai/claude-code`)
- Valid Anthropic API key

### As an OpenClaw Skill

```bash
mkdir -p ~/.openclaw/workspace/skills/claude-review
cp skill/SKILL.md ~/.openclaw/workspace/skills/claude-review/
cp skill/review-work.sh /usr/local/bin/review-work
chmod +x /usr/local/bin/review-work
```

Enable in your `openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "claude-review": { "enabled": true }
    }
  }
}
```

### Standalone

```bash
cp skill/review-work.sh /usr/local/bin/review-work
chmod +x /usr/local/bin/review-work
```

## Usage

```bash
review-work "<task_summary>" --context <file_or_folder> [--skill <file_or_folder>]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `task_summary` | Yes | What the work was supposed to accomplish |
| `--context <path>` | Yes | File or folder to review (work output, reference material, test logs — anything relevant) |
| `--skill <path>` | No | SKILL.md or skill folder used for the task — reviewer checks against its requirements |

All paths accept files or folders. Claude reads all files itself using its built-in tools — including images, PDFs, and text files. Common junk directories (node_modules, .git, __pycache__, dist, build, etc.) are automatically skipped.

### Examples

```bash
# Basic review
review-work "Write a Python email validator" --context /tmp/email.py

# Review with skill — reviewer verifies against skill's specific requirements
review-work "Write an SEO blog" --context /tmp/blog.md --skill ~/skills/seo-content-writer/SKILL.md

# Review an entire project folder
review-work "Build a todo app" --context /tmp/todo-app/ --skill ~/skills/fullstack/

# Review without task description
review-work "general review" --context /tmp/output.csv
```

### Skill-Aware Review

When `--skill` is passed, the reviewer reads the skill's full requirements and generates a verification checklist. For example, with the seo-content-writer skill, the reviewer checks:
- Is the primary keyword in the title, H1, first 100 words?
- Is the meta description 150-160 chars?
- Are there 5+ FAQ questions with 40-80 word answers?
- Does it follow CORE-EEAT standards?

Without `--skill`, the review is generic (accuracy, completeness, quality).

### Sample Output

```
## Review: blog.md

### Verification Checklist (from seo-content-writer skill)
- [x] Primary keyword in title
- [x] Meta description 150-160 chars
- [ ] FAQ section with 5+ questions — only 3 found
- [x] Table of contents with anchor links

### Major Issues
1. **FAQ section incomplete** — Only 3 questions, skill requires minimum 5.

### Minor Issues
2. **Meta description is 148 chars** — Slightly under the 150 minimum.

VERDICT: FAIL — 0 critical, 1 major, 1 minor
```

## Features

- **File & folder support** — review a single file or an entire project directory
- **Images & PDFs** — Claude reads all file types natively (images, PDFs, text, code)
- **Skill-aware review** — pass `--skill` to review against a skill's specific requirements and definition of done
- **Auto-learnings** — failed reviews are automatically logged to `LESSONS.md`
- **Repeat mistake detection** — auto-includes `LESSONS.md` in every review so the reviewer checks for past mistakes

## LESSONS.md

Failed reviews are auto-logged to `LESSONS.md` (default: `~/.openclaw/workspace/LESSONS.md`). This file is also auto-read on every future review, so the reviewer checks for repeat mistakes — no extra flags needed.

Override the path with:
```bash
LESSONS_FILE=/path/to/LESSONS.md review-work "task" --context /tmp/output
```

Example auto-logged entry:
```markdown
### [2026-03-10] REVIEW-FAIL: email.py

TASK: Write a Python email validator
CONTEXT: /tmp/email.py
VERDICT: VERDICT: FAIL — 1 critical, 1 major, 1 minor
ISSUES:
1. **critical** — validate_email() accepts None without raising an error
2. **major** — Regex doesn't handle consecutive dots in local part

---
```

## Agent Integration

When used as an OpenClaw skill, the agent automatically:

1. Identifies every file it created or modified
2. Runs `review-work` with the task summary, `--context` pointing to output, and `--skill` if a skill was used
3. Fixes any critical or major issues
4. Re-reviews after fixing (up to 3 cycles)
5. Reports the review summary in its final output

The user just needs to say "review your work" or "use review-work" — the agent determines all arguments on its own.

## License

MIT

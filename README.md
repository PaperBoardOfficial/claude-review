# claude-review

Self-review quality gate for [OpenClaw](https://github.com/openclaw/openclaw) agents. Uses Claude CLI (`claude --print`) as an independent reviewer to catch errors, missed requirements, and quality issues before delivering work to the user.

## How It Works

When an agent finishes a task, it runs `review-work` on every file it created or modified. The script sends the file to a **separate Claude instance** for independent review — the reviewer has no context of the original conversation, so it evaluates purely on merit.

```
Agent writes code → review-work sends to Claude CLI → gets issues back → fixes → re-reviews → delivers
```

The reviewer returns issues rated by severity (critical / major / minor) and a clear PASS/FAIL verdict.

## Installation

### Prerequisites

- [Claude CLI](https://github.com/anthropics/claude-code) installed and configured (`npm install -g @anthropic-ai/claude-code`)
- Valid Anthropic API key

### As an OpenClaw Skill

Copy both files into your agent's skills directory:

```bash
mkdir -p ~/.openclaw/workspace/skills/claude-review
cp SKILL.md ~/.openclaw/workspace/skills/claude-review/
cp review-work.sh /usr/local/bin/review-work
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

Just install the script:

```bash
cp review-work.sh /usr/local/bin/review-work
chmod +x /usr/local/bin/review-work
```

## Usage

```bash
review-work <file_path> "<task_description>"
```

| Argument | Required | Description |
|----------|----------|-------------|
| `file_path` | Yes | Path to the file to review |
| `task_description` | No | What the file was supposed to accomplish |

### Examples

```bash
# Review a Python script
review-work /tmp/email.py "Write a Python email validator"

# Review a blog post
review-work /tmp/blog.md "Write a 1500-word SEO blog about class action lawsuits"

# Review without task description (still works, less context for reviewer)
review-work /tmp/output.csv
```

### Sample Output

```
## Review: email.py

### Critical Issues
1. **No input validation** — `validate_email()` accepts None without raising an error.

### Major Issues
2. **Regex doesn't handle edge cases** — consecutive dots in local part are accepted.

### Minor Issues
3. **Missing docstring** — function lacks a description of parameters and return value.

VERDICT: FAIL — 1 critical, 1 major, 1 minor
```

## Features

- **File size guard** — files over 100KB are truncated with a warning to control token costs
- **Binary file detection** — automatically skips binary files
- **Structured output** — issues categorized by severity with a clear PASS/FAIL verdict
- **Claude CLI check** — clear error message if `claude` is not installed

## Agent Integration

When used as an OpenClaw skill, the agent automatically:

1. Identifies every file it created or modified
2. Runs `review-work` on each file
3. Fixes any critical or major issues
4. Re-reviews after fixing (up to 3 cycles)
5. Reports the review summary in its final output

The user just needs to say "review your work" or "use review-work" — the agent determines file paths and task descriptions on its own.

## License

MIT

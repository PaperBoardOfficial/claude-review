#!/bin/bash
# review-work — independent self-review via Claude CLI
# Usage: review-work "<task_summary>" --context <file_or_folder> [--skill <file_or_folder>]
#
# Sends work to a separate Claude instance for quality review.
# Returns issues with severity (critical/major/minor) and a PASS/FAIL verdict.
# Auto-logs issues to LESSONS.md when the review fails.
# Auto-includes LESSONS.md (if it exists) so the reviewer checks for repeat mistakes.

set -e

MAX_TOTAL_SIZE=102400  # 100KB total — truncate beyond this to control token costs
LESSONS_FILE="${LESSONS_FILE:-$HOME/.openclaw/workspace/LESSONS.md}"

# --- Helpers ---

read_path() {
  # Reads a file or all text files in a folder, returns concatenated content with headers
  local target="$1"
  local label="$2"

  if [ -f "$target" ]; then
    if file --mime-encoding "$target" | grep -q "binary"; then
      echo "[Skipped binary file: $target]"
    else
      echo "=== $label: $target ==="
      cat "$target"
      echo ""
    fi
  elif [ -d "$target" ]; then
    local found=0
    while IFS= read -r -d '' f; do
      if file --mime-encoding "$f" | grep -q "binary"; then
        continue
      fi
      echo "=== $label: $f ==="
      cat "$f"
      echo ""
      found=$((found + 1))
    done < <(find "$target" -type f -not -name '.*' -print0 | sort -z)
    if [ "$found" -eq 0 ]; then
      echo "[No text files found in: $target]"
    fi
  else
    echo "[Not found: $target]"
  fi
}

truncate_content() {
  local content="$1"
  local max_size="$2"
  local size=${#content}
  if [ "$size" -gt "$max_size" ]; then
    echo "${content:0:$max_size}"
    echo ""
    echo "[WARNING: Content truncated from ${size} to ${max_size} bytes to control token costs.]"
  else
    echo "$content"
  fi
}

# --- Parse arguments ---

TASK=""
CONTEXT_PATH=""
SKILL_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CONTEXT_PATH="$2"
      shift 2
      ;;
    --skill)
      SKILL_PATH="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: review-work \"<task_summary>\" --context <file_or_folder> [--skill <file_or_folder>]"
      echo ""
      echo "Arguments:"
      echo "  task_summary          What the work was supposed to accomplish"
      echo "  --context <path>      File or folder to review (required)"
      echo "  --skill <path>        SKILL.md or skill folder used for the task (optional)"
      echo ""
      echo "Examples:"
      echo "  review-work \"Write a Python email validator\" --context /tmp/email.py"
      echo "  review-work \"Write an SEO blog\" --context /tmp/blog.md --skill ~/skills/seo-content-writer/SKILL.md"
      echo "  review-work \"Build a todo app\" --context /tmp/my-app/ --skill ~/skills/fullstack/SKILL.md"
      echo ""
      echo "Environment:"
      echo "  LESSONS_FILE    Path to lessons file (default: ~/.openclaw/workspace/LESSONS.md)"
      exit 0
      ;;
    *)
      if [ -z "$TASK" ]; then
        TASK="$1"
      else
        echo "Error: Unexpected argument: $1"
        echo "Usage: review-work \"<task_summary>\" --context <file_or_folder> [--skill <file_or_folder>]"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$TASK" ]; then
  echo "Error: Task summary is required."
  echo "Usage: review-work \"<task_summary>\" --context <file_or_folder> [--skill <file_or_folder>]"
  exit 1
fi

if [ -z "$CONTEXT_PATH" ]; then
  echo "Error: --context is required."
  echo "Usage: review-work \"<task_summary>\" --context <file_or_folder> [--skill <file_or_folder>]"
  exit 1
fi

if [ ! -e "$CONTEXT_PATH" ]; then
  echo "Error: Context path not found: $CONTEXT_PATH"
  exit 1
fi

# Resolve skill name to path if not a valid file/folder
# Accepts: "seo-content-writer", "seo-content-writer/SKILL.md", or full path
SKILLS_DIR="${SKILLS_DIR:-$HOME/.openclaw/workspace/skills}"
if [ -n "$SKILL_PATH" ] && [ ! -e "$SKILL_PATH" ]; then
  if [ -f "$SKILLS_DIR/$SKILL_PATH/SKILL.md" ]; then
    SKILL_PATH="$SKILLS_DIR/$SKILL_PATH"
  elif [ -f "$SKILLS_DIR/$SKILL_PATH" ]; then
    SKILL_PATH="$SKILLS_DIR/$SKILL_PATH"
  fi
fi

# Check if claude CLI is available
if ! command -v claude &> /dev/null; then
  echo "Error: claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# --- Build review prompt ---

# Read work to review
WORK_CONTENT=$(read_path "$CONTEXT_PATH" "WORK")

# Read skill requirements if provided
SKILL_SECTION=""
if [ -n "$SKILL_PATH" ]; then
  if [ -e "$SKILL_PATH" ]; then
    SKILL_CONTENT=$(read_path "$SKILL_PATH" "SKILL")
    SKILL_SECTION="
## Skill Requirements

The work was produced using the following skill. Use its requirements, output format, and quality standards as your definition of done. Check EVERY requirement — a missing requirement is a major issue.

<skill>
${SKILL_CONTENT}
</skill>

Generate a verification checklist from the skill above and check each item against the actual work.
"
  else
    echo "Warning: Skill path not found: $SKILL_PATH (continuing without skill context)"
  fi
fi

# Auto-include LESSONS.md if it exists
LESSONS_SECTION=""
if [ -f "$LESSONS_FILE" ]; then
  LESSONS_CONTENT=$(cat "$LESSONS_FILE")
  if [ -n "$LESSONS_CONTENT" ]; then
    LESSONS_SECTION="
## Past Mistakes (LESSONS.md)

The following issues were found in previous reviews. Check if any of the same mistakes are present in this work.

<lessons>
${LESSONS_CONTENT}
</lessons>
"
  fi
fi

# Assemble full prompt
FULL_CONTENT="${WORK_CONTENT}${SKILL_SECTION}${LESSONS_SECTION}"

# Apply size guard
FULL_CONTENT=$(truncate_content "$FULL_CONTENT" "$MAX_TOTAL_SIZE")

# Run the review and capture output
REVIEW_OUTPUT=$(claude --print --permission-mode bypassPermissions "You are a code and content reviewer. Review the following work for:

1. **Accuracy** — Are there factual errors, bugs, or incorrect logic?
2. **Completeness** — Does it fulfill all requirements of the original task?
3. **Quality** — Is it well-structured, readable, and following best practices?
4. **Errors** — Are there syntax errors, typos, broken links, or formatting issues?
5. **Missed requirements** — Is anything from the task description missing or incomplete?
${SKILL_SECTION:+6. **Skill compliance** — Does it meet every requirement from the skill definition?}
${LESSONS_SECTION:+7. **Repeat mistakes** — Are any past mistakes from LESSONS.md present in this work?}

List every issue found with severity:
- **critical** — Blocks correctness or usability. Must fix.
- **major** — Significant quality or completeness gap. Should fix.
- **minor** — Style, polish, or optional improvement. Nice to fix.

Original task: ${TASK}

${FULL_CONTENT}

---

End your review with a verdict line in exactly this format:
VERDICT: PASS (if zero critical and zero major issues)
VERDICT: FAIL — X critical, Y major, Z minor (if any critical or major issues exist)")

# Print the review output
echo "$REVIEW_OUTPUT"

# Auto-log to LESSONS.md if the review failed
if echo "$REVIEW_OUTPUT" | grep -q "VERDICT: FAIL"; then
  VERDICT_LINE=$(echo "$REVIEW_OUTPUT" | grep "VERDICT: FAIL" | tail -1)
  DATE=$(date +%Y-%m-%d)

  # Extract critical and major issues (skip minor)
  ISSUES=$(echo "$REVIEW_OUTPUT" | grep -E "^\*?\*?(critical|major)\*?\*?" | head -10)
  if [ -z "$ISSUES" ]; then
    ISSUES=$(echo "$REVIEW_OUTPUT" | grep -i "critical\|major" | grep -v "VERDICT" | head -10)
  fi

  # Create directory if needed
  LESSONS_DIR=$(dirname "$LESSONS_FILE")
  mkdir -p "$LESSONS_DIR"

  # Append learning entry
  cat >> "$LESSONS_FILE" << EOF

### [$DATE] REVIEW-FAIL: $(basename "$CONTEXT_PATH")

TASK: $TASK
CONTEXT: $CONTEXT_PATH
VERDICT: $VERDICT_LINE
ISSUES:
$ISSUES

---
EOF
fi

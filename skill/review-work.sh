#!/bin/bash
# review-work — independent self-review via Claude CLI
# Usage: review-work <file_path> "<task_description>"
#
# Sends a file to a separate Claude instance for quality review.
# Returns issues with severity (critical/major/minor) and a PASS/FAIL verdict.
# Auto-logs issues to .learnings.md when the review fails.

set -e

MAX_FILE_SIZE=102400  # 100KB — truncate beyond this to control token costs
LEARNINGS_FILE="${LEARNINGS_FILE:-$HOME/.openclaw/workspace/.learnings.md}"

FILE="$1"
TASK="${2:-No task description provided}"

if [ -z "$FILE" ]; then
  echo "Usage: review-work <file_path> \"<task_description>\""
  echo "Example: review-work /tmp/prime.py \"Write a prime checker function\""
  exit 1
fi

if [ ! -f "$FILE" ]; then
  echo "Error: File not found: $FILE"
  exit 1
fi

# Check if claude CLI is available
if ! command -v claude &> /dev/null; then
  echo "Error: claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# Skip binary files
if file --mime-encoding "$FILE" | grep -q "binary"; then
  echo "Skipping binary file: $FILE"
  echo "review-work only reviews text-based files."
  exit 0
fi

# Read file with size guard
FILE_SIZE=$(wc -c < "$FILE")
if [ "$FILE_SIZE" -gt "$MAX_FILE_SIZE" ]; then
  CONTENT=$(head -c "$MAX_FILE_SIZE" "$FILE")
  TRUNCATED_NOTE="[WARNING: File truncated from ${FILE_SIZE} bytes to ${MAX_FILE_SIZE} bytes for review. Some content at the end was not reviewed.]"
else
  CONTENT=$(cat "$FILE")
  TRUNCATED_NOTE=""
fi

# Run the review and capture output
REVIEW_OUTPUT=$(claude --print --permission-mode bypassPermissions "You are a code and content reviewer. Review the following work for:

1. **Accuracy** — Are there factual errors, bugs, or incorrect logic?
2. **Completeness** — Does it fulfill all requirements of the original task?
3. **Quality** — Is it well-structured, readable, and following best practices?
4. **Errors** — Are there syntax errors, typos, broken links, or formatting issues?
5. **Missed requirements** — Is anything from the task description missing or incomplete?

List every issue found with severity:
- **critical** — Blocks correctness or usability. Must fix.
- **major** — Significant quality or completeness gap. Should fix.
- **minor** — Style, polish, or optional improvement. Nice to fix.

${TRUNCATED_NOTE}

Original task: ${TASK}

File: ${FILE}
Content:
${CONTENT}

---

End your review with a verdict line in exactly this format:
VERDICT: PASS (if zero critical and zero major issues)
VERDICT: FAIL — X critical, Y major, Z minor (if any critical or major issues exist)")

# Print the review output
echo "$REVIEW_OUTPUT"

# Auto-log to .learnings.md if the review failed
if echo "$REVIEW_OUTPUT" | grep -q "VERDICT: FAIL"; then
  VERDICT_LINE=$(echo "$REVIEW_OUTPUT" | grep "VERDICT: FAIL" | tail -1)
  DATE=$(date +%Y-%m-%d)

  # Extract critical and major issues (skip minor)
  ISSUES=$(echo "$REVIEW_OUTPUT" | grep -E "^\*?\*?(critical|major)\*?\*?" | head -10)
  if [ -z "$ISSUES" ]; then
    # Fallback: grab lines containing "critical" or "major" (case-insensitive)
    ISSUES=$(echo "$REVIEW_OUTPUT" | grep -i "critical\|major" | grep -v "VERDICT" | head -10)
  fi

  # Create learnings directory if needed
  LEARNINGS_DIR=$(dirname "$LEARNINGS_FILE")
  mkdir -p "$LEARNINGS_DIR"

  # Append learning entry
  cat >> "$LEARNINGS_FILE" << EOF

### [$DATE] REVIEW-FAIL: $(basename "$FILE")

TASK: $TASK
FILE: $FILE
VERDICT: $VERDICT_LINE
ISSUES:
$ISSUES

---
EOF
fi

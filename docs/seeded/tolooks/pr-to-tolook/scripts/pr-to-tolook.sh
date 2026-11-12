#!/bin/bash
set -euo pipefail

# pr-to-tolook.sh
# Fetches metadata from a GitHub pull request, formats a draft ToLook entry,
# and optionally comments and closes the PR.
#
# Target: macOS Bash 3.2 (POSIX awk, sed, jq; no declare -A, mapfile, coproc)
# Works when invoked from any directory.

print_usage() {
  echo "Usage: $(basename "$0") <PR-number-or-URL> [options]"
  echo ""
  echo "Arguments:"
  echo "  <PR-number-or-URL>   GitHub PR number (e.g. 119) or URL"
  echo ""
  echo "Options:"
  echo "  -r, --repo <owner/repo> Target repository (defaults to current git repo)"
  echo "  -a, --append            Append the generated ToLook to TOLOOKS.md in the repo root"
  echo "  -c, --close             Comment on and close the PR on GitHub"
  echo "  -h, --help              Show this help message"
}

PR_INPUT=""
REPO_ARG=""
APPEND_TO_TOLOOKS=0
CLOSE_PR=0

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--repo)
      REPO_ARG="$2"
      shift 2
      ;;
    -a|--append)
      APPEND_TO_TOLOOKS=1
      shift
      ;;
    -c|--close)
      CLOSE_PR=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      if [ -z "$PR_INPUT" ]; then
        PR_INPUT="$1"
        shift
      else
        echo "Error: Unknown argument '$1'" >&2
        print_usage >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$PR_INPUT" ]; then
  echo "Error: Missing PR number or URL." >&2
  print_usage >&2
  exit 1
fi

# Extract PR number if full URL was provided
PR_NUMBER=""
if echo "$PR_INPUT" | grep -q "pull/"; then
  PR_NUMBER="$(echo "$PR_INPUT" | sed -E 's|.*/pull/([0-9]+).*|\1|')"
  # If repo wasn't specified, extract from URL
  if [ -z "$REPO_ARG" ]; then
    REPO_ARG="$(echo "$PR_INPUT" | sed -E 's|https?://github.com/([^/]+/[^/]+)/pull/.*|\1|')"
  fi
else
  PR_NUMBER="$PR_INPUT"
fi

GH_REPO_FLAGS=()
if [ -n "$REPO_ARG" ]; then
  GH_REPO_FLAGS=("-R" "$REPO_ARG")
fi

# Verify gh CLI is available
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: 'gh' CLI is required but not installed." >&2
  exit 1
fi

echo "Fetching PR #$PR_NUMBER details..." >&2
PR_DATA="$(gh pr view "$PR_NUMBER" "${GH_REPO_FLAGS[@]}" --json number,title,body,author,createdAt,url,headRefName,baseRefName,files,additions,deletions,changedFiles 2>/dev/null || true)"

if [ -z "$PR_DATA" ]; then
  echo "Error: Failed to fetch PR #$PR_NUMBER using gh CLI." >&2
  exit 1
fi

PR_TITLE="$(echo "$PR_DATA" | jq -r '.title // "Untitled"')"
PR_AUTHOR="$(echo "$PR_DATA" | jq -r '.author.login // "unknown"')"
PR_BRANCH="$(echo "$PR_DATA" | jq -r '.headRefName // "unknown"')"
PR_URL="$(echo "$PR_DATA" | jq -r '.url // ""')"
PR_BODY="$(echo "$PR_DATA" | jq -r '.body // ""' | sed '/^[[:space:]]*$/d' | head -n 6)"

ADDITIONS="$(echo "$PR_DATA" | jq -r '.additions // 0')"
DELETIONS="$(echo "$PR_DATA" | jq -r '.deletions // 0')"
CHANGED_FILES_COUNT="$(echo "$PR_DATA" | jq -r '.changedFiles // 0')"
DIFF_SUMMARY="+$ADDITIONS / -$DELETIONS across $CHANGED_FILES_COUNT file(s)"

FILES_CHANGED="$(echo "$PR_DATA" | jq -r '.files[].path' 2>/dev/null | head -n 8 || true)"

# Format files list for investigation block
FORMATTED_FILES=""
if [ -n "$FILES_CHANGED" ]; then
  while IFS= read -r file_path; do
    if [ -n "$file_path" ]; then
      if [ -z "$FORMATTED_FILES" ]; then
        FORMATTED_FILES="[\`$file_path\`](file://$file_path)"
      else
        FORMATTED_FILES="$FORMATTED_FILES, [\`$file_path\`](file://$file_path)"
      fi
    fi
  done <<EOF
$FILES_CHANGED
EOF
fi

# Determine next item number if TOLOOKS.md exists
NEXT_NUM="1"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TOLOOKS_FILE="$REPO_ROOT/TOLOOKS.md"

if [ -f "$TOLOOKS_FILE" ]; then
  MAX_NUM="$(grep -E '^\- \[[ x]\] \*\*[0-9]+\.' "$TOLOOKS_FILE" | sed -E 's/^\- \[[ x]\] \*\*([0-9]+)\..*/\1/' | sort -n | tail -n 1 || echo "0")"
  if [ -n "$MAX_NUM" ] && [ "$MAX_NUM" -gt 0 ] 2>/dev/null; then
    NEXT_NUM="$((MAX_NUM + 1))"
  fi
fi

# Build Draft ToLook Markdown block
DRAFT_TOLOOK="$(cat <<EOF
- [ ] **$NEXT_NUM. $PR_TITLE**
  - **Idea**: Explore and implement $PR_TITLE.
  - **Context**: Originated from PR [#$PR_NUMBER]($PR_URL) on branch \`$PR_BRANCH\` by @$PR_AUTHOR ($DIFF_SUMMARY). Shelved to allow a clean revisit with fresh eyes and current architecture.
  - **Investigation**:
    - *Prior Art / PR Spike*: PR [#$PR_NUMBER]($PR_URL) provided initial prototype. Key files: ${FORMATTED_FILES:-none recorded}.
    - *Initial Description*:
$(echo "$PR_BODY" | sed 's/^/      > /')
    - *Candidate Options*:
      - **Option A (Fresh Redesign)**: Re-evaluate the requirement against modern conventions and build from scratch.
      - **Option B (Salvage Spike)**: Rebase \`$PR_BRANCH\` or cherry-pick core logic into a new branch.
    - [ ] Review prototype changes in PR [#$PR_NUMBER]($PR_URL)
    - [ ] Determine current necessity and API fit
EOF
)"

echo "$DRAFT_TOLOOK"

if [ "$APPEND_TO_TOLOOKS" -eq 1 ]; then
  if [ ! -f "$TOLOOKS_FILE" ]; then
    echo "Warning: $TOLOOKS_FILE not found. Creating from template..." >&2
    SEED_TEMPLATE="$REPO_ROOT/docs/seeded/tolooks/template.md"
    if [ -f "$SEED_TEMPLATE" ]; then
      cp "$SEED_TEMPLATE" "$TOLOOKS_FILE"
    else
      echo "# ToLooks" > "$TOLOOKS_FILE"
      echo "" >> "$TOLOOKS_FILE"
      echo "## Active ToLooks" >> "$TOLOOKS_FILE"
      echo "" >> "$TOLOOKS_FILE"
    fi
  fi

  # Append to Active ToLooks section if possible, otherwise append to end
  if grep -q "## Active ToLooks" "$TOLOOKS_FILE"; then
    awk -v block="$DRAFT_TOLOOK" '
      /## Active ToLooks/ {
        print
        print ""
        print block
        next
      }
      { print }
    ' "$TOLOOKS_FILE" > "${TOLOOKS_FILE}.tmp" && mv "${TOLOOKS_FILE}.tmp" "$TOLOOKS_FILE"
    echo "Appended ToLook #$NEXT_NUM to $TOLOOKS_FILE" >&2
  else
    printf "\n%s\n" "$DRAFT_TOLOOK" >> "$TOLOOKS_FILE"
    echo "Appended ToLook #$NEXT_NUM to $TOLOOKS_FILE (at end)" >&2
  fi
fi

if [ "$CLOSE_PR" -eq 1 ]; then
  echo "Closing PR #$PR_NUMBER on GitHub..." >&2
  gh pr comment "$PR_NUMBER" "${GH_REPO_FLAGS[@]}" --body "Converted into ToLook #$NEXT_NUM in \`TOLOOKS.md\` to preserve context and allow a fresh approach. Closing PR."
  gh pr close "$PR_NUMBER" "${GH_REPO_FLAGS[@]}"
  echo "PR #$PR_NUMBER closed successfully." >&2
fi

#!/bin/bash
# ==============================================================================
# monitor-seed-propagation.sh: Monitor seed workflow and downstream PR status.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TBX_PRS_SCRIPT="$HOME/tbx-for-toolbox.dev/tbx-gh-prs.sh"
TBX_ACTIONS_SCRIPT="$HOME/tbx-for-toolbox.dev/tbx-gh-actions.sh"

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Monitors seed propagation actions and downstream PR status across the ecosystem.

Options:
  -w, --watch       Watch the latest on-seed-updated workflow run in real-time
  -v, --verbose     Show detailed CI check statuses for open seed PRs
  --tbx             Run full tbx-gh-status audit from tbx-for-toolbox.dev
  -h, --help        Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --verbose
  $(basename "$0") --watch
EOF
	exit 0
}

WATCH_MODE=0
VERBOSE_MODE=0
RUN_TBX=0

while [ $# -gt 0 ]; do
	case "$1" in
		-w|--watch)
			WATCH_MODE=1
			shift
			;;
		-v|--verbose)
			VERBOSE_MODE=1
			shift
			;;
		--tbx)
			RUN_TBX=1
			shift
			;;
		-h|--help)
			usage
			;;
		*)
			echo "Error: Unknown argument '$1'" >&2
			usage
			;;
	esac
done

echo "================================================================================"
echo "🌱 REPOSITORY-SEED PROPAGATION & PR MONITOR ($(date '+%Y-%m-%d %H:%M:%S'))"
echo "================================================================================"
echo ""

# 1. Check latest upstream workflow run in repository-seed
echo "▶ 1. Latest 'on-seed-updated.yml' Workflow Run:"
echo "--------------------------------------------------------------------------------"
LATEST_RUN_JSON=$(gh run list --repo TarasMazepa/repository-seed --workflow on-seed-updated.yml --limit 1 --json databaseId,status,conclusion,headSha,url,updatedAt,displayTitle 2>/dev/null || true)

if [ -z "$LATEST_RUN_JSON" ] || [ "$LATEST_RUN_JSON" = "[]" ]; then
	echo "  No workflow runs found for on-seed-updated.yml."
else
	RUN_ID=$(echo "$LATEST_RUN_JSON" | jq -r '.[0].databaseId // empty')
	RUN_STATUS=$(echo "$LATEST_RUN_JSON" | jq -r '.[0].status // empty')
	RUN_CONCLUSION=$(echo "$LATEST_RUN_JSON" | jq -r '.[0].conclusion // empty')
	RUN_SHA=$(echo "$LATEST_RUN_JSON" | jq -r '.[0].headSha // empty')
	RUN_TITLE=$(echo "$LATEST_RUN_JSON" | jq -r '.[0].displayTitle // empty')
	RUN_URL=$(echo "$LATEST_RUN_JSON" | jq -r '.[0].url // empty')

	echo "  Commit:   $RUN_SHA"
	echo "  Title:    $RUN_TITLE"
	echo "  Status:   $RUN_STATUS ($RUN_CONCLUSION)"
	echo "  Run ID:   $RUN_ID"
	echo "  URL:      $RUN_URL"

	if [ "$WATCH_MODE" -eq 1 ] && [ "$RUN_STATUS" != "completed" ]; then
		echo ""
		echo "  Watching active workflow run $RUN_ID..."
		gh run watch "$RUN_ID" --repo TarasMazepa/repository-seed || true
	fi
fi
echo ""

# 2. Check open seed PRs across the ecosystem
echo "▶ 2. Open Downstream Seed Pull Requests:"
echo "--------------------------------------------------------------------------------"
OPEN_PRS_JSON=$(gh search prs --owner TarasMazepa --state open "Changes from repository seed" --json repository,number,title,url,updatedAt 2>/dev/null || true)

OPEN_COUNT=$(echo "$OPEN_PRS_JSON" | jq 'length' 2>/dev/null || echo 0)

if [ "$OPEN_COUNT" -eq 0 ]; then
	echo "  ✅ All downstream seed pull requests have merged cleanly! (0 open PRs)"
else
	echo "  ⚠️ Found $OPEN_COUNT open seed pull request(s) awaiting merge or blocked by CI:"
	echo ""
	echo "$OPEN_PRS_JSON" | jq -r '.[] | "  • " + .repository.nameWithOwner + " #" + (.number|tostring) + " -> " + .url'

	echo ""
	echo "  Checking CI status for open seed PRs..."
	echo "$OPEN_PRS_JSON" | jq -r '.[] | .url' | while read -r PR_URL; do
		if [ -n "$PR_URL" ]; then
			echo "  ----------------------------------------------------------------------------"
			echo "  Inspecting: $PR_URL"
			gh pr checks "$PR_URL" 2>&1 | sed 's/^/    /' || true
		fi
	done
fi
echo ""

# 3. Check recently merged seed PRs
echo "▶ 3. Recently Merged Seed Pull Requests:"
echo "--------------------------------------------------------------------------------"
MERGED_PRS_JSON=$(gh search prs --owner TarasMazepa --merged "Changes from repository seed" --limit 5 --json repository,number,url,updatedAt 2>/dev/null || true)

MERGED_COUNT=$(echo "$MERGED_PRS_JSON" | jq 'length' 2>/dev/null || echo 0)
if [ "$MERGED_COUNT" -gt 0 ]; then
	echo "$MERGED_PRS_JSON" | jq -r '.[] | "  ✓ " + .repository.nameWithOwner + " #" + (.number|tostring) + " (" + .updatedAt + ")"'
else
	echo "  No recently merged seed PRs found."
fi
echo ""

# 4. Optional tbx tools integration
if [ "$RUN_TBX" -eq 1 ]; then
	echo "▶ 4. Estate-Wide Health Audit via tbx-for-toolbox.dev:"
	echo "--------------------------------------------------------------------------------"
	if [ -x "$TBX_PRS_SCRIPT" ]; then
		echo "Running $TBX_PRS_SCRIPT..."
		"$TBX_PRS_SCRIPT"
	else
		echo "Note: $TBX_PRS_SCRIPT not found or not executable."
	fi
fi

echo "================================================================================"
echo "Done."

#!/bin/bash
# ==============================================================================
# check-unseeded-repositories.sh: Audit repos not managed by repository-seed.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/on-seed-updated.yml"
EXCLUDES_FILE="$SCRIPT_DIR/seed-excludes.txt"

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Audits all GitHub repositories for TarasMazepa against the active matrix in
repository-seed (.github/workflows/on-seed-updated.yml) and seed-excludes.txt.

Options:
  -v, --verbose     Show detailed repository metadata and classification reasons
  -h, --help        Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --verbose
EOF
	exit 0
}

VERBOSE_MODE=0

while [ $# -gt 0 ]; do
	case "$1" in
		-v|--verbose)
			VERBOSE_MODE=1
			shift
			;;
		-h|--help)
			usage
			;;
		*)
			echo "Unknown option: $1" >&2
			usage
			;;
	esac
done

if ! command -v gh >/dev/null 2>&1; then
	echo "Error: GitHub CLI ('gh') is required but not installed or not in PATH." >&2
	exit 1
fi

if [ ! -f "$WORKFLOW_FILE" ]; then
	echo "Error: Workflow file not found at $WORKFLOW_FILE" >&2
	exit 1
fi

# Temp files for set comparisons
SEEDED_TMP="$(mktemp -t seeded_repos.XXXXXX)"
ALL_ACTIVE_TMP="$(mktemp -t all_active.XXXXXX)"
ARCHIVED_TMP="$(mktemp -t archived.XXXXXX)"
STRUCTURAL_TMP="$(mktemp -t structural.XXXXXX)"
DORMANT_TMP="$(mktemp -t dormant.XXXXXX)"
ALL_EXCLUDED_TMP="$(mktemp -t all_excluded.XXXXXX)"
UNACCOUNTED_TMP="$(mktemp -t unaccounted.XXXXXX)"

trap 'rm -f "$SEEDED_TMP" "$ALL_ACTIVE_TMP" "$ARCHIVED_TMP" "$STRUCTURAL_TMP" "$DORMANT_TMP" "$ALL_EXCLUDED_TMP" "$UNACCOUNTED_TMP"' EXIT

# 1. Seeded repositories from workflow matrix
grep -E "^[[:space:]]+-[[:space:]]+TarasMazepa/" "$WORKFLOW_FILE" | \
	sed -E "s/^[[:space:]]+-[[:space:]]+TarasMazepa\///" | \
	sort > "$SEEDED_TMP"
SEEDED_COUNT=$(wc -l < "$SEEDED_TMP" | tr -d " ")

# 2. Excluded repositories from seed-excludes.txt
if [ -f "$EXCLUDES_FILE" ]; then
	grep -E '^[a-zA-Z0-9._-]+[[:space:]]+(structural|upstream-fork)' "$EXCLUDES_FILE" | awk '{print $1}' | sort > "$STRUCTURAL_TMP"
	grep -E '^[a-zA-Z0-9._-]+[[:space:]]+dormant-data' "$EXCLUDES_FILE" | awk '{print $1}' | sort > "$DORMANT_TMP"
	cat "$STRUCTURAL_TMP" "$DORMANT_TMP" | sort -u > "$ALL_EXCLUDED_TMP"
else
	touch "$STRUCTURAL_TMP" "$DORMANT_TMP" "$ALL_EXCLUDED_TMP"
fi
STRUCTURAL_COUNT=$(wc -l < "$STRUCTURAL_TMP" | tr -d " ")
DORMANT_COUNT=$(wc -l < "$DORMANT_TMP" | tr -d " ")

# 3. Query all GitHub repositories
gh_repos_json=$(gh repo list TarasMazepa --limit 150 --json name,isArchived,isFork,visibility,description)

# Separate active vs archived
echo "$gh_repos_json" | jq -r '.[] | select(.isArchived == false) | .name' | sort > "$ALL_ACTIVE_TMP"
echo "$gh_repos_json" | jq -r '.[] | select(.isArchived == true) | .name' | sort > "$ARCHIVED_TMP"

TOTAL_ACTIVE=$(wc -l < "$ALL_ACTIVE_TMP" | tr -d " ")
TOTAL_ARCHIVED=$(wc -l < "$ARCHIVED_TMP" | tr -d " ")
TOTAL_REPOS=$((TOTAL_ACTIVE + TOTAL_ARCHIVED))

# 4. Compute unaccounted active repos: Active - (Seeded + Excluded)
ACCOUNTED_TMP="$(mktemp -t accounted.XXXXXX)"
cat "$SEEDED_TMP" "$ALL_EXCLUDED_TMP" | sort -u > "$ACCOUNTED_TMP"
comm -23 "$ALL_ACTIVE_TMP" "$ACCOUNTED_TMP" > "$UNACCOUNTED_TMP"
UNACCOUNTED_COUNT=$(wc -l < "$UNACCOUNTED_TMP" | tr -d " ")
rm -f "$ACCOUNTED_TMP"

echo "=============================================================================="
echo "🌱 REPOSITORY SEED COVERAGE AUDIT"
echo "=============================================================================="
echo "Total Repositories on GitHub: $TOTAL_REPOS ($TOTAL_ACTIVE active, $TOTAL_ARCHIVED archived)"
echo "  ✓ Managed by Seed Matrix:    $SEEDED_COUNT"
echo "  ⊘ Excluded (Structural/Fork): $STRUCTURAL_COUNT"
echo "  ⊘ Excluded (Dormant/Data):   $DORMANT_COUNT"
echo "  📦 Archived on GitHub:       $TOTAL_ARCHIVED"
echo "------------------------------------------------------------------------------"
if [ "$UNACCOUNTED_COUNT" -eq 0 ]; then
	echo "Status: 100% ACCOUNTED FOR (Zero governance drift)"
else
	echo "Status: ⚠️  $UNACCOUNTED_COUNT UNACCOUNTED ACTIVE REPOSITORY/REPOSITORIES DETECTED"
fi
echo "=============================================================================="

if [ "$VERBOSE_MODE" -eq 1 ]; then
	echo ""
	echo "1. Seeded Active Repositories ($SEEDED_COUNT):"
	while IFS= read -r r; do [ -n "$r" ] && echo "   ✓ $r"; done < "$SEEDED_TMP"

	echo ""
	echo "2. Excluded Structural & Upstream Forks ($STRUCTURAL_COUNT):"
	while IFS= read -r r; do [ -n "$r" ] && echo "   ⊘ $r"; done < "$STRUCTURAL_TMP"

	echo ""
	echo "3. Excluded Dormant / Data ('Never Ever') ($DORMANT_COUNT):"
	while IFS= read -r r; do [ -n "$r" ] && echo "   ⊘ $r"; done < "$DORMANT_TMP"

	echo ""
	echo "4. Archived on GitHub ($TOTAL_ARCHIVED):"
	while IFS= read -r r; do [ -n "$r" ] && echo "   📦 $r"; done < "$ARCHIVED_TMP"
fi

if [ "$UNACCOUNTED_COUNT" -gt 0 ]; then
	echo ""
	echo "⚠️  Action Required: Unaccounted Active Repositories ($UNACCOUNTED_COUNT):"
	while IFS= read -r r; do
		[ -z "$r" ] && continue
		desc=$(echo "$gh_repos_json" | jq -r --arg n "$r" '.[] | select(.name == $n) | .description // ""')
		printf "  • %-26s %s\n" "$r" "$desc"
	done < "$UNACCOUNTED_TMP"
	echo "------------------------------------------------------------------------------"
	echo "Resolution: Add to .github/workflows/on-seed-updated.yml OR seed-excludes.txt"
	exit 1
fi

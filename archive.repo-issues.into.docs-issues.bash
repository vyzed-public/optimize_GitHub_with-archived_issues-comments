#!/usr/bin/env bash
#
# archive.repo-issues.into.docs-issues.bash
#
# One-time backfill script: pulls all GitHub Issues (open and closed) for a
# given repo and writes them as markdown files into archive/issues/ using the
# same sanitized-title filename format as the sync-issues.yml GitHub Action.
#
# Usage:
#   ./archive.repo-issues.into.docs-issues.bash OWNER/REPO
#
# Example:
#   ./archive.repo-issues.into.docs-issues.bash vyzed-public/explore_DNS-config-devops
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - python3 available on PATH
#
# Output:
#   archive/issues/issue-NNNN.Sanitized_Title.md  (one file per issue)
#

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 OWNER/REPO"
    echo "Example: $0 vyzed-public/explore_DNS-config-devops"
    exit 1
fi

REPO="$1"

echo "=== Fetching all issues from ${REPO} ==="

mkdir -p archive/issues

ISSUE_NUMBERS=$(gh issue list --repo "$REPO" --state all --json number --jq '.[].number' --limit 5000)

if [[ -z "$ISSUE_NUMBERS" ]]; then
    echo "No issues found for ${REPO}."
    exit 0
fi

TOTAL=$(echo "$ISSUE_NUMBERS" | wc -l)
COUNT=0

for i in $ISSUE_NUMBERS; do
    COUNT=$((COUNT + 1))
    echo "[${COUNT}/${TOTAL}] Processing issue #${i}..."

    gh issue view "$i" --repo "$REPO" \
        --json number,title,body,state,labels,createdAt,closedAt,author,comments \
        | python3 -c "
import json, sys, os, glob, re

issue = json.load(sys.stdin)
n = issue['number']

# --- Sanitize title for filename ---
title = issue.get('title', '')
# Strip to ASCII only
title = title.encode('ascii', 'ignore').decode('ascii')
# Replace spaces with underscores
title = title.replace(' ', '_')
# Remove anything that isn't alphanumeric, underscore, hyphen, or dot
title = re.sub(r'[^A-Za-z0-9_\-.]', '', title)
# Collapse multiple underscores
title = re.sub(r'_+', '_', title)
# Strip leading/trailing underscores
title = title.strip('_')
# Truncate to 100 chars, adding ellipsis if needed
if len(title) > 100:
    title = title[:100].rsplit('_', 1)[0] + '...'

# --- Delete any existing file for this issue number (handles renames) ---
for old_file in glob.glob(f'archive/issues/issue-{n:04d}.*'):
    os.remove(old_file)

# --- Build markdown content ---
md = []
md.append(f'# #{n}: {issue[\"title\"]}')
md.append('')
md.append(f'**State:** {issue[\"state\"]}')
md.append(f'**Author:** {issue[\"author\"][\"login\"]}')
md.append(f'**Created:** {issue[\"createdAt\"]}')
if issue.get('closedAt'):
    md.append(f'**Closed:** {issue[\"closedAt\"]}')
if issue.get('labels'):
    labels = ', '.join(l['name'] for l in issue['labels'])
    md.append(f'**Labels:** {labels}')
md.append('')
md.append('---')
md.append('')
md.append(issue.get('body') or '*No description provided.*')

if issue.get('comments'):
    md.append('')
    md.append('---')
    md.append('')
    md.append('## Comments')
    for c in issue['comments']:
        md.append('')
        md.append(f'### {c[\"author\"][\"login\"]} — {c[\"createdAt\"]}')
        md.append('')
        md.append(c['body'])

# --- Write file ---
if title:
    filename = f'archive/issues/issue-{n:04d}.{title}.md'
else:
    filename = f'archive/issues/issue-{n:04d}.md'
with open(filename, 'w') as f:
    f.write('\n'.join(md) + '\n')

print(f'  -> {filename}')
"
done

echo ""
echo "=== Done. ${TOTAL} issues written to archive/issues/ ==="
echo ""
echo "Next steps:"
echo "  git add archive/issues/"
echo "  git commit -m 'archive: backfill all issues into archive/issues/'"
echo "  git push"

# Discussion Summary: In-Repo Issue Tracking via `archive/issues/`

## Problem Statement

Many GitHub projects use Issues to track not just code tasks but procedural items — configuration steps, operational checklists, and historical records of CLI output. These issues and their comment threads serve as valuable documentation, but they live outside the Git repository in GitHub's database. A `git clone` captures none of them.

The goal: make issue tracking **part of the repo itself**, so issues clone with the code and are portable across tools like Obsidian and TiddlyWiki.

## Key Insight

GitHub Issues aren't stored in Git — they exist in GitHub's platform layer. `git clone` has no mechanism to pull them. However, since issues are fundamentally markdown content, they can be serialized into markdown files and committed to the repo.

## Approaches for Retrieving Issues Locally

### GitHub CLI (`gh`)

The most accessible method for pulling issues locally:

```bash
# List all issues
gh issue list --repo OWNER/REPO --state all --limit 500

# View a single issue with comments
gh issue view 42 --repo OWNER/REPO --comments

# Export all issues as structured JSON
gh issue list --repo OWNER/REPO --state all \
  --json number,title,body,comments,labels,state,createdAt,closedAt \
  --limit 500 > issues.json
```

### GitHub REST API

For more granular control, with pagination at 100 results per page:

```bash
curl -H "Authorization: token YOUR_PAT" \
  "https://api.github.com/repos/OWNER/REPO/issues?state=all&per_page=100" \
  > issues.json
```

## Chosen Solution: GitHub Action for Automated Sync

A GitHub Action triggers on issue and comment events, renders each issue to a markdown file, and commits it back to the repo.

### Trigger Events

The workflow fires on:

- `issues`: opened, edited, closed, reopened, labeled, unlabeled, deleted
- `issue_comment`: created, edited, deleted

### Version History

An initial "basic" version of the workflow was prototyped first, using a simple `issue-NNNN.md` naming scheme with no title in the filename. That version was committed to the repo and can be retrieved via standard git operations:

```bash
# View commit history for the workflow file
git log --oneline .github/workflows/sync-issues.yml

# Restore the original basic version if needed
git checkout <commit-hash> -- .github/workflows/sync-issues.yml
git commit -m "revert sync-issues.yml to basic version"
```

The current version (below) implements the updated filename spec with sanitized issue titles.

### Output Format

Each issue is written to `archive/issues/issue-NNNN.Sanitized_Issue_Title.md` with the following structure:

- Filename includes the issue number prefix and a sanitized version of the issue title (e.g., `issue-0016.Troubleshoot_DNS_on_spoke_within_VPN.md`)
- Title as H1 heading (e.g., `# #16: Troubleshoot: DNS on spoke within VPN`)
- Metadata block: state, author, created/closed timestamps, labels
- Issue body (original markdown preserved)
- Comments section: each comment as an H3 with author and timestamp, followed by the comment body

### Filename Sanitization Rules

- **ASCII only:** All non-ASCII characters (emoji, accented characters, etc.) are stripped
- **Spaces** replaced with underscores
- **Special characters** (`/ : \ " ' ?` and others unsafe for file paths) are removed
- **Multiple consecutive underscores** collapsed to a single underscore
- **Title portion** capped at 100 characters; if truncated, three periods (`...`) are appended at a word boundary (103 characters effective max for the title portion)
- **On rename:** If an issue title is edited, the old file is deleted via glob match on `issue-NNNN.*` before the new file is written, preventing stale duplicates
- **Fallback:** If the title sanitizes to an empty string, the file falls back to `issue-NNNN.md`

### Workflow File

Located at `.github/workflows/sync-issues.yml`:

```yaml
name: Sync Issues to Archive

on:
  issues:
    types: [opened, edited, closed, reopened, labeled, unlabeled, deleted]
  issue_comment:
    types: [created, edited, deleted]

permissions:
  contents: write

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Handle deleted issue
        if: github.event.action == 'deleted' && github.event_name == 'issues'
        run: |
          ISSUE_NUMBER=${{ github.event.issue.number }}
          cd $GITHUB_WORKSPACE
          mkdir -p archive/issues
          rm -f archive/issues/issue-$(printf '%04d' $ISSUE_NUMBER).*
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add archive/issues/
          git diff --cached --quiet && exit 0
          git commit -m "archive: remove deleted issue #${ISSUE_NUMBER}"
          git push

      - name: Sync issue to markdown
        if: ${{ !(github.event.action == 'deleted' && github.event_name == 'issues') }}
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          ISSUE_NUMBER=${{ github.event.issue.number }}
          
          # Fetch issue data as JSON
          gh issue view "$ISSUE_NUMBER" \
            --repo ${{ github.repository }} \
            --json number,title,body,state,labels,createdAt,closedAt,author,comments \
            > /tmp/issue.json
          
          mkdir -p archive/issues
          
          # Build the markdown file with sanitized title in filename
          python3 << 'PYTHON'
          import json, os, glob, re

          with open("/tmp/issue.json") as f:
              issue = json.load(f)

          n = issue["number"]

          # --- Sanitize title for filename ---
          title = issue.get("title", "")
          # Strip to ASCII only
          title = title.encode("ascii", "ignore").decode("ascii")
          # Replace spaces with underscores
          title = title.replace(" ", "_")
          # Remove anything that isn't alphanumeric, underscore, hyphen, or dot
          title = re.sub(r"[^A-Za-z0-9_\-.]", "", title)
          # Collapse multiple underscores
          title = re.sub(r"_+", "_", title)
          # Strip leading/trailing underscores
          title = title.strip("_")
          # Truncate to 100 chars, adding ellipsis if needed
          if len(title) > 100:
              title = title[:100].rsplit("_", 1)[0] + "..."

          # --- Delete any existing file for this issue number (handles renames) ---
          for old_file in glob.glob(f"archive/issues/issue-{n:04d}.*"):
              os.remove(old_file)

          # --- Build markdown content ---
          md = []
          md.append(f"# #{n}: {issue['title']}")
          md.append("")
          md.append(f"**State:** {issue['state']}")
          md.append(f"**Author:** {issue['author']['login']}")
          md.append(f"**Created:** {issue['createdAt']}")
          if issue.get("closedAt"):
              md.append(f"**Closed:** {issue['closedAt']}")
          if issue.get("labels"):
              labels = ", ".join(l["name"] for l in issue["labels"])
              md.append(f"**Labels:** {labels}")
          md.append("")
          md.append("---")
          md.append("")
          md.append(issue.get("body") or "*No description provided.*")

          if issue.get("comments"):
              md.append("")
              md.append("---")
              md.append("")
              md.append("## Comments")
              for c in issue["comments"]:
                  md.append("")
                  md.append(f"### {c['author']['login']} — {c['createdAt']}")
                  md.append("")
                  md.append(c["body"])

          # --- Write file ---
          if title:
              filename = f"archive/issues/issue-{n:04d}.{title}.md"
          else:
              filename = f"archive/issues/issue-{n:04d}.md"
          with open(filename, "w") as f:
              f.write("\n".join(md) + "\n")
          PYTHON

      - name: Commit and push
        if: ${{ !(github.event.action == 'deleted' && github.event_name == 'issues') }}
        run: |
          cd $GITHUB_WORKSPACE
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add archive/issues/
          git diff --cached --quiet && exit 0
          ISSUE_NUMBER=${{ github.event.issue.number }}
          git commit -m "archive: sync issue #${ISSUE_NUMBER}"
          git push
```

## Initial Backfill of Existing Issues

For repos with existing issues, a one-time backfill script pulls all issues and generates markdown files using the same sanitized-title filename format as the GitHub Action. This script is provided as a standalone file: `archive.repo-issues.into.docs-issues.bash`.

### Where to Run

The script runs on your **local machine**, from inside a local clone of the repo. It creates the `archive/issues/` directory and writes markdown files into it locally — you then commit and push the results yourself.

### How It Talks to GitHub

The script uses `gh issue list` and `gh issue view` to fetch issue data from the **remote** GitHub repository via the GitHub API. It does not use `git` to read issues (issues aren't in git). The `OWNER/REPO` argument tells `gh` which remote repo to query, so the script doesn't need to be run from any particular directory — but you'll want to run it from the repo root so that `archive/issues/` lands in the right place.

### Access Permissions

The GitHub CLI (`gh`) must be installed and authenticated before running the script. To set this up:

```bash
# Install gh (if not already present)
sudo apt install gh

# Verify installation
gh --version

# Authenticate — this opens a browser-based OAuth flow
gh auth login
```

During `gh auth login`, select **GitHub.com**, choose **HTTPS** as the protocol, and authenticate via browser. This stores a token locally that `gh` uses for all subsequent API calls. For public repos, read access to issues requires no special scopes. For private repos, the token needs `repo` scope (the OAuth flow will prompt for this).

You can verify your authentication is working with:

```bash
gh auth status
```

### Usage

Run from the **root of your local clone**:

```bash
chmod +x archive.repo-issues.into.docs-issues.bash
./archive.repo-issues.into.docs-issues.bash OWNER/REPO
```

The `OWNER/REPO` argument is the GitHub organization (or username) and repository name — the same path that appears after `github.com/` in the repo URL. For example, given this repo:

`https://github.com/vyzed-public/deploy-OCI_Portainer-NPM-frontend`

The command would be:

```bash
./archive.repo-issues.into.docs-issues.bash vyzed-public/deploy-OCI_Portainer-NPM-frontend
```

After the script completes, commit and push the generated files:

```bash
git add archive/issues/
git commit -m "archive: backfill all issues into archive/issues/"
git push
```

**Note:** The backfill script is not affected by the deleted-issue edge case that the GitHub Action handles. The script gets its list of issue numbers from `gh issue list`, which only returns issues that currently exist — a deleted issue will never appear in that list.

### Script Contents

```bash
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
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#   - python3 available on PATH
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

ISSUE_NUMBERS=$(gh issue list --repo "$REPO" --state all --json number \
    --jq '.[].number' --limit 5000)

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
title = title.encode('ascii', 'ignore').decode('ascii')
title = title.replace(' ', '_')
title = re.sub(r'[^A-Za-z0-9_\-.]', '', title)
title = re.sub(r'_+', '_', title)
title = title.strip('_')
if len(title) > 100:
    title = title[:100].rsplit('_', 1)[0] + '...'

# --- Delete any existing file for this issue number ---
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
```

## Operational Considerations

- **Bot commits in history**: The action commits as `github-actions[bot]`. To isolate these, consider committing to a dedicated branch (e.g., `archive/issue-sync`) and merging periodically.
- **Deleted issues**: Handled by a dedicated early step in the workflow. When an issue is deleted, the action skips the `gh issue view` fetch (which would fail on a deleted issue) and instead directly removes the corresponding markdown file via glob match on `issue-NNNN.*`. The backfill script is unaffected since `gh issue list` only returns issues that currently exist.
- **Comment threading**: Comments are captured in chronological order, preserving the narrative flow of CLI output logs, configuration notes, and procedural steps.
- **Cross-tool portability**: The resulting markdown files are directly usable in Obsidian vaults and TiddlyWiki instances. Adding YAML frontmatter would further enhance filtering and linking in both tools.

## Potential Extensions

- YAML frontmatter with structured metadata for Obsidian/TiddlyWiki parsing
- Auto-generated index file (`archive/issues/README.md`) listing all issues by state and label
- Bidirectional sync (local markdown edits reflected back to GitHub Issues)
- Integration with TiddlyWiki's Node.js server for automatic tiddler creation from issue files

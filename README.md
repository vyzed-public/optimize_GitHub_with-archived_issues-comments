# optimize_GitHub_with-archived_issues-comments

## Usage

### For any new items added as Issues and/or Comments:

We have configured a GitHub action: [.github/workflows/sync-issues.yml](https://github.com/vyzed-public/optimize_GitHub_with-archived_issues-comments/blob/main/.github/workflows/sync-issues.yml) to add/update issues & comments into our repo's `archive/issues/` dir on a per-issue basis.

---

### For Backfills of Existing Issues (in pre-existing repos):
For repos with existing issues, a one-time backfill script pulls all issues and generates markdown files using the same sanitized-title filename format as the GitHub Action. 

This script is provided as a standalone file: `archive.repo-issues.into.docs-issues.bash`.

#### Where to Run
The script runs on your local machine, from inside a local clone of the repo. 

It creates the `archive/issues/` directory and writes markdown files into it locally — you then commit and push the results yourself.

#### How It Talks to GitHub
The script uses `gh issue list` and `gh issue view` to fetch issue data from the remote GitHub repository via the GitHub API. 

It does not use git to read issues (issues aren't in git). 

The OWNER/REPO argument tells `gh` which remote repo to query, so the script doesn't need to be run from any particular directory — but you'll want to run it from the repo root so that `archive/issues/` lands in the right place.

#### Access Permissions
The GitHub CLI (`gh`) must be installed and authenticated before running the script. 

To set this up:
```bash
# Install gh (if not already present)
sudo apt install gh

# Verify installation
gh --version

# Authenticate — this opens a browser-based OAuth flow
gh auth login
```

During `gh auth` login, select GitHub.com, choose HTTPS as the protocol, and authenticate via browser. 

This stores a token locally that `gh` uses for all subsequent API calls. 

For public repos, read access to issues requires no special scopes. 

For private repos, the token needs repo scope (the OAuth flow will prompt for this).

You can verify your authentication is working with:
```bash
gh auth status
```

#### Usage
Run from the root of your local clone:
```bash
chmod +x archive.repo-issues.into.docs-issues.bash
./archive.repo-issues.into.docs-issues.bash OWNER/REPO
```
The `OWNER/REPO` argument is the GitHub organization (or username) and repository name — the same path that appears after `github.com/` in the repo URL. 

For example, given this repo: 
```
https://github.com/vyzed-public/deploy-OCI_Portainer-NPM-frontend
```

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

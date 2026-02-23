# Beads → GitHub Sync

One-way sync from beads issues to GitHub Issues (and optionally GitHub Projects boards).

## How It Works

A GitHub Actions workflow (`.github/workflows/beads-sync.yml`) triggers on every push to `main` that modifies `.beads/issues.jsonl` or `.beads/issues/**`. It runs a bash script (`.github/scripts/beads-sync.sh`) that:

1. Reads all beads issues (supports both JSONL and directory-based formats)
2. Creates or updates corresponding GitHub Issues
3. Syncs comments and close reasons
4. Applies labels based on `issue_type` and `priority`
5. Optionally updates a GitHub Projects board with status columns
6. Commits updated map files back to the repo

## Files

| File | Purpose |
|------|---------|
| `.github/workflows/beads-sync.yml` | GitHub Actions workflow trigger |
| `.github/scripts/beads-sync.sh` | Sync logic script |
| `.beads/github-map.json` | Maps beads IDs → GitHub issue numbers (auto-generated) |
| `.beads/comment-map.json` | Tracks which comments have been synced (auto-generated) |

## Trigger Conditions

- **Automatic:** Push to `main` that modifies `.beads/issues.jsonl` or `.beads/issues/**`
- **Manual:** `workflow_dispatch` from GitHub Actions UI (useful for initial sync or debugging)

## Label Mapping

### Issue Type → GitHub Label

| Beads `issue_type` | GitHub Label |
|--------------------|-------------|
| `bug` | `bug` |
| `feature` | `enhancement` |
| `task` | `task` |
| `epic` | `epic` |
| *(other)* | `task` |

### Priority → GitHub Label

| Beads `priority` | GitHub Label |
|-------------------|-------------|
| `0` | `priority:critical` |
| `1` | `priority:high` |
| `2` | `priority:medium` |
| `3` | `priority:low` |

## Status Mapping (for GitHub Projects)

| Beads Status | Project Column |
|-------------|---------------|
| `open` | Todo |
| `pending` | Todo |
| `in_progress` | In Progress |
| `blocked` | Blocked |
| `hooked` | In Progress |
| `closed` | Done |
| `completed` | Done |

## Configuration

### GitHub Issues Only (default)

No configuration needed. The workflow uses `GITHUB_TOKEN` which is automatically provided by GitHub Actions.

### With GitHub Projects Board

1. Create a GitHub Project at `github.com/users/<username>/projects`
2. Note the project number from the URL
3. Edit `.github/workflows/beads-sync.yml` and set `PROJECT_NUMBER`:
   ```yaml
   env:
     PROJECT_NUMBER: "5"  # your project number
   ```
4. Ensure the project has a "Status" field with options matching the status mapping above

## Deduplication

The sync script prevents duplicate GitHub Issues through two mechanisms:

1. **Map file:** `.beads/github-map.json` tracks which beads IDs have already been created as GitHub Issues
2. **Title search fallback:** If the map is stale (e.g. after a fresh clone), the script searches GitHub Issues by title pattern `[beads-id]` before creating a new one

## Running Locally

```bash
export GH_TOKEN="$(gh auth token)"
export GITHUB_REPOSITORY="owner/repo"
export PROJECT_NUMBER=""  # optional
.github/scripts/beads-sync.sh --dry-run  # preview
.github/scripts/beads-sync.sh            # sync
```

## Permissions

The workflow requires these GitHub Actions permissions:
- `issues: write` — create/update/close GitHub Issues
- `contents: write` — commit map files back to repo
- `repository-projects: write` — update GitHub Projects board (if configured)

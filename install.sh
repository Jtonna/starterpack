#!/usr/bin/env bash
# install.sh — Install or upgrade the starterpack into the current directory.
#
# Downloads a tagged release of the starterpack from GitHub and copies
# the workflow files into the current project. Existing files are overwritten.
#
# Usage:
#   # Install latest prod release (default)
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash
#
#   # Install latest dev/pre-release
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --dev
#
#   # Install a specific prod version
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --prod v1.2.0
#
#   # Install a specific dev version
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --dev v1.2.0-dev.1
#
#   # Install any specific version (backwards compat)
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --version v1.2.0
#
#   # Dry run
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --dry-run

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
REPO_OWNER="Jtonna"
REPO_NAME="starterpack"
VERSION_FILE=".starterpack/VERSION"

# ── Colors (disabled if stdout is not a terminal) ───────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

# ── Manifest ─────────────────────────────────────────────────────────────────
MANIFEST=(
    ".starterpack/CLAUDE.md"
    ".gitattributes"
    ".starterpack/agent_instructions/BEHAVIORS_MANIFEST.xml"
    ".starterpack/agent_instructions/LIFECYCLE_MANIFEST.xml"
    ".starterpack/agent_instructions/MODELS_AND_ROLES.xml"
    ".starterpack/agent_instructions/behaviors/git-conventions.xml"
    ".starterpack/agent_instructions/behaviors/escalation.xml"
    ".starterpack/agent_instructions/behaviors/scope-enforcement.xml"
    ".starterpack/agent_instructions/behaviors/sub-task-tracking.xml"
    ".starterpack/agent_instructions/behaviors/documentation-structure.xml"
    ".starterpack/agent_instructions/behaviors/pr-template.xml"
    ".starterpack/agent_instructions/behaviors/human-gate.xml"
    ".starterpack/agent_instructions/behaviors/response-format.xml"
    ".starterpack/agent_instructions/behaviors/create-behavior.xml"
    ".starterpack/agent_instructions/behaviors/create-lifecycle.xml"
    ".starterpack/agent_instructions/behaviors/ci-gate.xml"
    ".starterpack/agent_instructions/behaviors/autonomous-nightly.xml"
    ".starterpack/agent_instructions/lifecycle/entry.xml"
    ".starterpack/agent_instructions/lifecycle/planning.xml"
    ".starterpack/agent_instructions/lifecycle/implementation.xml"
    ".starterpack/agent_instructions/lifecycle/docs.xml"
    ".starterpack/agent_instructions/lifecycle/pr.xml"
    ".starterpack/agent_instructions/lifecycle/authoring-behaviors-and-lifecycles.xml"
    ".starterpack/agent_instructions/lifecycle/nightly-autonomous-run.xml"
    ".github/workflows/comment-sync.yml"
    ".github/workflows/check-starterpack.yml"
    ".github/scripts/comment-sync.sh"
    ".github/comment-queue.json"
    ".claude/settings.local.json"
)

# ── Defaults ─────────────────────────────────────────────────────────────────
VERSION="${STARTERPACK_VERSION:-latest}"
DRY_RUN="${STARTERPACK_DRYRUN:-0}"
FORCE="${STARTERPACK_FORCE:-0}"
NO_COMMIT="${STARTERPACK_NO_COMMIT:-0}"
CHANNEL="prod"

# ── Parse flags ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --version|-v)
            VERSION="$2"; shift 2 ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        --force)
            FORCE=1; shift ;;
        --no-commit)
            NO_COMMIT=1; shift ;;
        --dev|-dev)
            CHANNEL="dev"
            # If next arg looks like a version, consume it
            if [ $# -gt 1 ] && echo "$2" | grep -qE '^v[0-9]'; then
                VERSION="$2"; shift 2
            else
                VERSION="latest"; shift
            fi
            ;;
        --prod|-prod)
            CHANNEL="prod"
            # If next arg looks like a version, consume it
            if [ $# -gt 1 ] && echo "$2" | grep -qE '^v[0-9]'; then
                VERSION="$2"; shift 2
            else
                VERSION="latest"; shift
            fi
            ;;
        -*)
            echo -e "${RED}Unknown flag: $1${RESET}" >&2; exit 1 ;;
        *)
            echo -e "${RED}Unexpected argument: $1${RESET}" >&2; exit 1 ;;
    esac
done

# ── Helper: download a URL to a file ────────────────────────────────────────
download() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        echo -e "${RED}ERROR: Neither curl nor wget found. Install one and retry.${RESET}" >&2
        exit 1
    fi
}

# ── Helper: fetch URL content to stdout ──────────────────────────────────────
fetch() {
    local url="$1"
    local auth_header=""
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        auth_header="Authorization: Bearer $GITHUB_TOKEN"
    fi
    if command -v curl >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            curl -fsSL -H "Accept: application/vnd.github+json" -H "$auth_header" "$url"
        else
            curl -fsSL -H "Accept: application/vnd.github+json" "$url"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ -n "$auth_header" ]; then
            wget -q -O - --header="Accept: application/vnd.github+json" --header="$auth_header" "$url"
        else
            wget -q -O - --header="Accept: application/vnd.github+json" "$url"
        fi
    else
        echo -e "${RED}ERROR: Neither curl nor wget found.${RESET}" >&2
        exit 1
    fi
}

# ── Temp directory with cleanup trap ─────────────────────────────────────────
TEMP_DIR=""
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# ── Step 1: Resolve version ─────────────────────────────────────────────────
resolve_version() {
    local requested="$1"
    local channel="${2:-prod}"

    if [ "$requested" != "latest" ]; then
        if ! echo "$requested" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
            echo -e "${RED}Invalid version format: $requested (expected v#.#.# or v#.#.#-suffix e.g. v1.0.0, v1.0.0-dev.1)${RESET}" >&2
            exit 1
        fi
        echo "$requested"
        return
    fi

    # "latest" resolution depends on channel
    if [ "$channel" = "dev" ]; then
        echo -e "${CYAN}Resolving latest dev release...${RESET}" >&2
        local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"
        local response
        if ! response=$(fetch "$api_url" 2>&1); then
            if echo "$response" | grep -q "403"; then
                echo -e "${RED}GitHub API rate limit hit. Set \$GITHUB_TOKEN or specify a version directly.${RESET}" >&2
            else
                echo -e "${RED}Failed to fetch releases: $response${RESET}" >&2
            fi
            exit 1
        fi

        # Find the first pre-release tag
        local tag=""
        if command -v jq >/dev/null 2>&1; then
            tag=$(echo "$response" | jq -r '[.[] | select(.prerelease == true)][0].tag_name')
        elif command -v python3 >/dev/null 2>&1; then
            tag=$(echo "$response" | python3 -c "
import sys, json
releases = json.load(sys.stdin)
pre = [r for r in releases if r.get('prerelease')]
print(pre[0]['tag_name'] if pre else '')
")
        else
            # Fallback: grep for tags with a dash (pre-release suffix)
            tag=$(echo "$response" | grep -oP '"tag_name"\s*:\s*"\Kv[0-9]+\.[0-9]+\.[0-9]+-[^"]+' | head -1 || true)
        fi

        if [ -z "$tag" ] || [ "$tag" = "null" ]; then
            echo -e "${RED}No dev/pre-release versions found. Use --prod or specify a version with --version.${RESET}" >&2
            exit 1
        fi

        echo -e "${GREEN}Latest dev release: $tag${RESET}" >&2
        echo "$tag"
    else
        echo -e "${CYAN}Resolving latest release...${RESET}" >&2
        local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
        local response
        if ! response=$(fetch "$api_url" 2>&1); then
            if echo "$response" | grep -q "403"; then
                echo -e "${RED}GitHub API rate limit hit. Set \$GITHUB_TOKEN or specify a version directly.${RESET}" >&2
            elif echo "$response" | grep -q "404"; then
                echo -e "${RED}No releases found. The starterpack repo may not have any tagged releases yet.${RESET}" >&2
            else
                echo -e "${RED}Failed to resolve latest release: $response${RESET}" >&2
            fi
            exit 1
        fi

        local tag=""
        if command -v jq >/dev/null 2>&1; then
            tag=$(echo "$response" | jq -r '.tag_name')
        elif command -v python3 >/dev/null 2>&1; then
            tag=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
        else
            tag=$(echo "$response" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' || true)
        fi

        if [ -z "$tag" ] || [ "$tag" = "null" ]; then
            echo -e "${RED}Failed to parse release tag from GitHub API response.${RESET}" >&2
            exit 1
        fi

        echo -e "${GREEN}Latest release: $tag${RESET}" >&2
        echo "$tag"
    fi
}

# ── Step 2: Check current version ───────────────────────────────────────────
get_current_version() {
    # Check new location first, then fall back to legacy location
    if [ -f "$VERSION_FILE" ]; then
        tr -d '[:space:]' < "$VERSION_FILE"
    elif [ -f ".starterpack-version" ]; then
        tr -d '[:space:]' < ".starterpack-version"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
resolved_version=$(resolve_version "$VERSION" "$CHANNEL")
current_version=$(get_current_version)

if [ "$current_version" = "$resolved_version" ] && [ "$FORCE" != "1" ]; then
    echo -e "${YELLOW}Already at $resolved_version. Use --force to reinstall.${RESET}"
    exit 0
fi

if [ -n "$current_version" ]; then
    echo -e "${CYAN}Upgrading from $current_version to $resolved_version${RESET}"
else
    echo -e "${CYAN}Installing starterpack $resolved_version${RESET}"
fi

# ── Migrate legacy version file ───────────────────────────────────────────
if [ -f ".starterpack-version" ]; then
    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY RUN] Would migrate .starterpack-version → $VERSION_FILE"
    else
        mkdir -p "$(dirname "$VERSION_FILE")"
        mv -f ".starterpack-version" "$VERSION_FILE"
        git rm -f --cached ".starterpack-version" 2>/dev/null || true
        echo -e "  ${GREEN}[ok] Migrated .starterpack-version → $VERSION_FILE${RESET}"
    fi
fi

# ── Dry run preview ─────────────────────────────────────────────────────────
if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo -e "${YELLOW}[DRY RUN] Would install these files:${RESET}"
    for file in "${MANIFEST[@]}"; do
        if [ -e "$file" ]; then
            echo -e "  ${YELLOW}[overwrite] $file${RESET}"
        else
            echo -e "  ${GREEN}[create] $file${RESET}"
        fi
    done
    echo -e "  ${GREEN}[create] $VERSION_FILE${RESET}"
    echo ""
    echo -e "${YELLOW}[DRY RUN] No files were written.${RESET}"
    exit 0
fi

# ── Step 3: Download release archive ────────────────────────────────────────
archive_url="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/tags/${resolved_version}.tar.gz"
TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'starterpack')
archive_file="$TEMP_DIR/starterpack-${resolved_version}.tar.gz"

echo -e "${CYAN}Downloading $archive_url${RESET}"
if ! download "$archive_url" "$archive_file"; then
    echo -e "${RED}Download failed. Check that version $resolved_version exists at https://github.com/${REPO_OWNER}/${REPO_NAME}/releases${RESET}" >&2
    exit 1
fi

# ── Step 4: Extract ─────────────────────────────────────────────────────────
echo -e "${CYAN}Extracting...${RESET}"
tar -xzf "$archive_file" -C "$TEMP_DIR"

# GitHub archives extract to a folder named repo-version (e.g. starterpack-1.0.0)
extracted_root=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "$extracted_root" ]; then
    echo -e "${RED}Archive extraction failed: no root directory found.${RESET}" >&2
    exit 1
fi

# ── Step 5: Copy manifest files ─────────────────────────────────────────────
copied=0
skipped=0
for file in "${MANIFEST[@]}"; do
    source_path="$extracted_root/$file"
    dest_path="./$file"

    if [ ! -f "$source_path" ]; then
        echo -e "  ${YELLOW}[skip] $file (not in release)${RESET}"
        skipped=$((skipped + 1))
        continue
    fi

    dest_dir=$(dirname "$dest_path")
    if [ ! -d "$dest_dir" ]; then
        mkdir -p "$dest_dir"
    fi

    cp -f "$source_path" "$dest_path"
    echo -e "  ${GREEN}[ok] $file${RESET}"
    copied=$((copied + 1))
done

# ── Step 5b: Install CLAUDE.md to project root ──────────────────────────────
# The starterpack stores CLAUDE.md inside .starterpack/, but Claude Code
# reads project instructions from the repo root.
if [ -f ".starterpack/CLAUDE.md" ]; then
    cp -f ".starterpack/CLAUDE.md" "./CLAUDE.md"
    echo -e "  ${GREEN}[ok] CLAUDE.md (copied to project root)${RESET}"
fi

# ── Step 6: Write version file ──────────────────────────────────────────────
printf '%s' "$resolved_version" > "$VERSION_FILE"
echo -e "  ${GREEN}[ok] $VERSION_FILE${RESET}"

# ── Step 7: Ensure Agent Teams is enabled ────────────────────────────────────
settings_path=".claude/settings.local.json"
settings_dir=".claude"

if [ ! -d "$settings_dir" ]; then
    mkdir -p "$settings_dir"
fi

merge_agent_teams() {
    # Merge env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1" into settings.local.json
    local settings_file="$1"

    if [ ! -f "$settings_file" ]; then
        # Create new file
        printf '{\n  "env": {\n    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"\n  }\n}\n' > "$settings_file"
        echo -e "  ${GREEN}[ok] .claude/settings.local.json (created: Agent Teams enabled)${RESET}"
        return
    fi

    local content
    content=$(cat "$settings_file")

    # Check if already set
    if echo "$content" | grep -q '"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS".*"1"'; then
        echo -e "  ${GREEN}[ok] .claude/settings.local.json (Agent Teams already enabled)${RESET}"
        return
    fi

    # Try jq
    if command -v jq >/dev/null 2>&1; then
        local merged
        if merged=$(echo "$content" | jq '.env = (.env // {}) + {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}' 2>/dev/null); then
            echo "$merged" > "$settings_file"
            echo -e "  ${GREEN}[ok] .claude/settings.local.json (updated: Agent Teams enabled)${RESET}"
            return
        fi
    fi

    # Try python3
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "
import json, sys
with open('$settings_file', 'r') as f:
    data = json.load(f)
if 'env' not in data:
    data['env'] = {}
data['env']['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1'
with open('$settings_file', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null; then
            echo -e "  ${GREEN}[ok] .claude/settings.local.json (updated: Agent Teams enabled)${RESET}"
            return
        fi
    fi

    # Fallback: grep/sed approach — insert into existing "env" block or add one
    if echo "$content" | grep -q '"env"'; then
        # Add the key inside the existing env block (after the "env": { line)
        sed -i.bak 's/"env"\s*:\s*{/"env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",/' "$settings_file" && rm -f "${settings_file}.bak"
        echo -e "  ${GREEN}[ok] .claude/settings.local.json (updated: Agent Teams enabled)${RESET}"
    else
        # No env block — inject one before the closing brace
        sed -i.bak 's/}$/,  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }/' "$settings_file" && rm -f "${settings_file}.bak"
        echo -e "  ${GREEN}[ok] .claude/settings.local.json (updated: Agent Teams enabled)${RESET}"
    fi
}

merge_agent_teams "$settings_path"

# ── Step 8: Ensure critical paths are not gitignored ────────────────────────
if [ -f ".gitignore" ]; then
    # Test representative files from each critical path
    critical_paths=(
        ".starterpack/VERSION"
        ".claude/settings.local.json"
        ".github/workflows/comment-sync.yml"
        "CLAUDE.md"
        ".gitattributes"
    )

    ignored_paths=()
    for path in "${critical_paths[@]}"; do
        # git check-ignore returns 0 if the file IS ignored
        if git check-ignore --no-index "$path" >/dev/null 2>&1; then
            ignored_paths+=("$path")
        fi
    done

    if [ ${#ignored_paths[@]} -gt 0 ]; then
        if [ "$DRY_RUN" = "1" ]; then
            echo -e "  ${YELLOW}[DRY RUN] Would append negation patterns to .gitignore (${#ignored_paths[@]} paths currently ignored)${RESET}"
        else
            # Append negation patterns to .gitignore
            cat >> .gitignore <<'EOF'

# starterpack — these paths must be tracked by git
!.starterpack/
!.starterpack/**
!.claude/
!.claude/**
!.github/
!.github/**
!CLAUDE.md
!.gitattributes
EOF
            echo -e "  ${GREEN}[ok] .gitignore updated with negation patterns (${#ignored_paths[@]} paths were ignored)${RESET}"
        fi
    else
        echo -e "  ${GREEN}[ok] .gitignore check passed (critical paths not ignored)${RESET}"
    fi
else
    echo -e "  ${YELLOW}[skip] No .gitignore found${RESET}"
fi

# ── Step 9: Clean up legacy beads hooks ──────────────────────────────────────
if [ -d ".git/hooks" ]; then
    for hook in pre-commit post-merge; do
        hook_path=".git/hooks/$hook"
        if [ -f "$hook_path" ] && grep -q "beads\|\.beads\|bd " "$hook_path" 2>/dev/null; then
            rm -f "$hook_path"
            echo -e "  ${GREEN}[ok] Removed legacy beads hook: .git/hooks/$hook${RESET}"
        fi
    done
fi

# ── Step 10: Auto-commit ────────────────────────────────────────────────────
if [ "$NO_COMMIT" != "1" ]; then
    if [ ! -d ".git" ]; then
        echo -e "  ${YELLOW}[skip] Not a git repository - skipping commit${RESET}"
    else
        # Check for pre-existing staged changes
        prior_staged=$(git diff --cached --name-only 2>/dev/null || true)
        if [ -n "$prior_staged" ]; then
            echo ""
            echo -e "  ${YELLOW}[warn] Skipping auto-commit: you have staged changes that predate this install.${RESET}"
            echo -e "  ${YELLOW}       Commit or unstage your existing changes first, then re-run.${RESET}"
            echo -e "  ${YELLOW}       Or commit the starterpack files manually:${RESET}"
            echo -e "  ${CYAN}         git add CLAUDE.md .starterpack/${RESET}"
            if [ -n "$current_version" ]; then
                commit_action="upgrade"
            else
                commit_action="install"
            fi
            echo -e "  ${CYAN}         git commit -m 'chore: $commit_action starterpack $resolved_version'${RESET}"
        else
            # Stage only specific installed files
            files_to_stage=(
                "CLAUDE.md"
                ".starterpack/"
                ".gitattributes"
                ".claude/"
                ".github/"
                ".gitignore"
            )
            for f in "${files_to_stage[@]}"; do
                if [ -e "$f" ]; then
                    git add -- "$f" 2>/dev/null || true
                fi
            done

            staged=$(git diff --cached --name-only 2>/dev/null || true)
            if [ -n "$staged" ]; then
                if [ -n "$current_version" ]; then
                    commit_action="upgrade starterpack to $resolved_version"
                else
                    commit_action="install starterpack $resolved_version"
                fi
                if git commit -m "chore: $commit_action" 2>/dev/null; then
                    echo -e "  ${GREEN}[ok] Committed: chore: $commit_action${RESET}"
                    # Push if on main branch, warn otherwise
                    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
                    if [ "$current_branch" = "main" ] || [ "$current_branch" = "master" ]; then
                        if git push 2>/dev/null; then
                            echo -e "  ${GREEN}[ok] Pushed to $current_branch${RESET}"
                        else
                            echo -e "  ${YELLOW}[warn] git push failed - push manually${RESET}"
                        fi
                    else
                        echo -e "  ${YELLOW}[warn] Not on main branch ($current_branch) - skipping push. Push manually when ready.${RESET}"
                    fi
                else
                    echo -e "  ${YELLOW}[warn] git commit failed - commit manually${RESET}"
                fi
            else
                echo -e "  ${GREEN}[ok] No changes to commit (files already up to date)${RESET}"
            fi
        fi
    fi
fi

# ── Step 11: Post-install checks ────────────────────────────────────────────
echo ""
echo -e "${GREEN}Installed starterpack $resolved_version ($copied files)${RESET}"
if [ "$skipped" -gt 0 ]; then
    echo -e "${YELLOW}  $skipped files skipped (not found in release)${RESET}"
fi
echo ""

# Check prerequisites
warnings=()

if ! command -v claude >/dev/null 2>&1; then
    warnings+=("Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code")
fi

if [ ${#warnings[@]} -gt 0 ]; then
    echo -e "${YELLOW}Next steps:${RESET}"
    for w in "${warnings[@]}"; do
        echo -e "  ${YELLOW}- $w${RESET}"
    done
else
    echo -e "${GREEN}Ready to go. Start the orchestrator with: claude${RESET}"
fi

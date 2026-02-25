#!/usr/bin/env bash
# install.sh — Install or upgrade the starterpack into the current directory.
#
# Downloads a tagged release of the starterpack from GitHub and copies
# the workflow files into the current project. Existing files are overwritten.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --init-beads
#
#   # Install a specific version
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --version v1.2.0
#
#   # Dry run
#   curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --dry-run

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
REPO_OWNER="Jtonna"
REPO_NAME="starterpack"
VERSION_FILE=".starterpack-version"

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

# ── Manifest — must match install.ps1 EXACTLY ───────────────────────────────
MANIFEST=(
    "CLAUDE.md"
    ".gitattributes"
    ".starterpack/agent_instructions/BEHAVIORS_MANIFEST.xml"
    ".starterpack/agent_instructions/LIFECYCLE_MANIFEST.xml"
    ".starterpack/agent_instructions/MODELS_AND_ROLES.xml"
    ".starterpack/agent_instructions/behaviors/git-with-beads.xml"
    ".starterpack/agent_instructions/behaviors/escalation.xml"
    ".starterpack/agent_instructions/behaviors/scope-enforcement.xml"
    ".starterpack/agent_instructions/behaviors/sub-task-tracking.xml"
    ".starterpack/agent_instructions/behaviors/documentation-structure.xml"
    ".starterpack/agent_instructions/behaviors/pr-template.xml"
    ".starterpack/agent_instructions/behaviors/human-gate.xml"
    ".starterpack/agent_instructions/behaviors/response-format.xml"
    ".starterpack/agent_instructions/behaviors/create-behavior.xml"
    ".starterpack/agent_instructions/behaviors/create-lifecycle.xml"
    ".starterpack/agent_instructions/lifecycle/entry.xml"
    ".starterpack/agent_instructions/lifecycle/planning.xml"
    ".starterpack/agent_instructions/lifecycle/implementation.xml"
    ".starterpack/agent_instructions/lifecycle/docs.xml"
    ".starterpack/agent_instructions/lifecycle/pr.xml"
    ".starterpack/agent_instructions/lifecycle/authoring-behaviors-and-lifecycles.xml"
    ".starterpack/beads_sync.md"
    ".starterpack/hooks/pre-commit"
    ".starterpack/hooks/post-merge"
    ".github/workflows/beads-sync.yml"
    ".github/scripts/beads-sync.sh"
    ".beads/.gitignore"
    ".claude/settings.local.json"
)

# ── Defaults ─────────────────────────────────────────────────────────────────
VERSION="${STARTERPACK_VERSION:-latest}"
DRY_RUN="${STARTERPACK_DRYRUN:-0}"
FORCE="${STARTERPACK_FORCE:-0}"
INIT_BEADS="${STARTERPACK_INIT_BEADS:-0}"
NO_COMMIT="${STARTERPACK_NO_COMMIT:-0}"

# ── Parse flags ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --version|-v)
            VERSION="$2"; shift 2 ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        --force)
            FORCE=1; shift ;;
        --init-beads)
            INIT_BEADS=1; shift ;;
        --no-commit)
            NO_COMMIT=1; shift ;;
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
    if [ "$requested" != "latest" ]; then
        if ! echo "$requested" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo -e "${RED}Invalid version format: $requested (expected v#.#.# e.g. v1.0.0)${RESET}" >&2
            exit 1
        fi
        echo "$requested"
        return
    fi

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

    # Extract tag_name from JSON — try jq, then python3, then grep
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
}

# ── Step 2: Check current version ───────────────────────────────────────────
get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        tr -d '[:space:]' < "$VERSION_FILE"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
resolved_version=$(resolve_version "$VERSION")
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

# ── Beads prerequisite gate ──────────────────────────────────────────────────
beads_initialized=false
if [ -f ".beads/config.yaml" ] || [ -f ".beads/metadata.json" ]; then
    beads_initialized=true
fi

if [ "$beads_initialized" = false ]; then
    if [ "$INIT_BEADS" != "1" ]; then
        echo ""
        echo -e "${RED}  ERROR: Beads is not initialized in this project.${RESET}"
        echo -e "${YELLOW}  The starterpack requires Beads for ticket tracking.${RESET}"
        echo ""
        echo -e "${YELLOW}  Re-run with --init-beads to auto-initialize:${RESET}"
        echo -e "${CYAN}    curl -fsSL https://raw.githubusercontent.com/Jtonna/starterpack/main/install.sh | bash -s -- --init-beads${RESET}"
        echo ""
        exit 1
    fi
    if ! command -v bd >/dev/null 2>&1; then
        echo ""
        echo -e "${RED}  ERROR: --init-beads was specified but 'bd' was not found on PATH.${RESET}"
        echo -e "${YELLOW}  Install Beads from: https://github.com/steveyegge/beads${RESET}"
        echo ""
        exit 1
    fi
    if ! command -v dolt >/dev/null 2>&1; then
        echo ""
        echo -e "${RED}  ERROR: --init-beads was specified but 'dolt' was not found on PATH.${RESET}"
        echo -e "${YELLOW}  Beads v0.56+ requires Dolt as its database backend.${RESET}"
        echo -e "${YELLOW}  Install Dolt from: https://github.com/dolthub/dolt${RESET}"
        echo ""
        exit 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        echo "[DRY RUN] Would run: bd init (Beads not yet initialized)"
    else
        echo "  Initializing Beads..."
        if ! bd init; then
            echo -e "${RED}  ERROR: bd init failed.${RESET}"
            echo -e "${YELLOW}  Run 'bd init' manually, then re-run the installer.${RESET}"
            exit 1
        fi
        echo -e "${GREEN}  [ok] Beads initialized successfully.${RESET}"
        # bd init creates an AGENTS.md that conflicts with the starterpack setup — discard it
        if [ -f "AGENTS.md" ]; then
            rm -f "AGENTS.md"
        fi
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

# ── Step 8: Install git hooks ───────────────────────────────────────────────
if [ -d ".git" ]; then
    # Install all beads hooks
    if command -v bd >/dev/null 2>&1; then
        if bd hooks install --force 2>/dev/null; then
            hooks_msg="pre-commit, post-merge, pre-push, post-checkout, prepare-commit-msg"
            echo -e "  ${GREEN}[ok] Beads hooks installed ($hooks_msg)${RESET}"
        else
            echo -e "  ${YELLOW}[warn] bd hooks install failed - run 'bd hooks install' manually${RESET}"
        fi
    fi

    # Overlay starterpack custom hooks (enhanced post-merge with worktree support and auto-commit)
    hooks_source_dir=".starterpack/hooks"
    git_hooks_dir=".git/hooks"
    if [ -d "$hooks_source_dir" ]; then
        for hook_file in "$hooks_source_dir"/*; do
            [ -f "$hook_file" ] || continue
            hook_name=$(basename "$hook_file")
            dest_hook="$git_hooks_dir/$hook_name"
            cp -f "$hook_file" "$dest_hook"
            chmod +x "$dest_hook"
            echo -e "  ${GREEN}[ok] .git/hooks/$hook_name (starterpack override)${RESET}"
        done
    fi
fi

# ── Step 9: Auto-commit ─────────────────────────────────────────────────────
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
            echo -e "  ${CYAN}         git add CLAUDE.md .starterpack/ .starterpack-version${RESET}"
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
                ".starterpack-version"
                ".starterpack/"
                ".gitattributes"
                ".claude/"
                ".github/"
            )
            if [ -d ".beads/" ]; then
                files_to_stage+=(".beads/")
            fi
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
                else
                    echo -e "  ${YELLOW}[warn] git commit failed - commit manually${RESET}"
                fi
            else
                echo -e "  ${GREEN}[ok] No changes to commit (files already up to date)${RESET}"
            fi
        fi
    fi
fi

# ── Step 10: Post-install checks ────────────────────────────────────────────
echo ""
echo -e "${GREEN}Installed starterpack $resolved_version ($copied files)${RESET}"
if [ "$skipped" -gt 0 ]; then
    echo -e "${YELLOW}  $skipped files skipped (not found in release)${RESET}"
fi
echo ""

# Check prerequisites
warnings=()

if ! command -v bd >/dev/null 2>&1; then
    warnings+=("Beads CLI (bd) not found. Install from: https://github.com/steveyegge/beads")
fi

if ! command -v dolt >/dev/null 2>&1; then
    warnings+=("Dolt not found. Beads v0.56+ uses Dolt as its database backend. Install from: https://github.com/dolthub/dolt")
fi

if ! command -v claude >/dev/null 2>&1; then
    warnings+=("Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code")
fi

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    warnings+=("Neither jq nor python3 found. The pre-commit hook needs one of these to flush beads issues to JSONL for GitHub sync.")
fi

if [ ! -f ".beads/config.yaml" ] && [ ! -f ".beads/metadata.json" ]; then
    warnings+=("Beads not initialized. Run: bd init --prefix <your-prefix>-")
fi

if [ ${#warnings[@]} -gt 0 ]; then
    echo -e "${YELLOW}Next steps:${RESET}"
    for w in "${warnings[@]}"; do
        echo -e "  ${YELLOW}- $w${RESET}"
    done
else
    echo -e "${GREEN}Ready to go. Start the orchestrator with: claude${RESET}"
fi

#Requires -Version 5.1
<#
.SYNOPSIS
    Install or upgrade the starterpack into the current directory.

.DESCRIPTION
    Downloads a tagged release of the starterpack from GitHub and copies
    the workflow files into the current project. Existing files are overwritten.

.PARAMETER Version
    The release tag to install (e.g. "v1.0.0"). Defaults to the latest release.
    Can also be set via $env:STARTERPACK_VERSION.

.PARAMETER DryRun
    Preview what would be installed without writing any files.

.PARAMETER Force
    Reinstall even if the current version matches.

.EXAMPLE
    # Install latest version
    irm https://raw.githubusercontent.com/Jtonna/starterpack/main/install.ps1 | iex

    # Install a specific version
    $env:STARTERPACK_VERSION = "v1.2.0"
    irm https://raw.githubusercontent.com/Jtonna/starterpack/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$Version = $env:STARTERPACK_VERSION,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$InitBeads,
    [switch]$NoCommit
)

# When piped through iex, CmdletBinding/param are ignored.
# The & { } wrapper below ensures the script body runs correctly in both modes.
& {
    param(
        [string]$Version,
        [switch]$DryRun,
        [switch]$Force,
        [switch]$InitBeads,
        [switch]$NoCommit
    )

    if ($env:STARTERPACK_DRYRUN -eq "1") { $DryRun = [switch]::Present }
    if ($env:STARTERPACK_FORCE -eq "1") { $Force = [switch]::Present }
    if ($env:STARTERPACK_INIT_BEADS -eq "1") { $InitBeads = $true }
    if ($env:STARTERPACK_NO_COMMIT -eq "1") { $NoCommit = $true }
    if (-not $Version) {
        if ($env:STARTERPACK_VERSION) { $Version = $env:STARTERPACK_VERSION }
        else { $Version = "latest" }
    }

    $ErrorActionPreference = "Stop"

    # PS 5.1 defaults to TLS 1.0 which GitHub rejects
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $RepoOwner = "Jtonna"
    $RepoName = "starterpack"
    $VersionFile = ".starterpack-version"

    # Files to copy from the release archive into the target project
    $Manifest = @(
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
        ".starterpack/hooks/post-merge"
        ".github/workflows/beads-sync.yml"
        ".github/scripts/beads-sync.sh"
        ".beads/.gitignore"
        ".claude/settings.local.json"
    )

    function Get-AuthHeaders {
        $headers = @{ "Accept" = "application/vnd.github+json" }
        if ($env:GITHUB_TOKEN) {
            $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
        }
        return $headers
    }

    function Resolve-ReleaseVersion {
        param([string]$Requested)

        if ($Requested -ne "latest") {
            if ($Requested -notmatch "^v\d+\.\d+\.\d+$") {
                throw "Invalid version format: $Requested (expected v#.#.# e.g. v1.0.0)"
            }
            return $Requested
        }

        Write-Host "Resolving latest release..." -ForegroundColor Cyan
        $url = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
        try {
            $release = Invoke-RestMethod -Uri $url -Headers (Get-AuthHeaders)
            $tag = $release.tag_name
            Write-Host "Latest release: $tag" -ForegroundColor Green
            return $tag
        }
        catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -eq 403) {
                throw "GitHub API rate limit hit. Set `$env:GITHUB_TOKEN or specify a version directly."
            }
            if ($status -eq 404) {
                throw "No releases found. The starterpack repo may not have any tagged releases yet."
            }
            throw "Failed to resolve latest release: $_"
        }
    }

    function Get-CurrentVersion {
        if (Test-Path $VersionFile) {
            return (Get-Content $VersionFile -Raw).Trim()
        }
        return $null
    }

    $tempZip = $null
    $tempDir = $null

    try {
        # Step 1: Resolve version
        $resolvedVersion = Resolve-ReleaseVersion -Requested $Version

        # Step 2: Check if already installed
        $currentVersion = Get-CurrentVersion
        if ($currentVersion -eq $resolvedVersion -and -not $Force) {
            Write-Host "Already at $resolvedVersion. Use -Force to reinstall." -ForegroundColor Yellow
            return
        }

        if ($currentVersion) {
            Write-Host "Upgrading from $currentVersion to $resolvedVersion" -ForegroundColor Cyan
        } else {
            Write-Host "Installing starterpack $resolvedVersion" -ForegroundColor Cyan
        }

        # --- Beads prerequisite gate ---
        $beadsInitialized = (Test-Path ".beads/config.yaml") -or (Test-Path ".beads/metadata.json")

        if (-not $beadsInitialized) {
            if (-not $InitBeads) {
                Write-Host ""
                Write-Host "  ERROR: Beads is not initialized in this project." -ForegroundColor Red
                Write-Host ""
                Write-Host "  The starterpack requires Beads for ticket tracking." -ForegroundColor Yellow
                Write-Host "  No .beads/ directory was found in the current directory." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  To initialize Beads and proceed with installation, re-run with -InitBeads" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  To initialize Beads manually first, run:" -ForegroundColor Yellow
                Write-Host "    bd init" -ForegroundColor Cyan
                Write-Host "  Then re-run the installer." -ForegroundColor Yellow
                Write-Host ""
                return
            }
            if (-not (Get-Command "bd" -ErrorAction SilentlyContinue)) {
                Write-Host ""
                Write-Host "  ERROR: -InitBeads was specified but 'bd' was not found on PATH." -ForegroundColor Red
                Write-Host "  Install Beads from: https://github.com/cosmix/beads" -ForegroundColor Yellow
                Write-Host ""
                return
            }
            if ($DryRun) {
                Write-Host "[DRY RUN] Would run: bd init (Beads not yet initialized)"
            } else {
                Write-Host "  Initializing Beads..."
                bd init
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  ERROR: bd init failed (exit code $LASTEXITCODE)." -ForegroundColor Red
                    Write-Host "  Run 'bd init' manually, then re-run the installer." -ForegroundColor Yellow
                    return
                }
                Write-Host "  [ok] Beads initialized successfully." -ForegroundColor Green
                # bd init creates an AGENTS.md that conflicts with the starterpack setup — discard it
                if (Test-Path "AGENTS.md") {
                    Remove-Item "AGENTS.md" -Force
                }
            }
        }

        if ($DryRun) {
            Write-Host ""
            Write-Host "[DRY RUN] Would install these files:" -ForegroundColor Yellow
            foreach ($file in $Manifest) {
                $exists = Test-Path $file
                $label = if ($exists) { "overwrite" } else { "create" }
                Write-Host "  [$label] $file" -ForegroundColor $(if ($exists) { "Yellow" } else { "Green" })
            }
            Write-Host "  [create] $VersionFile" -ForegroundColor Green
            Write-Host ""
            Write-Host "[DRY RUN] No files were written." -ForegroundColor Yellow
            return
        }

        # Step 3: Download release archive
        $archiveUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/tags/$resolvedVersion.zip"
        $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "starterpack-$resolvedVersion.zip"
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "starterpack-extract-$([guid]::NewGuid().ToString('N').Substring(0,8))"

        Write-Host "Downloading $archiveUrl" -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $archiveUrl -OutFile $tempZip -UseBasicParsing
        }
        catch {
            throw "Download failed. Check that version $resolvedVersion exists at https://github.com/$RepoOwner/$RepoName/releases"
        }

        # Step 4: Extract
        Write-Host "Extracting..." -ForegroundColor Cyan
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

        # GitHub archives extract to a folder named repo-version (e.g. starterpack-1.0.0)
        $extractedRoot = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
        if (-not $extractedRoot) {
            throw "Archive extraction failed: no root directory found."
        }

        # Step 5: Copy manifest files
        $copied = 0
        $skipped = 0
        foreach ($file in $Manifest) {
            $sourcePath = Join-Path $extractedRoot.FullName ($file -replace "/", [IO.Path]::DirectorySeparatorChar)
            $destPath = Join-Path $PWD ($file -replace "/", [IO.Path]::DirectorySeparatorChar)

            if (-not (Test-Path $sourcePath)) {
                Write-Host "  [skip] $file (not in release)" -ForegroundColor Yellow
                $skipped++
                continue
            }

            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            Copy-Item -Path $sourcePath -Destination $destPath -Force
            Write-Host "  [ok] $file" -ForegroundColor Green
            $copied++
        }

        # Step 6: Write version file
        Set-Content -Path $VersionFile -Value $resolvedVersion -NoNewline
        Write-Host "  [ok] $VersionFile" -ForegroundColor Green

        # Step 7: Ensure Agent Teams is enabled
        # Nested Join-Path for PS 5.1 compat (3-arg form requires PS 6+)
        $settingsPath = Join-Path (Join-Path $PWD ".claude") "settings.local.json"
        $settingsDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }
        if (Test-Path $settingsPath) {
            # Merge: read existing, ensure env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is set
            try {
                $existingSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                $needsUpdate = $false
                if (-not $existingSettings.env) {
                    $existingSettings | Add-Member -NotePropertyName "env" -NotePropertyValue ([PSCustomObject]@{}) -Force
                    $needsUpdate = $true
                }
                if ($existingSettings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -ne "1") {
                    $existingSettings.env | Add-Member -NotePropertyName "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" -NotePropertyValue "1" -Force
                    $needsUpdate = $true
                }
                if ($needsUpdate) {
                    $existingSettings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
                    Write-Host "  [ok] .claude/settings.local.json (updated: Agent Teams enabled)" -ForegroundColor Green
                } else {
                    Write-Host "  [ok] .claude/settings.local.json (Agent Teams already enabled)" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "  [warn] Could not parse .claude/settings.local.json — skipping Agent Teams config" -ForegroundColor Yellow
            }
        }
        else {
            $settings = [PSCustomObject]@{
                env = [PSCustomObject]@{
                    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
                }
            }
            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
            Write-Host "  [ok] .claude/settings.local.json (created: Agent Teams enabled)" -ForegroundColor Green
        }

        # Step 8: Install git hooks
        $hooksSourceDir = Join-Path (Join-Path $PWD ".starterpack") "hooks"
        $gitHooksDir = Join-Path (Join-Path $PWD ".git") "hooks"
        if ((Test-Path $hooksSourceDir) -and (Test-Path (Join-Path $PWD ".git"))) {
            foreach ($hookFile in (Get-ChildItem -Path $hooksSourceDir -File -ErrorAction SilentlyContinue)) {
                $destHook = Join-Path $gitHooksDir $hookFile.Name
                Copy-Item -Path $hookFile.FullName -Destination $destHook -Force
                Write-Host "  [ok] .git/hooks/$($hookFile.Name) (installed from .starterpack/hooks/)" -ForegroundColor Green
            }
        }

        # --- Auto-commit ---
        if (-not $NoCommit) {
            if (-not (Test-Path ".git")) {
                Write-Host "  [skip] Not a git repository - skipping commit" -ForegroundColor Yellow
            } else {
                # Temporarily relax error preference for git commands (git writes
                # warnings like CRLF normalization to stderr, which PowerShell
                # converts to terminating errors under $ErrorActionPreference=Stop).
                $prevErrorPref = $ErrorActionPreference
                $ErrorActionPreference = "Continue"

                # Check for pre-existing staged changes
                $priorStaged = git diff --cached --name-only 2>$null
                if ($priorStaged) {
                    $ErrorActionPreference = $prevErrorPref
                    Write-Host ""
                    Write-Host "  [warn] Skipping auto-commit: you have staged changes that predate this install." -ForegroundColor Yellow
                    Write-Host "         Commit or unstage your existing changes first, then re-run." -ForegroundColor Yellow
                    Write-Host "         Or commit the starterpack files manually:" -ForegroundColor Yellow
                    Write-Host "           git add CLAUDE.md .starterpack/ .starterpack-version" -ForegroundColor Cyan
                    $commitAction = if ($currentVersion) { "upgrade" } else { "install" }
                    Write-Host "           git commit -m 'chore: $commitAction starterpack $resolvedVersion'" -ForegroundColor Cyan
                } else {
                    if ($DryRun) {
                        $ErrorActionPreference = $prevErrorPref
                        $commitAction = if ($currentVersion) { "upgrade" } else { "install" }
                        Write-Host "[DRY RUN] Would commit: chore: $commitAction starterpack $resolvedVersion"
                    } else {
                        # Stage only specific installed files
                        $filesToStage = @(
                            "CLAUDE.md",
                            ".starterpack-version",
                            ".starterpack/",
                            ".gitattributes",
                            ".claude/",
                            ".github/"
                        )
                        if (Test-Path ".beads/") { $filesToStage += ".beads/" }
                        foreach ($f in $filesToStage) {
                            if (Test-Path $f) { git add -- $f 2>$null }
                        }

                        $staged = git diff --cached --name-only 2>$null
                        $ErrorActionPreference = $prevErrorPref

                        if ($staged) {
                            $commitAction = if ($currentVersion) { "upgrade starterpack to $resolvedVersion" } else { "install starterpack $resolvedVersion" }
                            git commit -m "chore: $commitAction" 2>$null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "  [ok] Committed: chore: $commitAction" -ForegroundColor Green
                            } else {
                                Write-Host "  [warn] git commit failed - commit manually" -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "  [ok] No changes to commit (files already up to date)" -ForegroundColor Green
                        }
                    }
                }
            }
        }

        # Step 10: Post-install checks
        Write-Host ""
        Write-Host "Installed starterpack $resolvedVersion ($copied files)" -ForegroundColor Green
        if ($skipped -gt 0) {
            Write-Host "  $skipped files skipped (not found in release)" -ForegroundColor Yellow
        }
        Write-Host ""

        # Check prerequisites
        $warnings = @()

        if (-not (Get-Command "bd" -ErrorAction SilentlyContinue)) {
            $warnings += "Beads CLI (bd) not found. Install from: https://github.com/cosmix/beads"
        }

        if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
            $warnings += "Claude Code CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code"
        }

        if (-not (Test-Path ".beads/config.yaml") -and -not (Test-Path ".beads/metadata.json")) {
            $warnings += "Beads not initialized. Run: bd init --prefix <your-prefix>-"
        }

        if ($warnings.Count -gt 0) {
            Write-Host "Next steps:" -ForegroundColor Yellow
            foreach ($w in $warnings) {
                Write-Host "  - $w" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Ready to go. Run 'claude' to start the orchestrator." -ForegroundColor Green
        }
    }
    finally {
        # Cleanup temp files
        if ($tempZip -and (Test-Path $tempZip)) {
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        }
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} -Version $Version -DryRun:$DryRun -Force:$Force -InitBeads:$InitBeads -NoCommit:$NoCommit

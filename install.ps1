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
    [switch]$Force
)

if ($env:STARTERPACK_DRYRUN -eq "1") { $DryRun = [switch]::Present }
if (-not $Version) { $Version = "latest" }

$ErrorActionPreference = "Stop"

# PS 5.1 defaults to TLS 1.0 which GitHub rejects
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoOwner = "Jtonna"
$RepoName = "starterpack"
$VersionFile = ".starterpack-version"

# Files to copy from the release archive into the target project
$Manifest = @(
    "CLAUDE.md"
    "AGENTS.md"
    ".gitattributes"
    ".starterpack/workflows/WORKFLOW_ENTRY.xml"
    ".starterpack/workflows/MODELS.xml"
    ".starterpack/workflows/BEADS.xml"
    ".starterpack/workflows/WORKFLOW_PLANNING.xml"
    ".starterpack/workflows/WORKFLOW_IMPLEMENTATION.xml"
    ".starterpack/workflows/WORKFLOW_DOCS.xml"
    ".starterpack/workflows/WORKFLOW_PR.xml"
    ".starterpack/beads_sync.md"
    ".github/workflows/beads-sync.yml"
    ".github/scripts/beads-sync.sh"
    ".beads/.gitignore"
    ".claude/settings.local.json"
    ".starterpack/hooks/post-merge"
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
    $settingsPath = Join-Path $PWD ".claude" "settings.local.json"
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
    $hooksSourceDir = Join-Path $PWD ".starterpack" "hooks"
    $gitHooksDir = Join-Path $PWD ".git" "hooks"
    if ((Test-Path $hooksSourceDir) -and (Test-Path (Join-Path $PWD ".git"))) {
        foreach ($hookFile in (Get-ChildItem -Path $hooksSourceDir -File -ErrorAction SilentlyContinue)) {
            $destHook = Join-Path $gitHooksDir $hookFile.Name
            Copy-Item -Path $hookFile.FullName -Destination $destHook -Force
            Write-Host "  [ok] .git/hooks/$($hookFile.Name) (installed from .starterpack/hooks/)" -ForegroundColor Green
        }
    }

    # Step 9: Post-install checks
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

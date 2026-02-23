#Requires -Version 5.1
<#
.SYNOPSIS
    Create a new tagged release of the starterpack.

.DESCRIPTION
    Bumps the version, creates a git tag, pushes it, and creates a GitHub release.
    Must be run from the starterpack repo root on the main branch.

.PARAMETER BumpType
    Which semver component to bump: "major", "minor", or "patch".

.PARAMETER DryRun
    Preview the release without making any changes.

.EXAMPLE
    ./release.ps1 -BumpType patch
    ./release.ps1 -BumpType minor -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("major", "minor", "patch")]
    [string]$BumpType,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Verify we are in a git repo
if (-not (Test-Path ".git")) {
    throw "Not in a git repository root. Run this from the starterpack repo."
}

# Verify we are on main
$branch = (git rev-parse --abbrev-ref HEAD 2>&1)
if ($branch -ne "main") {
    throw "Must be on the main branch to release. Currently on: $branch"
}

# Verify working tree is clean
$status = (git status --porcelain 2>&1)
if ($status) {
    throw "Working tree is not clean. Commit or stash changes first."
}

# Get the latest version tag
$tags = git tag --list "v*" --sort=-version:refname 2>&1
$currentVersion = "v0.0.0"
if ($tags) {
    $latest = ($tags -split "`n" | Select-Object -First 1).Trim()
    if ($latest -match "^v\d+\.\d+\.\d+$") {
        $currentVersion = $latest
    }
}

# Parse and bump
$parts = $currentVersion.TrimStart("v").Split(".")
$major = [int]$parts[0]
$minor = [int]$parts[1]
$patch = [int]$parts[2]

switch ($BumpType) {
    "major" { $major++; $minor = 0; $patch = 0 }
    "minor" { $minor++; $patch = 0 }
    "patch" { $patch++ }
}

$newVersion = "v$major.$minor.$patch"

Write-Host ""
Write-Host "Current version: $currentVersion" -ForegroundColor Cyan
Write-Host "Bump type:       $BumpType" -ForegroundColor Cyan
Write-Host "New version:     $newVersion" -ForegroundColor Green
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] Would run:" -ForegroundColor Yellow
    Write-Host "  git tag $newVersion" -ForegroundColor Yellow
    Write-Host "  git push origin $newVersion" -ForegroundColor Yellow
    Write-Host "  gh release create $newVersion --title `"$newVersion`" --generate-notes" -ForegroundColor Yellow
    return
}

# Confirm
$confirm = Read-Host "Create release $newVersion? (y/n)"
if ($confirm -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    return
}

# Tag
Write-Host "Creating tag $newVersion..." -ForegroundColor Cyan
git tag $newVersion
if ($LASTEXITCODE -ne 0) { throw "Failed to create tag." }

# Push tag
Write-Host "Pushing tag..." -ForegroundColor Cyan
git push origin $newVersion
if ($LASTEXITCODE -ne 0) { throw "Failed to push tag." }

# Create GitHub release
if (Get-Command "gh" -ErrorAction SilentlyContinue) {
    Write-Host "Creating GitHub release..." -ForegroundColor Cyan
    gh release create $newVersion --title $newVersion --generate-notes
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: gh release create failed. Create manually at:" -ForegroundColor Yellow
        Write-Host "  https://github.com/Jtonna/starterpack/releases/new?tag=$newVersion" -ForegroundColor Yellow
    }
} else {
    Write-Host "gh CLI not found. Create the release manually at:" -ForegroundColor Yellow
    Write-Host "  https://github.com/Jtonna/starterpack/releases/new?tag=$newVersion" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Released $newVersion" -ForegroundColor Green

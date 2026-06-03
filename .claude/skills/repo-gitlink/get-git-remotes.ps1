# get-git-remotes.ps1
# Extracts git remote URLs from .claude/repo subdirectories
# Output: .claude/www/git.remote
# Default: append + auto-dedup (preserves history, skips URLs already in file)
# -Force:  reset the file before writing (no dedup needed)

param(
    [switch]$Force
)

$repoDir = Join-Path $PSScriptRoot "..\..\repo"
$outputFile = Join-Path $PSScriptRoot "..\..\www\git.remote"
$wwwDir = Join-Path $PSScriptRoot "..\..\www"

if (-not (Test-Path $wwwDir)) {
    New-Item -ItemType Directory -Path $wwwDir -Force | Out-Null
}

if (-not (Test-Path $repoDir)) {
    Write-Error "Repository directory not found: $repoDir"
    exit 1
}

if ($Force -and (Test-Path $outputFile)) {
    Remove-Item -Path $outputFile -Force
}

# Load existing URLs (for dedup in append mode)
$existing = @{}
if (-not $Force -and (Test-Path $outputFile)) {
    Get-Content -Path $outputFile |
        Where-Object { $_ -match '^(git@|https?://)' } |
        ForEach-Object { $existing[$_.Trim()] = $true }
}

$repos = Get-ChildItem -Path $repoDir -Directory
$added = 0
$deduped = 0
$noRemote = 0
$notGit = 0

foreach ($repo in $repos) {
    $gitDir = Join-Path $repo.FullName ".git"
    if (-not (Test-Path $gitDir)) {
        $notGit++
        continue
    }

    $prev = Get-Location
    Set-Location $repo.FullName
    $remoteUrl = git remote get-url origin 2>$null
    Set-Location $prev

    if (-not $remoteUrl) {
        Write-Warning "$($repo.Name): No remote 'origin' found"
        $noRemote++
        continue
    }

    $remoteUrl = $remoteUrl.Trim()

    if ($existing.ContainsKey($remoteUrl)) {
        $deduped++
        continue
    }

    Add-Content -Path $outputFile -Value $remoteUrl
    $existing[$remoteUrl] = $true
    $added++
}

Write-Host "Added: $added, Deduped: $deduped, NoRemote: $noRemote, NotGit: $notGit"
Write-Host "Output: $outputFile"

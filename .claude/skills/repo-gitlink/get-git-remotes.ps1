# get-git-remotes.ps1
# Extracts git remote URLs from .claude/repo subdirectories
# Output: .claude/www/git.remote

param(
    [switch]$Force
)

$repoDir = Join-Path $PSScriptRoot "..\..\repo"
$outputFile = Join-Path $PSScriptRoot "..\..\www\git.remote"
$wwwDir = Join-Path $PSScriptRoot "..\..\www"

if (-not (Test-Path $wwwDir)) {
    New-Item -ItemType Directory -Path $wwwDir -Force | Out-Null
}

if ($Force -and (Test-Path $outputFile)) {
    Remove-Item -Path $outputFile -Force
}
if (-not (Test-Path $outputFile)) {
    New-Item -ItemType File -Path $outputFile -Force | Out-Null
}

if (-not (Test-Path $repoDir)) {
    Write-Error "Repository directory not found: $repoDir"
    exit 1
}

$repos = Get-ChildItem -Path $repoDir -Directory
$found = 0
$skipped = 0

foreach ($repo in $repos) {
    $gitDir = Join-Path $repo.FullName ".git"
    if (Test-Path $gitDir) {
        $prev = Get-Location
        Set-Location $repo.FullName
        $remoteUrl = git remote get-url origin 2>$null
        Set-Location $prev

        if ($remoteUrl) {
            Add-Content -Path $outputFile -Value $remoteUrl
            $found++
        } else {
            Write-Warning "$($repo.Name): No remote 'origin' found"
            $skipped++
        }
    } else {
        $skipped++
    }
}

Write-Host "Done. Found: $found, Skipped: $skipped"
Write-Host "Output: $outputFile"

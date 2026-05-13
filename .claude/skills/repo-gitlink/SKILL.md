---
name: repo-gitlink
description: Use when team needs to extract or sync git remote URLs from .claude/repo subdirectories for collaboration tracking
---

# Repo Gitlink

## Overview
Extract git remote URLs from all repositories under `.claude/repo` and output to `.claude/www/git.remote`. One line per remote URL. Supports both PowerShell (Windows) and Bash (Linux/Mac).

## When to Use
- Team agents need to discover all repo remote URLs
- Onboarding new team member or agent
- Auditing which repos are tracked
- syncing gitlink-like metadata for collaboration

## Quick Reference

| Platform | Command |
|----------|---------|
| Windows | `powershell -ExecutionPolicy Bypass -File .claude/skills/repo-gitlink/get-git-remotes.ps1` |
| Linux/Mac | `bash .claude/skills/repo-gitlink/get-git-remotes.sh` |

## Input/Output Convention

```
Input:  .claude/repo/<repo-name>/.git  (one level deep only)
Output: .claude/www/git.remote
Format: One URL per line, no extra whitespace
```

## Implementation Scripts

### PowerShell (Windows)

```powershell
# get-git-remotes.ps1
$repoDir = Join-Path $PSScriptRoot "..\..\repo"
$outputFile = Join-Path $PSScriptRoot "..\..\www\git.remote"
$wwwDir = Join-Path $PSScriptRoot "..\..\www"

if (-not (Test-Path $wwwDir)) {
    New-Item -ItemType Directory -Path $wwwDir -Force | Out-Null
}

Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
New-Item -ItemType File -Path $outputFile -Force | Out-Null

foreach ($repo in Get-ChildItem -Path $repoDir -Directory) {
    $gitDir = Join-Path $repo.FullName ".git"
    if (Test-Path $gitDir) {
        Set-Location $repo.FullName
        $remoteUrl = git remote get-url origin 2>$null
        if ($remoteUrl) {
            Add-Content -Path $outputFile -Value $remoteUrl
        }
    }
}
```

### Bash (Linux/Mac)

```bash
#!/bin/bash
# get-git-remotes.sh
REPO_DIR="$(dirname "$(dirname "$0")")/repo"
OUTPUT_FILE="$(dirname "$(dirname "$0")")/www/git.remote"
mkdir -p "$(dirname "$OUTPUT_FILE")"

> "$OUTPUT_FILE"

for repo in "$REPO_DIR"/*/; do
    if [ -d "$repo/.git" ]; then
        cd "$repo"
        git remote get-url origin 2>/dev/null >> "$OUTPUT_FILE"
    fi
done
```

## Acceptance Criteria

| # | Criterion | Test Method |
|---|-----------|-------------|
| 1 | Output file created at `.claude/www/git.remote` | `Test-Path .claude/www/git.remote` |
| 2 | One URL per line, no empty lines between | `Get-Content` / `cat` |
| 3 | Only valid git URLs (ssh or https) | Regex: `^git@\|^https://` |
| 4 | All repos with .git folder included | Count repos vs output lines |
| 5 | No duplicate lines | `Sort-Object -Unique` / `sort -u` |
| 6 | Works on fresh clone (no prior www dir) | Delete www, run script, verify |
| 7 | Non-git directories silently skipped | repos without .git not in output |

## Common Mistakes

| Mistake | Prevention |
|---------|------------|
| Hardcoded paths | Use `$PSScriptRoot` / `dirname "$0"` relative to script |
| Appending to existing file | Always `Remove-Item` or `> "$OUTPUT_FILE"` first |
| Including non-git dirs | Explicitly check for `.git` folder |
| Empty output on failure | Verify `$remoteUrl` is not null/empty |

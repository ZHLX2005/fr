---
name: repo-gitlink
description: Use when team needs to extract or sync git remote URLs from .claude/repo subdirectories for collaboration tracking
---
# Repo Gitlink

## Overview

Extract git remote URLs from all repositories under `.claude/repo` and **append** to `.claude/www/git.remote`. One line per remote URL. Append-mode by design — preserves historical entries across runs. Use `-f`/`-Force` flag to start fresh. Supports both PowerShell (Windows) and Bash (Linux/Mac).

## When to Use

- Team agents need to discover all repo remote URLs
- Onboarding new team member or agent
- Auditing which repos are tracked
- syncing gitlink-like metadata for collaboration

## Quick Reference

| Platform          | Command                                                                                             | Mode      |
| ----------------- | --------------------------------------------------------------------------------------------------- | --------- |
| Windows           | `powershell -ExecutionPolicy Bypass -File .claude/skills/repo-gitlink/get-git-remotes.ps1`        | append    |
| Windows (reset)   | `powershell -ExecutionPolicy Bypass -File .claude/skills/repo-gitlink/get-git-remotes.ps1 -Force` | overwrite |
| Linux/Mac         | `bash .claude/skills/repo-gitlink/get-git-remotes.sh`                                             | append    |
| Linux/Mac (reset) | `bash .claude/skills/repo-gitlink/get-git-remotes.sh -f`                                          | overwrite |

## Input/Output Convention

```
Input:  .claude/repo/<repo-name>/.git  (one level deep only)
Output: .claude/www/git.remote (append by default)
Format: One URL per line, no extra whitespace
Mode:   append unless -f/-Force passed
```

## Implementation Scripts

### PowerShell (Windows)

```powershell
# get-git-remotes.ps1
param([switch]$Force)

$repoDir = Join-Path $PSScriptRoot "..\..\repo"
$outputFile = Join-Path $PSScriptRoot "..\..\www\git.remote"
$wwwDir = Join-Path $PSScriptRoot "..\..\www"

if (-not (Test-Path $wwwDir)) {
    New-Item -ItemType Directory -Path $wwwDir -Force | Out-Null
}

# Append by default; only reset when -Force passed
if ($Force -and (Test-Path $outputFile)) {
    Remove-Item -Path $outputFile -Force
}
if (-not (Test-Path $outputFile)) {
    New-Item -ItemType File -Path $outputFile -Force | Out-Null
}

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
FORCE=false
[ "$1" = "-f" ] || [ "$1" = "--force" ] && FORCE=true

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../repo"
OUTPUT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../www/git.remote"
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Append by default; only reset when -f/--force passed
if [ "$FORCE" = true ] && [ -f "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_FILE"
fi
touch "$OUTPUT_FILE"

for repo in "$REPO_DIR"/*/; do
    if [ -d "$repo/.git" ]; then
        cd "$repo"
        git remote get-url origin 2>/dev/null >> "$OUTPUT_FILE"
    fi
done
```

## Acceptance Criteria

| # | Criterion                                                       | Test Method                                  |
| - | --------------------------------------------------------------- | -------------------------------------------- |
| 1 | Output file created at `.claude/www/git.remote`               | `Test-Path .claude/www/git.remote`         |
| 2 | One URL per line, no empty lines between                        | `Get-Content` / `cat`                    |
| 3 | Only valid git URLs (ssh or https)                              | Regex:`^git@\|^https://`                    |
| 4 | All repos with .git folder appended on each run                 | Count repos vs new lines added               |
| 5 | Append-mode preserves history (duplicates expected across runs) | Compare line count before/after; should grow |
| 6 | `-f`/`-Force` flag resets file to fresh state               | Run with flag, line count == repo count      |
| 7 | Works on fresh clone (no prior www dir)                         | Delete www, run script, verify               |
| 8 | Non-git directories silently skipped                            | repos without .git not in output             |

## Common Mistakes


| Mistake                            | Prevention                                                                                                |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Hardcoded paths                    | Use `$PSScriptRoot` / `dirname "${BASH_SOURCE[0]}"` relative to script                                |
| Overwriting historical entries     | Default is append (`Add-Content` / `>>`); use `-Force`/`-f` only when intentional reset is needed |
| Including non-git dirs             | Explicitly check for `.git` folder                                                                      |
| Empty output on failure            | Verify `$remoteUrl` is not null/empty                                                                   |
| Unbounded growth of `git.remote` | Periodically reset with `-Force`/`-f`, or post-process with `sort -u` if dedup is needed downstream |

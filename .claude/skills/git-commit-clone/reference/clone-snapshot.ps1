# clone-snapshot.ps1 — 创建指定 commit 的项目快照（浅克隆 --depth=1）
# 用法: powershell -ExecutionPolicy Bypass -File clone-snapshot.ps1 [[-CommitHash] <string>]
#   默认使用当前 HEAD

param(
    [string]$CommitHash = "",
    [int]$KeepSnapshots = 10
)

$ErrorActionPreference = "Stop"

# ── 检测项目根目录 ──────────────────────────────
$ProjectRoot = git rev-parse --show-toplevel 2>$null
if (-not $ProjectRoot) {
    Write-Host "[git-commit-clone] ERROR: not in a git repository"
    exit 1
}

# ── 收集快照元数据 ──────────────────────────────
if (-not $CommitHash) {
    $CommitHash = git rev-parse --short HEAD
}
$CommitMsg = git log -1 --pretty=%s $CommitHash 2>$null
if (-not $CommitMsg) {
    Write-Host "[git-commit-clone] ERROR: commit ${CommitHash} not found"
    exit 1
}
$CommitMsg = [regex]::Replace($CommitMsg, '[^\w\s-]', '')
if ($CommitMsg.Length -gt 80) { $CommitMsg = $CommitMsg.Substring(0, 80) }

$Timestamp = Get-Date -Format "yyyy-MM-dd"
$SnapshotName = "${Timestamp}-${CommitHash}"
$SnapshotDir = Join-Path $ProjectRoot ".claude\repo\project\$SnapshotName"
$IndexDir = Join-Path $ProjectRoot ".claude\repo\project"

# ── 跳过重复 ────────────────────────────────────
$MetaFile = Join-Path $SnapshotDir ".snapshot-meta.json"
if (Test-Path $SnapshotDir) -and (Test-Path $MetaFile) {
    Write-Host "[git-commit-clone] Snapshot already exists: $SnapshotName, skip"
    exit 0
}

New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null

# ── 浅克隆 ──────────────────────────────────────
Write-Host "[git-commit-clone] Creating snapshot for commit ${CommitHash}: ${SnapshotName}"

# 切换到目标 commit 再克隆
$CurrentBranch = git rev-parse --abbrev-ref HEAD
git checkout --detach $CommitHash 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[git-commit-clone] ERROR: commit ${CommitHash} not found"
    if (Test-Path $SnapshotDir) { Remove-Item -Recurse -Force $SnapshotDir }
    exit 1
}

try {
    git clone --depth 1 "file:///${ProjectRoot}" $SnapshotDir 2>&1 | Out-Null
}
catch {
    Write-Host "[git-commit-clone] WARNING: shallow clone failed, retrying..."
    if (Test-Path $SnapshotDir) { Remove-Item -Recurse -Force $SnapshotDir }
    git clone --depth 1 "file:///${ProjectRoot}" $SnapshotDir 2>&1 | Out-Null
}

git checkout $CurrentBranch 2>&1 | Out-Null

# ── 写入快照元数据 ──────────────────────────────
$RemoteUrl = git remote get-url origin 2>$null
$MetaContent = @{
    id           = $CommitHash
    timestamp    = (Get-Date -Format "o")
    commit_short = $CommitHash
    commit_msg   = $CommitMsg
    remote_url   = $RemoteUrl
    path         = ".claude/repo/project/$SnapshotName"
}

$MetaContent | ConvertTo-Json | Set-Content -Path $MetaFile -Encoding UTF8

# ── 更新全局索引 ────────────────────────────────
$IndexFile = Join-Path $IndexDir "snapshots.json"
$LogFile = Join-Path $IndexDir "snapshots.log"

$LogEntry = "$(Get-Date -Format 'o') ${CommitHash} ${CommitMsg}"
Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8

# 重建完整索引
$SnapDirs = Get-ChildItem -Path $IndexDir -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}-' } | Sort-Object Name -Descending
$Index = @()
foreach ($dir in $SnapDirs) {
    $metaFile = Join-Path $dir.FullName ".snapshot-meta.json"
    if (Test-Path $metaFile) {
        $meta = Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $Index += $meta
    }
}
$Index | ConvertTo-Json -Depth 10 | Set-Content -Path $IndexFile -Encoding UTF8

Write-Host "[git-commit-clone] Snapshot saved: $SnapshotDir"

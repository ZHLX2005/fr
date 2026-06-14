#!/bin/bash
# clone-snapshot.sh — 创建指定 commit 的项目快照（浅克隆 --depth=1）
# 用法: bash clone-snapshot.sh [commit-hash]
#   commit-hash: 可选，默认为当前 HEAD
#
# 示例:
#   bash clone-snapshot.sh                    # 为当前 HEAD 创建快照
#   bash clone-snapshot.sh a1b2c3d            # 为指定 commit 创建快照

set -euo pipefail

# ── 配置 ──────────────────────────────────────────
KEEP_SNAPSHOTS=10          # 默认保留数量 (手动清理时生效)

# ── 检测项目根目录 ──────────────────────────────
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "[git-commit-clone] ERROR: not in a git repository"
    exit 1
}

# ── 收集快照元数据 ──────────────────────────────
COMMIT_HASH="${1:-$(git rev-parse --short HEAD)}"
COMMIT_MSG=$(git log -1 --pretty=%s "${COMMIT_HASH}" 2>/dev/null | tr -dc '[:alnum:]-_/ ' | head -c 80 | sed 's/[\/]/_/g')
TIMESTAMP=$(date +%Y-%m-%d)
SNAPSHOT_NAME="${TIMESTAMP}-${COMMIT_HASH}"
SNAPSHOT_DIR="${PROJECT_ROOT}/.claude/repo/project/${SNAPSHOT_NAME}"
INDEX_DIR="${PROJECT_ROOT}/.claude/repo/project"

# ── 跳过重复 ────────────────────────────────────
if [ -d "$SNAPSHOT_DIR" ] && [ -f "${SNAPSHOT_DIR}/.snapshot-meta.json" ]; then
    echo "[git-commit-clone] Snapshot already exists: ${SNAPSHOT_NAME}, skip"
    exit 0
fi

mkdir -p "$SNAPSHOT_DIR"

# ── 浅克隆 ──────────────────────────────────────
echo "[git-commit-clone] Creating snapshot for commit ${COMMIT_HASH}: ${SNAPSHOT_NAME}"

# 先切换到目标 commit 再克隆
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git checkout --detach "${COMMIT_HASH}" 2>/dev/null || {
    echo "[git-commit-clone] ERROR: commit ${COMMIT_HASH} not found"
    rm -rf "$SNAPSHOT_DIR"
    exit 1
}
git clone --depth 1 "file://${PROJECT_ROOT}" "$SNAPSHOT_DIR" 2>/dev/null || {
    echo "[git-commit-clone] WARNING: shallow clone failed, retrying..."
    rm -rf "$SNAPSHOT_DIR"
    git clone --depth 1 "file://${PROJECT_ROOT}" "$SNAPSHOT_DIR"
}
git checkout "$CURRENT_BRANCH" 2>/dev/null || true

# ── 写入快照元数据 ──────────────────────────────
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
FULL_COMMIT_MSG=$(git log -1 --pretty=%s "${COMMIT_HASH}" 2>/dev/null | head -c 200)
cat > "${SNAPSHOT_DIR}/.snapshot-meta.json" << EOF
{
  "id": "${COMMIT_HASH}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit_short": "${COMMIT_HASH}",
  "commit_msg": "${FULL_COMMIT_MSG}",
  "remote_url": "${REMOTE_URL}",
  "path": ".claude/repo/project/${SNAPSHOT_NAME}"
}
EOF

# ── rebuild_snapshots_json: 聚合所有 .snapshot-meta.json 到 snapshots.json ──
rebuild_snapshots_json() {
    local dir="$1"
    local metas
    metas=$(find "$dir" -maxdepth 2 -name '.snapshot-meta.json' 2>/dev/null | sort -r)
    echo '[' > "${dir}/snapshots.json"
    local first=true
    while IFS= read -r meta; do
        if [ -f "$meta" ]; then
            if [ "$first" = true ]; then
                first=false
            else
                echo ',' >> "${dir}/snapshots.json"
            fi
            cat "$meta" >> "${dir}/snapshots.json"
        fi
    done <<< "$metas"
    echo '' >> "${dir}/snapshots.json"
    echo ']' >> "${dir}/snapshots.json"
}

# ── 更新全局索引 ────────────────────────────────
rebuild_snapshots_json "$INDEX_DIR"

# 确保 snapshots.json 至少有一个空数组（无快照时）
if ! [ -s "${INDEX_DIR}/snapshots.json" ]; then
    echo '[]' > "${INDEX_DIR}/snapshots.json"
fi

echo "[git-commit-clone] Snapshot saved: ${SNAPSHOT_DIR}"

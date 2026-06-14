#!/bin/bash
# prune-snapshots.sh — 清理旧快照，保留最近 N 个
# 用法: bash prune-snapshots.sh [保留数量] [项目根路径]

set -euo pipefail

KEEP=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ge 2 ]; then
    PROJECT_ROOT="$2"
else
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

INDEX_DIR="${PROJECT_ROOT}/.claude/repo/project"

if [ ! -d "$INDEX_DIR" ]; then
    echo "[git-commit-clone] No snapshots directory found at ${INDEX_DIR}"
    exit 0
fi

# ── 统计快照 ────────────────────────────────────
SNAPSHOTS=$(ls -1d "${INDEX_DIR}/"*-* 2>/dev/null | sort || true)
TOTAL=$(echo "$SNAPSHOTS" | wc -l)

echo "[git-commit-clone] Snapshots: ${TOTAL} total, keeping ${KEEP}"

if [ "$TOTAL" -le "$KEEP" ]; then
    echo "[git-commit-clone] Nothing to prune"
    exit 0
fi

TO_DELETE=$((TOTAL - KEEP))

echo "[git-commit-clone] Deleting ${TO_DELETE} old snapshot(s):"
for snap in $(echo "$SNAPSHOTS" | head -n "$TO_DELETE"); do
    SNAP_NAME=$(basename "$snap")
    echo "  - ${SNAP_NAME}"
    rm -rf "$snap"
done

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

# ── 重建 snapshots.json ────────────────────────
rebuild_snapshots_json "$INDEX_DIR"

echo "[git-commit-clone] ✓ Prune complete. ${KEEP} snapshots retained"

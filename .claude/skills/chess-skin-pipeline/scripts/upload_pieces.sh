#!/usr/bin/env bash
# upload_pieces.sh —— 上传一套国际象棋皮肤的 12 张棋子 webp 到 File API，输出 file_id 映射 JSON。
#
# 用法：
#   bash upload_pieces.sh <图片目录> <skinId>
#   例：bash upload_pieces.sh D:/skins/neo neo
#
# 前置：kvcli 已登录（token 从 ~/.kvcli/config.json 读）。
# 输出：stdout 打印 { "<skinId>": { "wK": "<fileId>", ... 12 项 } }（建议 tee 存档）。
# 失败：任一张上传失败 → 非零退出并列出失败项；重跑即可（File 每次生成新 file_id）。
#
# 契约（实测，勿改）：
#   POST /api/v1/files  multipart field 必须叫 "file"（不是 /api/v1/upload —— 那个 404）
#   accessLevel=public  key=chess/<skinId>/<pieceKey>

set -u

DIR="${1:-}"
SKIN_ID="${2:-}"
BASE="${CHESS_SKIN_BASE_URL:-http://47.110.80.47:8988}"
CFG="${HOME}/.kvcli/config.json"
# Windows Python 不认 /c/... POSIX 路径 → cygpath 转 Windows 路径（非 cygwin 环境原样）
CFG_WIN=$(cygpath -w "$CFG" 2>/dev/null || echo "$CFG")

if [ -z "$DIR" ] || [ -z "$SKIN_ID" ]; then
  echo "用法: bash upload_pieces.sh <图片目录> <skinId>" >&2
  exit 2
fi
if [ ! -d "$DIR" ]; then
  echo "ERROR: dir not found $DIR" >&2
  exit 2
fi
if [ ! -f "$CFG" ] && [ ! -f "$CFG_WIN" ]; then
  echo "ERROR: $CFG not found - run kvcli auth login first" >&2
  exit 2
fi
TOKEN=$(python -c "import json;print(json.load(open(r'$CFG_WIN'))['token'])" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "ERROR: read token failed" >&2
  exit 2
fi

# 文件名（去扩展名）→ piece key
declare -A PIECE_MAP=(
  ['00_white_king']='wK'   ['01_white_queen']='wQ' ['02_white_rook']='wR'
  ['03_white_bishop']='wB' ['04_white_knight']='wN' ['05_white_pawn']='wp'
  ['06_black_king']='bK'   ['07_black_queen']='bQ'  ['08_black_rook']='bR'
  ['09_black_bishop']='bB' ['10_black_knight']='bN' ['11_black_pawn']='bp'
)
ORDER=(wK wQ wR wB wN wp bK bQ bR bB bN bp)

declare -A FID
FAIL=0

for base_name in "${!PIECE_MAP[@]}"; do
  key="${PIECE_MAP[$base_name]}"
  f=""
  for ext in webp png; do
    [ -f "$DIR/$base_name.$ext" ] && f="$DIR/$base_name.$ext" && break
  done
  if [ -z "$f" ]; then
    echo "ERROR: missing $DIR/$base_name.webp" >&2
    FAIL=1
    continue
  fi
  resp=$(curl -s -X POST "$BASE/api/v1/files" \
    -H "Authorization: Bearer $TOKEN" \
    -F "file=@$f" \
    -F "accessLevel=public" \
    -F "key=chess/$SKIN_ID/$key" 2>&1)
  fid=$(echo "$resp" | grep -oP '"fileId":"[a-f0-9]{32}"' | head -1 | cut -d'"' -f4)
  if [ -n "$fid" ]; then
    FID[$key]="$fid"
    echo "  ok $key <- $(basename "$f") $fid" >&2
  else
    echo "  FAIL $key: $(echo "$resp" | head -c 200)" >&2
    FAIL=1
  fi
done

# 输出 JSON（stdout）
out="{\"$SKIN_ID\":{"
first=1
for key in "${ORDER[@]}"; do
  fid="${FID[$key]:-}"
  if [ -n "$fid" ]; then
    [ $first -eq 0 ] && out+=","
    out+="\"$key\":\"$fid\""
    first=0
  fi
done
out+="}}"
echo "$out"

[ $FAIL -eq 0 ] || { echo "some uploads failed - rerun" >&2; exit 1; }

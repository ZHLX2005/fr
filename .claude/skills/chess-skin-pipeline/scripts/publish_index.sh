#!/usr/bin/env bash
# publish_index.sh —— 把一份（或一组）皮肤 meta JSON 合并发布到 KV public（chess_skin:index）。
#
# 用法：
#   bash publish_index.sh <meta.json> [更多meta.json...]
#   例：bash publish_index.sh neo_meta.json
#
# 行为：
#   1. 登录态拉旧 index（GET /api/v1/kv/chess_skin:index?groupId=190）
#   2. 与输入 meta 按 id 合并去重（输入覆盖旧值）
#   3. 校验：id 唯一 / id 格式 / pieces 严格 12 key / fileId 32-hex
#   4. POST /api/v1/kv 写回（visibility=public, groupId=190）
#   5. 匿名读回验证（GET /api/v1/kv/public/...）
#
# 输入 meta.json：单个对象（一套皮肤）或 JSON array（多套）。

set -u

BASE="${CHESS_SKIN_BASE_URL:-http://47.110.80.47:8988}"
GROUP="${CHESS_SKIN_GROUP:-190}"
KEY="chess_skin:index"
CFG="${HOME}/.kvcli/config.json"
# Windows Python 不认 /c/... POSIX 路径 → cygpath 转 Windows 路径
CFG_WIN=$(cygpath -w "$CFG" 2>/dev/null || echo "$CFG")

if [ $# -lt 1 ]; then
  echo "用法: bash publish_index.sh <meta.json> [更多...]" >&2
  exit 2
fi
if [ ! -f "$CFG" ] && [ ! -f "$CFG_WIN" ]; then
  echo "错误: 未找到 $CFG —— 先 kvcli auth login" >&2
  exit 2
fi
TOKEN=$(python -c "import json;print(json.load(open(r'$CFG_WIN'))['token'])" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "错误: 读取 token 失败" >&2
  exit 2
fi

# 输入文件路径同样转 Windows 形式（Windows Python open 需要）
ARGS=()
for p in "$@"; do
  ARGS+=("$(cygpath -w "$p" 2>/dev/null || echo "$p")")
done

python - "${ARGS[@]}" <<PYEOF
import json, sys, urllib.request

BASE = "$BASE"
GROUP = $GROUP
KEY = "$KEY"
TOKEN = "$TOKEN"
PIECE_KEYS = {"wK","wQ","wR","wB","wN","wp","bK","bQ","bR","bB","bN","bp"}
import re
ID_RE = re.compile(r'^[a-z0-9][a-z0-9-]{0,31}$')
HEX32 = re.compile(r'^[a-f0-9]{32}$')

def http(method, path, body=None, auth=True):
    url = f"{BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if auth:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {}
    except Exception as e:
        return 0, {"err": str(e)}

# 1) 拉旧 index
status, old = http("GET", f"/api/v1/kv/{KEY}?groupId={GROUP}")
merged = {}
if status == 200 and old.get("code") == 0 and old.get("data"):
    try:
        for m in json.loads(old["data"]["value"]):
            merged[m["id"]] = m
        print(f"old index: {len(merged)} skins", file=sys.stderr)
    except Exception as e:
        print(f"WARN: old index parse failed (ignored): {e}", file=sys.stderr)
else:
    print("old index missing -> fresh publish", file=sys.stderr)

# 2) 合并输入
for path in sys.argv[1:]:
    raw = json.load(open(path, encoding="utf-8"))
    items = raw if isinstance(raw, list) else [raw]
    for m in items:
        mid = m.get("id", "")
        if not ID_RE.match(mid):
            print(f"ERROR: {path} bad id: {mid!r}", file=sys.stderr); sys.exit(1)
        pieces = m.get("pieces", {})
        if set(pieces.keys()) != PIECE_KEYS:
            print(f"ERROR: {mid} pieces must be exactly 12 keys, got {sorted(pieces.keys())}", file=sys.stderr); sys.exit(1)
        for pk, ref in pieces.items():
            fid = ref.get("fileId", "")
            if not HEX32.match(fid):
                print(f"ERROR: {mid}/{pk} fileId not 32-hex: {fid!r}", file=sys.stderr); sys.exit(1)
        merged[mid] = m
        print(f"  merged {mid} (v{m.get('version',1)})", file=sys.stderr)

final = list(merged.values())
value = json.dumps(final, ensure_ascii=False)

# 3) 写回
status, w = http("POST", "/api/v1/kv", {
    "key": KEY, "value": value, "visibility": "public", "groupId": GROUP,
})
if not (status == 200 and w.get("code") == 0):
    print(f"ERROR: write failed: {status} {w}", file=sys.stderr); sys.exit(1)
print(f"published {len(final)} skins -> {KEY} (public, group {GROUP})", file=sys.stderr)

# 4) 匿名读回验证
status, v = http("GET", f"/api/v1/kv/public/{KEY}?groupId={GROUP}", auth=False)
if status == 200 and v.get("code") == 0:
    got = json.loads(v["data"]["value"])
    print(f"anon read-back OK: {len(got)} skins", file=sys.stderr)
else:
    print(f"WARN: anon read-back failed (client falls back to local): {status} {str(v)[:200]}", file=sys.stderr); sys.exit(1)
PYEOF

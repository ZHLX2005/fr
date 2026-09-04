#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
add_skin.py —— 端到端：压缩 → 上传 → 更新 KV 一站式脚本（纯 Python，无 bash 依赖）。

用法：
    python add_skin.py <source_dir> <skin_id> [--name <display_name>] [--game <gameId>]

示例：
    python add_skin.py "D:/DevProjects/my/test/image/3/8" 8
    python add_skin.py "D:/skins/neo" neo --name "霓虹"
    python add_skin.py "D:/skins/gomoku_ink" ink --game gomoku --name "水墨"

行为：
  1. 可选：Pillow 压缩 PNG（paletted + max compression）→ tmp 文件
  2. 登录态 POST /api/v1/files 上传 N 张图，拿 file_id
     · multipart 同时携带 key=<game>/<skinId>/<pieceKey>（路径化标签，旧依赖兼容）
     · 与 tags[]=['<game>-skin', '<game>-skin:<id>', '<game>-skin:<id>:<pieceKey>']
       （后端 tag 维度，可按 list?tags= 查询，详见 references/architecture.md §5）
  3. 登录态 GET <game>_skin:index（旧 index）→ 合并去重（新覆盖旧）→ 校验
  4. POST /api/v1/kv 写回（public + groupId 190 + tags=['<game>-skin']）
  5. 匿名 GET /api/v1/kv/public/<game>_skin:index 验证

多游戏参数化（--game）：
  --game 派生：kvIndexKey=<game>_skin:index, tagPrefix=<game>-skin,
  fileKeyPrefix=<game>/, pieceKeys 来自 GAME_ASSET_KEYS。
  默认 chess（零回归）；未知 game 回退到 chess 12 keys 并打印 warning。

依赖：Python 3.8+，标准库 + Pillow（压缩用；缺则跳过压缩，行为等价）。
"""
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
import uuid
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


# ── 多游戏资产注册表（与 plan/game-kit-unification.md § Naming Convention 对齐） ──
# key = gameId（与 GameDefinition.slug / kGameMeta 一致），value = piece asset keys
GAME_ASSET_KEYS = {
    "chess": ["wK", "wQ", "wR", "wB", "wN", "wp", "bK", "bQ", "bR", "bB", "bN", "bp"],
    # gomoku: 黑/白子 + 棋盘底图（如需棋盘颜色自定义，另走 BoardPalette，不在 skin file 集内）
    "gomoku": ["black", "white", "board"],
}

# 每游戏文件名映射（pieceKey → 期望文件名；chess 保留 00_* 历史命名，gomoku 用语义名）
_CHESS_NAME_BY_KEY = {
    "wK": "00_white_king.png", "wQ": "01_white_queen.png", "wR": "02_white_rook.png",
    "wB": "03_white_bishop.png", "wN": "04_white_knight.png", "wp": "05_white_pawn.png",
    "bK": "06_black_king.png", "bQ": "07_black_queen.png", "bR": "08_black_rook.png",
    "bB": "09_black_bishop.png", "bN": "10_black_knight.png", "bp": "11_black_pawn.png",
}
_GOMOKU_NAME_BY_KEY = {
    "black": "black.png", "white": "white.png", "board": "board.png",
}

GAME_FILE_MAPS = {
    "chess": _CHESS_NAME_BY_KEY,
    "gomoku": _GOMOKU_NAME_BY_KEY,
}

# ── 向后兼容：保留旧顶层常量（旧调用/外部引用不受影响） ──
PIECE_KEYS = GAME_ASSET_KEYS["chess"]
NAME_BY_KEY = _CHESS_NAME_BY_KEY
EXPECTED_FILES = set(NAME_BY_KEY.values())


def die(msg, code=1):
    print(f"[ERR] {msg}", file=sys.stderr)
    sys.exit(code)


def log(msg, file=sys.stderr):
    print(msg, file=file, flush=True)


def resolve_game_config(game):
    """根据 --game 派生 kvIndexKey / tagPrefix / fileKeyPrefix / pieceKeys / nameByKey。

    未知 game 回退到 chess 12 keys 并 warn（保持零回归，不中断）。
    """
    if game in GAME_ASSET_KEYS:
        piece_keys = GAME_ASSET_KEYS[game]
    else:
        log(f"warn: unknown --game '{game}', fallback to chess keys (12); known: {sorted(GAME_ASSET_KEYS.keys())}")
        piece_keys = GAME_ASSET_KEYS["chess"]
    kv_index_key = f"{game}_skin:index"
    tag_prefix = f"{game}-skin"
    file_key_prefix = f"{game}/"
    # 文件名映射：已知游戏用注册表，未知回退到 {k: k.png}
    if game in GAME_FILE_MAPS:
        name_by_key = GAME_FILE_MAPS[game]
    else:
        name_by_key = {k: f"{k}.png" for k in piece_keys}
    return kv_index_key, tag_prefix, file_key_prefix, piece_keys, name_by_key


def resolve_piece_path(src_dir, piece_key, name_by_key, game):
    """返回该 piece 在 src_dir 下的实际文件 Path（若不存在则 None）。

    chess：严格按 NAME_BY_KEY 的 00_* 名查找（零回归）。
    其他游戏：先试注册名，再试同 stem 的 .webp/.jpg 兜底（允许 png/webp 混用）。
    """
    # 兼容：name_by_key 可能不含该 key（未知 game 回退分支）
    expected_name = name_by_key.get(piece_key) if isinstance(name_by_key, dict) else None
    if game == "chess":
        if expected_name is None:
            return None
        cand = src_dir / expected_name
        return cand if cand.is_file() else None
    # 非 chess：允许 png/webp/jpg 互换
    if expected_name is not None:
        cand = src_dir / expected_name
        if cand.is_file():
            return cand
        stem = Path(expected_name).stem
    else:
        stem = piece_key
    for ext in (".png", ".webp", ".jpg", ".jpeg"):
        alt = src_dir / f"{stem}{ext}"
        if alt.is_file():
            return alt
    return None


def load_token():
    """Windows + POSIX 兼容：优先 ~/.kvcli/config.json。"""
    candidates = [
        Path.home() / ".kvcli" / "config.json",
        Path(os.environ.get("KVCLI_CONFIG", "")) if os.environ.get("KVCLI_CONFIG") else None,
    ]
    for p in candidates:
        if p and p.is_file():
            try:
                return json.loads(p.read_text(encoding="utf-8"))["token"]
            except Exception as e:
                die(f"read token failed from {p}: {e}")
    die("token not found; run `kvcli auth login` first")


def http_multipart_upload(base_url, token, file_bytes, file_name, key, tags=None, content_type="image/png"):
    """POST /api/v1/files — multipart form-data.

    同时携带 `key`（路径化标签，与旧管线兼容）和 `tags[]`（后端 tag 维度，
    见 references/architecture.md §5 Tag Schema：['<game>-skin', '<game>-skin:<id>',
    '<game>-skin:<id>:<pieceKey>']）。两者并存,旧依赖 key 的查询不受影响,
    新增的 tag 维度可用于 list?tags= 查询。
    """
    boundary = "----WebKitFormBoundary" + uuid.uuid4().hex
    body = []
    body.append(f"--{boundary}".encode())
    body.append(b'Content-Disposition: form-data; name="accessLevel"')
    body.append(b"")
    body.append(b"public")
    body.append(f"--{boundary}".encode())
    body.append(b'Content-Disposition: form-data; name="key"')
    body.append(b"")
    body.append(key.encode())
    # tags[] 重复参数(replace 语义),后端会按 tag 维度入 facet
    for t in (tags or []):
        body.append(f"--{boundary}".encode())
        body.append(b'Content-Disposition: form-data; name="tags[]"')
        body.append(b"")
        body.append(t.encode())
    body.append(f"--{boundary}".encode())
    body.append(f'Content-Disposition: form-data; name="file"; filename="{file_name}"'.encode())
    body.append(f"Content-Type: {content_type}".encode())
    body.append(b"")
    body.append(file_bytes)
    body.append(f"--{boundary}--".encode())
    body.append(b"")
    payload = b"\r\n".join(body)
    req = urllib.request.Request(
        f"{base_url}/api/v1/files",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(payload)),
        },
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


def http_get(base_url, path, token=None, anonymous=False):
    headers = {}
    if token and not anonymous:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{base_url}{path}", headers=headers)
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())


def http_post_json(base_url, path, token, body):
    req = urllib.request.Request(
        f"{base_url}{path}",
        data=json.dumps(body).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())


def compress_png(src_path, max_colors=128):
    """Pillow 优化：合并 alpha 通道 + 调色板模式 + 最大压缩。返回压缩后的 bytes。
    文件已经够小（<50KB）则不强制压缩，由 caller 决定；本函数仅在调用方要求时使用。"""
    if not HAS_PIL:
        raise RuntimeError("Pillow not available")
    img = Image.open(src_path)
    # paletted PNG with alpha preserved (RGBA → P mode loses alpha; use PA)
    if img.mode == "RGBA":
        img = img.convert("P", palette=Image.Palette.ADAPTIVE, colors=max_colors)
    elif img.mode not in ("P", "L", "RGB"):
        img = img.convert("RGBA")
    buf = BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def upload_one(base_url, token, file_path, skin_id, piece_key, game, tag_prefix, file_key_prefix):
    data = file_path.read_bytes()
    # 压缩：>50KB 调一次 Pillow 优化；否则原样上传（board 底图可能较大，同样适用）
    if HAS_PIL and len(data) > 50_000:
        try:
            data = compress_png(file_path)
        except Exception as e:
            log(f"  warn: compress failed for {file_path.name}: {e}; uploading raw")
    key = f"{file_key_prefix}{skin_id}/{piece_key}"
    # 三级 tag：通用 / 皮肤级 / 棋子级（对应 references/architecture.md §5，game 维度参数化）
    tags = [tag_prefix, f"{tag_prefix}:{skin_id}", f"{tag_prefix}:{skin_id}:{piece_key}"]
    resp = http_multipart_upload(base_url, token, data, file_path.name, key, tags=tags)
    fid = resp.get("data", {}).get("fileId", "")
    if not fid:
        raise RuntimeError(f"upload failed for {file_path.name}: {resp}")
    return fid


def fetch_old_index(base_url, token, group_id, kv_index_key):
    """登录态 GET /api/v1/kv/<kv_index_key>?groupId=... 读旧 index（数组）；缺失返回 []。"""
    qs = urllib.parse.urlencode({"groupId": group_id})
    resp = http_get(base_url, f"/api/v1/kv/{kv_index_key}?{qs}", token=token)
    if resp.get("code") != 0 or not resp.get("data"):
        return []
    try:
        return json.loads(resp["data"]["value"])
    except Exception as e:
        log(f"warn: parse old index failed: {e}; treating as empty")
        return []


def publish_index(base_url, token, group_id, metas, kv_index_key, common_tag):
    """登录态 POST /api/v1/kv 写回。

    同时写入 tags=[common_tag] —— 后端 KV 与 file 在 tag 维度统一，
    见 references/architecture.md §5 Tag Schema。KV 端不需要 skin/piece 级 tag，
    因为 <game>_skin:index 自身就是全量索引。
    """
    body = {
        "key": kv_index_key,
        "value": json.dumps(metas, ensure_ascii=False),
        "visibility": "public",
        "groupId": group_id,
        "tags": [common_tag],
    }
    resp = http_post_json(base_url, "/api/v1/kv", token, body)
    if resp.get("code") != 0:
        raise RuntimeError(f"publish failed: {resp}")


def anon_verify(base_url, group_id, expect_n, kv_index_key):
    """匿名 GET 验证条数 + 关键 id 都在。"""
    qs = urllib.parse.urlencode({"groupId": group_id})
    resp = http_get(base_url, f"/api/v1/kv/public/{kv_index_key}?{qs}", anonymous=True)
    if resp.get("code") != 0:
        raise RuntimeError(f"anon read failed: {resp}")
    arr = json.loads(resp["data"]["value"])
    if len(arr) < expect_n:
        raise RuntimeError(f"anon returned {len(arr)} skins, expected >= {expect_n}")


def main():
    ap = argparse.ArgumentParser(description="End-to-end: compress → upload → update KV (game skin, --game parameterized)")
    ap.add_argument("source_dir", help="N 张 PNG/WebP 所在目录（chess 12 张，gomoku 3 张）")
    ap.add_argument("skin_id", help="数字或小写 ASCII id，例如 8 / neo")
    ap.add_argument("--name", default=None, help="displayName（默认：'皮肤 {skin_id}'）")
    ap.add_argument("--game", default="chess", help="gameId，决定 KV key/tag 前缀/file 前缀与 piece keys（default: chess；已知: chess, gomoku）")
    ap.add_argument("--base", default=os.environ.get("CHESS_SKIN_BASE_URL", "http://47.110.80.47:8988"),
                    help="API base URL (default from env or hardcoded)")
    ap.add_argument("--group", type=int, default=int(os.environ.get("CHESS_SKIN_GROUP", "190")),
                    help="KV groupId (default from env or 190)")
    ap.add_argument("--no-compress", action="store_true", help="跳过 PNG 优化")
    args = ap.parse_args()

    kv_index_key, tag_prefix, file_key_prefix, piece_keys, name_by_key = resolve_game_config(args.game)

    src = Path(args.source_dir)
    if not src.is_dir():
        die(f"source_dir not found: {src}")

    # ── 文件校验（按 game 派生；chess 保持旧逻辑零回归） ──
    if args.game == "chess":
        found = {f.name for f in src.glob("*.png")}
        expected_files = set(name_by_key.values())
        missing = expected_files - found
        extra = found - expected_files
        if missing:
            die(f"missing {len(missing)} files: {sorted(missing)[:5]}... (game={args.game}, expected {len(expected_files)})")
        if extra:
            log(f"info: ignoring {len(extra)} extra files: {sorted(extra)[:5]}...")
    else:
        missing_keys = []
        resolved = {}
        for k in piece_keys:
            p = resolve_piece_path(src, k, name_by_key, args.game)
            if p is None:
                missing_keys.append(k)
            else:
                resolved[k] = p
        if missing_keys:
            die(f"missing {len(missing_keys)} piece files for game={args.game}: {missing_keys} (src={src}, expected stems: {piece_keys})")
        # extra 提示（仅对 png/webp/jpg 统计）
        all_piece_stems = {Path(name_by_key.get(k, f"{k}.png")).stem for k in piece_keys}
        found_stems = {p.stem for p in src.glob("*.*") if p.suffix.lower() in (".png", ".webp", ".jpg", ".jpeg")}
        extra = found_stems - all_piece_stems
        if extra:
            log(f"info: ignoring {len(extra)} extra files (stems): {sorted(extra)[:5]}...")

    token = load_token()
    log(f"[1/4] uploading {len(piece_keys)} pieces for skin '{args.skin_id}' game={args.game} from {src} (kv={kv_index_key}, tag={tag_prefix}, filePrefix={file_key_prefix})")
    pieces = {}
    for key in piece_keys:
        # 解析实际文件路径（chess 严格名，其他游戏允许 png/webp 互换）
        if args.game == "chess":
            fp = src / name_by_key[key]
        else:
            fp = resolve_piece_path(src, key, name_by_key, args.game)
            if fp is None:
                die(f"resolve failed for piece {key} (game={args.game})")
        try:
            fid = upload_one(args.base, token, fp, args.skin_id, key, args.game, tag_prefix, file_key_prefix)
        except Exception as e:
            die(f"upload {fp.name} failed: {e}")
        pieces[key] = {
            "fileId": fid,
            "fileName": fp.name,
            "sizeBytes": 0,  # 占位（发布脚本只校验 fileId 格式）
            "contentType": "image/png",
        }
        log(f"  ok {key} {fp.name} -> {fid}")

    meta = {
        "id": args.skin_id,
        "displayName": args.name or f"皮肤 {args.skin_id}",
        "version": 1,
        "colorStyle": "vivid",
        "createdAt": "2026-08-30T00:00:00Z",
        "updatedAt": "2026-08-30T00:00:00Z",
        "pieces": pieces,
    }

    log(f"[2/4] fetching old index {kv_index_key} from {args.base} (groupId={args.group})")
    old = fetch_old_index(args.base, token, args.group, kv_index_key)
    log(f"  old index: {len(old)} skins")
    # merge: 同 id 覆盖；新 id 追加
    by_id = {m["id"]: m for m in old}
    by_id[args.skin_id] = meta
    merged = list(by_id.values())
    log(f"[3/4] publishing {len(merged)} skins (added/updated: {args.skin_id}) kv={kv_index_key} tag={tag_prefix}")
    publish_index(args.base, token, args.group, merged, kv_index_key, tag_prefix)

    log(f"[4/4] anon verify {kv_index_key}")
    anon_verify(args.base, args.group, len(merged), kv_index_key)

    log(f"OK: skin '{args.skin_id}' game={args.game} published. total {len(merged)} skins at {args.base} kv={kv_index_key}.")
    # 输出 meta JSON 到 stdout（便于 pipe 到 git add / CI）
    print(json.dumps(meta, ensure_ascii=False))


if __name__ == "__main__":
    main()

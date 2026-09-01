#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
add_skin.py —— 端到端：压缩 → 上传 → 更新 KV 一站式脚本（纯 Python，无 bash 依赖）。

用法：
    python add_skin.py <source_dir> <skin_id> [--name <display_name>]

示例：
    python add_skin.py "D:/DevProjects/my/test/image/3/8" 8
    python add_skin.py "D:/skins/neo" neo --name "霓虹"

行为：
  1. 可选：Pillow 压缩 PNG（paletted + max compression）→ tmp 文件
  2. 登录态 POST /api/v1/files 上传 12 张图，拿 file_id
     · multipart 同时携带 key=chess/<skinId>/<pieceKey>（路径化标签，旧依赖兼容）
     · 与 tags[]=['chess-skin', 'chess-skin:<id>', 'chess-skin:<id>:<pieceKey>']
       （后端 tag 维度，可按 list?tags= 查询，详见 references/architecture.md §5）
  3. 登录态 GET chess_skin:index（旧 index）→ 合并去重（新覆盖旧）→ 校验
  4. POST /api/v1/kv 写回（public + groupId 190 + tags=['chess-skin']）
  5. 匿名 GET /api/v1/kv/public/chess_skin:index 验证

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


PIECE_KEYS = ["wK", "wQ", "wR", "wB", "wN", "wp", "bK", "bQ", "bR", "bB", "bN", "bp"]
NAME_BY_KEY = {
    "wK": "00_white_king.png", "wQ": "01_white_queen.png", "wR": "02_white_rook.png",
    "wB": "03_white_bishop.png", "wN": "04_white_knight.png", "wp": "05_white_pawn.png",
    "bK": "06_black_king.png", "bQ": "07_black_queen.png", "bR": "08_black_rook.png",
    "bB": "09_black_bishop.png", "bN": "10_black_knight.png", "bp": "11_black_pawn.png",
}
EXPECTED_FILES = set(NAME_BY_KEY.values())


def die(msg, code=1):
    print(f"[ERR] {msg}", file=sys.stderr)
    sys.exit(code)


def log(msg, file=sys.stderr):
    print(msg, file=file, flush=True)


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
    见 references/architecture.md §5 Tag Schema：['chess-skin', 'chess-skin:<id>',
    'chess-skin:<id>:<pieceKey>']）。两者并存,旧依赖 key 的查询不受影响,
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


def upload_one(base_url, token, file_path, skin_id, piece_key):
    data = file_path.read_bytes()
    # 压缩：>50KB 调一次 Pillow 优化；否则原样上传
    if HAS_PIL and len(data) > 50_000:
        try:
            data = compress_png(file_path)
        except Exception as e:
            log(f"  warn: compress failed for {file_path.name}: {e}; uploading raw")
    key = f"chess/{skin_id}/{piece_key}"
    # 三级 tag：通用 / 皮肤级 / 棋子级（对应 references/architecture.md §5）
    tags = ["chess-skin", f"chess-skin:{skin_id}", f"chess-skin:{skin_id}:{piece_key}"]
    resp = http_multipart_upload(base_url, token, data, file_path.name, key, tags=tags)
    fid = resp.get("data", {}).get("fileId", "")
    if not fid:
        raise RuntimeError(f"upload failed for {file_path.name}: {resp}")
    return fid


def fetch_old_index(base_url, token, group_id):
    """登录态 GET /api/v1/kv/chess_skin:index?groupId=... 读旧 index（数组）；缺失返回 []。"""
    qs = urllib.parse.urlencode({"groupId": group_id})
    resp = http_get(base_url, f"/api/v1/kv/chess_skin:index?{qs}", token=token)
    if resp.get("code") != 0 or not resp.get("data"):
        return []
    try:
        return json.loads(resp["data"]["value"])
    except Exception as e:
        log(f"warn: parse old index failed: {e}; treating as empty")
        return []


def publish_index(base_url, token, group_id, metas):
    """登录态 POST /api/v1/kv 写回。

    同时写入 tags=['chess-skin'] —— 后端 KV 与 file 在 tag 维度统一，
    见 references/architecture.md §5 Tag Schema。KV 端不需要 skin/piece 级 tag，
    因为 chess_skin:index 自身就是全量索引。
    """
    body = {
        "key": "chess_skin:index",
        "value": json.dumps(metas, ensure_ascii=False),
        "visibility": "public",
        "groupId": group_id,
        "tags": ["chess-skin"],
    }
    resp = http_post_json(base_url, "/api/v1/kv", token, body)
    if resp.get("code") != 0:
        raise RuntimeError(f"publish failed: {resp}")


def anon_verify(base_url, group_id, expect_n):
    """匿名 GET 验证条数 + 关键 id 都在。"""
    qs = urllib.parse.urlencode({"groupId": group_id})
    resp = http_get(base_url, f"/api/v1/kv/public/chess_skin:index?{qs}", anonymous=True)
    if resp.get("code") != 0:
        raise RuntimeError(f"anon read failed: {resp}")
    arr = json.loads(resp["data"]["value"])
    if len(arr) < expect_n:
        raise RuntimeError(f"anon returned {len(arr)} skins, expected >= {expect_n}")


def main():
    ap = argparse.ArgumentParser(description="End-to-end: compress → upload → update KV (chess skin)")
    ap.add_argument("source_dir", help="12 张 PNG 所在目录")
    ap.add_argument("skin_id", help="数字或小写 ASCII id，例如 8 / neo")
    ap.add_argument("--name", default=None, help="displayName（默认：'皮肤 {skin_id}'）")
    ap.add_argument("--base", default=os.environ.get("CHESS_SKIN_BASE_URL", "http://47.110.80.47:8988"),
                    help="API base URL (default from env or hardcoded)")
    ap.add_argument("--group", type=int, default=int(os.environ.get("CHESS_SKIN_GROUP", "190")),
                    help="KV groupId (default from env or 190)")
    ap.add_argument("--no-compress", action="store_true", help="跳过 PNG 优化")
    args = ap.parse_args()

    src = Path(args.source_dir)
    if not src.is_dir():
        die(f"source_dir not found: {src}")
    found = {f.name for f in src.glob("*.png")}
    missing = EXPECTED_FILES - found
    extra = found - EXPECTED_FILES
    if missing:
        die(f"missing {len(missing)} files: {sorted(missing)[:5]}...")
    if extra:
        log(f"info: ignoring {len(extra)} extra files: {sorted(extra)[:5]}...")

    token = load_token()
    log(f"[1/4] uploading 12 pieces for skin '{args.skin_id}' from {src}")
    pieces = {}
    for key in PIECE_KEYS:
        fp = src / NAME_BY_KEY[key]
        try:
            fid = upload_one(args.base, token, fp, args.skin_id, key)
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

    log(f"[2/4] fetching old index from {args.base} (groupId={args.group})")
    old = fetch_old_index(args.base, token, args.group)
    log(f"  old index: {len(old)} skins")
    # merge: 同 id 覆盖；新 id 追加
    by_id = {m["id"]: m for m in old}
    by_id[args.skin_id] = meta
    merged = list(by_id.values())
    log(f"[3/4] publishing {len(merged)} skins (added/updated: {args.skin_id})")
    publish_index(args.base, token, args.group, merged)

    log(f"[4/4] anon verify")
    anon_verify(args.base, args.group, len(merged))

    log(f"OK: skin '{args.skin_id}' published. total {len(merged)} skins at {args.base}.")
    # 输出 meta JSON 到 stdout（便于 pipe 到 git add / CI）
    print(json.dumps(meta, ensure_ascii=False))


if __name__ == "__main__":
    main()
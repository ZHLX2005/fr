#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
add_emoji_pack.py —— 端到端：扫描 emoji 目录 → 上传 → 更新 KV emoji_<scope>:index。

用法：
    python add_emoji_pack.py <source_dir> <pack_id> [--scope <scope>] [--name <display_name>]

示例：
    # common 作用域（全局）
    python add_emoji_pack.py D:/emojis/celebration celebration --scope common --name "庆祝"

    # 特定游戏作用域（chess 房间可见）
    python add_emoji_pack.py D:/emojis/chess_only chess-faces --scope chess

    # 同 pack 重发（覆盖语义：删除旧 pack 中消失的 emoji file）
    python add_emoji_pack.py D:/emojis/celebration celebration --scope common

行为：
  1. 扫描 <source_dir>：每个 <emoji_id>.<ext> 文件 = 一个 emoji（.webp/.png/.jpg/.gif）
  2. 登录态 POST /api/v1/files 上传 N 个 emoji，拿 file_id
     · multipart 携带 key=emoji/<scope>/<packId>/<emojiId>
     · tags[]=['<scope>-emoji', '<scope>-emoji:<packId>', '<scope>-emoji:<packId>:<emojiId>']
  3. 拼 pack meta：{id: packId, displayName, version: 1, emojis: {<id>: FileRef}}
  4. 登录态 GET /api/v1/kv/emoji_<scope>:index 读旧 index（pack 数组形态）
  5. 合并：同 packId 覆盖；其他 pack 保留；新 packId 追加
  6. POST /api/v1/kv 写回（visibility=public, groupId=190, tags=['<scope>-emoji']）
  7. 匿名 GET /api/v1/kv/public/emoji_<scope>:index 验证
  8. 同 packId 覆盖时：best-effort DELETE 旧 pack 中消失的 emoji fileId

与 chess-skin-pipeline 的 add_skin.py 区别：
  · emoji 没有 chess 那套"12 key 严格匹配"硬约束 —— 每个 pack 自描述 emojis map
  · emoji id 允许下划线（skinId 不允许），正则更宽松
  · emoji 没有"棋盘颜色"等额外资源，等价于只有"pieces"字段

依赖：Python 3.8+ 标准库。
"""
import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


# ── 正则（与 lib/core/game_kit/emoji/emoji_pack_meta.dart 的 kEmojiIdPattern 对齐） ──
SCOPE_RE = re.compile(r"^[a-z0-9][a-z0-9-_]{0,31}$")
PACK_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
EMOJI_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-_]{0,31}$")
ALLOWED_EXTS = {".webp", ".png", ".jpg", ".jpeg", ".gif"}

CONTENT_TYPE_BY_EXT = {
    ".webp": "image/webp",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
}


def die(msg, code=1):
    print(f"[ERR] {msg}", file=sys.stderr)
    sys.exit(code)


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def kv_index_key(scope: str) -> str:
    return f"emoji_{scope}:index"


def kv_tag(scope: str) -> str:
    return f"{scope}-emoji"


def file_key_prefix(scope: str) -> str:
    return f"emoji/{scope}/"


def load_token():
    """Windows + POSIX 兼容：优先 ~/.kvcli/config.json；env KVCLI_CONFIG 覆盖。"""
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME") or "."
    candidates = [
        Path(os.environ["KVCLI_CONFIG"]) if os.environ.get("KVCLI_CONFIG") else None,
        Path(home) / ".kvcli" / "config.json",
    ]
    for p in candidates:
        if p and p.is_file():
            try:
                return json.loads(p.read_text(encoding="utf-8"))["token"]
            except Exception as e:
                die(f"read token failed from {p}: {e}")
    die("token not found; run `kvcli auth login` first")


def http_multipart_upload(base_url, token, file_bytes, file_name, key, tags, content_type):
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
    for t in tags:
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
    with urllib.request.urlopen(req, timeout=30) as r:
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


def scan_emojis(src: Path):
    """扫描目录，返回 [(emoji_id, file_path, content_type)]。

    约定：每个文件 <emoji_id>.<ext>（允许下划线/连字符）= 一个 emoji。
    - 大小写不敏感（统一转小写 emoji id）
    - 跳过非图片扩展名
    - emoji id 不合法 → 报错（不静默跳过，防 typo）
    """
    out = []
    seen_ids = set()
    for f in sorted(src.iterdir()):
        if not f.is_file():
            continue
        ext = f.suffix.lower()
        if ext not in ALLOWED_EXTS:
            continue
        emoji_id = f.stem.lower()
        if not EMOJI_ID_RE.match(emoji_id):
            die(f"invalid emoji id (file): {f.name} — must match {EMOJI_ID_RE.pattern}")
        if emoji_id in seen_ids:
            die(f"duplicate emoji id: {emoji_id} (case-insensitive collision)")
        seen_ids.add(emoji_id)
        out.append((emoji_id, f, CONTENT_TYPE_BY_EXT[ext]))
    return out


def upload_one(base_url, token, scope, pack_id, emoji_id, file_path, content_type):
    """上传单个 emoji，带三级 tag。"""
    data = file_path.read_bytes()
    key = f"{file_key_prefix(scope)}{pack_id}/{emoji_id}"
    tags = [
        kv_tag(scope),
        f"{kv_tag(scope)}:{pack_id}",
        f"{kv_tag(scope)}:{pack_id}:{emoji_id}",
    ]
    resp = http_multipart_upload(base_url, token, data, file_path.name, key, tags, content_type)
    fid = resp.get("data", {}).get("fileId", "")
    if not fid:
        raise RuntimeError(f"upload failed for {file_path.name}: {resp}")
    return fid


def fetch_old_index(base_url, token, group_id, scope):
    """登录态 GET /api/v1/kv/emoji_<scope>:index 读旧 index（pack 数组形态）。

    注意：ve emoji-pack-admin 的 flat open-set 形态在 KV 里是 array of {id,file}，
    本脚本发的是 pack 嵌套形态。两者通过 parseList 在客户端兼容；服务端只做字符串存储。
    """
    kv_key = kv_index_key(scope)
    qs = urllib.parse.urlencode({"groupId": group_id})
    resp = http_get(base_url, f"/api/v1/kv/{kv_key}?{qs}", token=token)
    if resp.get("code") != 0 or not resp.get("data"):
        return []
    try:
        return json.loads(resp["data"]["value"])
    except Exception as e:
        log(f"warn: parse old index failed: {e}; treating as empty")
        return []


def publish_index(base_url, token, group_id, packs, scope):
    """登录态 POST /api/v1/kv 写回整个 pack 数组。"""
    body = {
        "key": kv_index_key(scope),
        "value": json.dumps(packs, ensure_ascii=False),
        "visibility": "public",
        "groupId": group_id,
        "tags": [kv_tag(scope)],
    }
    resp = http_post_json(base_url, "/api/v1/kv", token, body)
    if resp.get("code") != 0:
        raise RuntimeError(f"publish failed: {resp}")


def collect_file_ids(pack: dict) -> list:
    """从一个 pack 收集所有 emoji fileId（保序去重）。"""
    out, seen = [], set()
    emojis = pack.get("emojis") if isinstance(pack, dict) else None
    if isinstance(emojis, dict):
        for v in emojis.values():
            if isinstance(v, dict):
                fid = v.get("fileId")
                if isinstance(fid, str) and fid and fid not in seen:
                    seen.add(fid)
                    out.append(fid)
    return out


def delete_file(base_url, token, file_id, group_id):
    """登录态 DELETE /api/v1/files/<fileId>?groupId=…；失败抛异常。"""
    qs = urllib.parse.urlencode({"groupId": group_id})
    req = urllib.request.Request(
        f"{base_url}/api/v1/files/{urllib.parse.quote(file_id)}?{qs}",
        method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        body = r.read()
        if not body:
            return
        try:
            resp = json.loads(body)
        except Exception:
            return
        if isinstance(resp, dict) and "code" in resp and resp.get("code") != 0:
            raise RuntimeError(f"delete file failed: {resp}")


def cleanup_orphaned_files(base_url, token, group_id, old_pack, new_pack):
    """同 packId 覆盖后：删除旧 pack 中不再存在的 emoji fileId（best-effort）。"""
    keep = set(collect_file_ids(new_pack))
    orphans = [fid for fid in collect_file_ids(old_pack) if fid not in keep]
    if not orphans:
        return
    cleaned, failed = 0, 0
    for fid in orphans:
        try:
            delete_file(base_url, token, fid, group_id)
            cleaned += 1
            log(f"  cleaned orphan file {fid[:8]}…")
        except Exception as e:
            failed += 1
            log(f"  warn: orphan delete {fid[:8]}… failed: {e}")
    log(f"  orphan cleanup: cleaned={cleaned} failed={failed}")


def anon_verify(base_url, group_id, scope, expect_n_packs):
    """匿名 GET 验证：code 0 + array 长度 ≥ 期望。"""
    qs = urllib.parse.urlencode({"groupId": group_id})
    resp = http_get(base_url, f"/api/v1/kv/public/{kv_index_key(scope)}?{qs}", anonymous=True)
    if resp.get("code") != 0:
        raise RuntimeError(f"anon read failed: {resp}")
    arr = json.loads(resp["data"]["value"])
    if len(arr) < expect_n_packs:
        raise RuntimeError(f"anon returned {len(arr)} packs, expected >= {expect_n_packs}")


def main():
    ap = argparse.ArgumentParser(
        description="End-to-end: scan emoji dir → upload → update emoji_<scope>:index"
    )
    ap.add_argument("source_dir", help="emoji 文件目录（每个文件 <emoji_id>.<ext>）")
    ap.add_argument("pack_id", help="emoji pack id（小写 kebab-case / snake_case）")
    ap.add_argument("--scope", default="common",
                    help="scope 标识（common 或 gameId，如 chess / line）。默认 common")
    ap.add_argument("--name", default=None,
                    help="displayName（默认：'Emoji {pack_id}'）")
    ap.add_argument("--base",
                    default=os.environ.get("CHESS_SKIN_BASE_URL", "http://47.110.80.47:8988"),
                    help="API base URL")
    ap.add_argument("--group", type=int,
                    default=int(os.environ.get("CHESS_SKIN_GROUP", "190")),
                    help="KV groupId (default 190)")
    ap.add_argument("--no-cleanup", action="store_true",
                    help="跳过孤儿 file 清理（默认会 best-effort 删除旧 pack 中消失的 emoji file）")
    args = ap.parse_args()

    # 校验
    if not SCOPE_RE.match(args.scope):
        die(f"invalid --scope '{args.scope}': must match {SCOPE_RE.pattern}")
    if not PACK_ID_RE.match(args.pack_id):
        die(f"invalid pack_id '{args.pack_id}': must match {PACK_ID_RE.pattern}")

    src = Path(args.source_dir)
    if not src.is_dir():
        die(f"source_dir not found: {src}")

    emojis = scan_emojis(src)
    if not emojis:
        die(f"no emoji files found in {src} (allowed exts: {sorted(ALLOWED_EXTS)})")
    log(f"scanned {len(emojis)} emojis in {src}")

    token = load_token()
    tag = kv_tag(args.scope)
    kv_key = kv_index_key(args.scope)
    log(f"[1/4] uploading {len(emojis)} emojis to scope={args.scope} pack={args.pack_id} (kv={kv_key}, tag={tag})")

    emoji_map = {}
    for emoji_id, file_path, ctype in emojis:
        try:
            fid = upload_one(args.base, token, args.scope, args.pack_id, emoji_id, file_path, ctype)
        except Exception as e:
            die(f"upload {file_path.name} failed: {e}")
        emoji_map[emoji_id] = {
            "fileId": fid,
            "fileName": file_path.name,
            "sizeBytes": file_path.stat().st_size,
            "contentType": ctype,
        }
        log(f"  ok {emoji_id} {file_path.name} -> {fid}")

    new_pack = {
        "id": args.pack_id,
        "displayName": args.name or f"Emoji {args.pack_id}",
        "version": 1,
        "emojis": emoji_map,
    }

    log(f"[2/4] fetching old index {kv_key} (groupId={args.group})")
    old = fetch_old_index(args.base, token, args.group, args.scope)
    log(f"  old packs: {len(old)}")
    # merge: 同 packId 覆盖；其他 pack 保留；新 packId 追加
    by_id = {p.get("id"): p for p in old if isinstance(p, dict) and p.get("id")}
    prev_pack = by_id.get(args.pack_id)
    by_id[args.pack_id] = new_pack
    merged = list(by_id.values())
    log(f"[3/4] publishing {len(merged)} packs (added/updated: {args.pack_id}) kv={kv_key} tag={tag}")
    publish_index(args.base, token, args.group, merged, args.scope)

    log(f"[4/4] anon verify {kv_key}")
    anon_verify(args.base, args.group, args.scope, len(merged))

    if not args.no_cleanup and prev_pack is not None:
        log(f"[5/5] cleaning orphaned emoji files for replaced pack '{args.pack_id}'")
        cleanup_orphaned_files(args.base, token, args.group, prev_pack, new_pack)
    elif prev_pack is None:
        log("[5/5] no previous pack → skip orphan cleanup")
    else:
        log("[5/5] --no-cleanup set → skip orphan cleanup")

    log(f"OK: emoji pack '{args.pack_id}' scope={args.scope} published. "
        f"total {len(merged)} packs at {args.base} kv={kv_key}.")
    # 输出 pack JSON 到 stdout
    print(json.dumps(new_pack, ensure_ascii=False))


if __name__ == "__main__":
    main()
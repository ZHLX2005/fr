#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
migrate_line_from_supabase.py —— 把「线」曲库从 Supabase 迁到 KV + File。

用法：
  python migrate_line_from_supabase.py
  python migrate_line_from_supabase.py --dry-run
  python migrate_line_from_supabase.py --base http://47.110.80.47:8988 --group 190

行为：
  1. 匿名读 Supabase REST：GET /rest/v1/music
  2. 对每首歌下载 audio / cover / chart（Storage 公开 URL）
  3. 登录态上传到 File API（tags=line-song / line-song:<id> / line-song:<id>:<asset>）
  4. 合并写 KV public line_song:index（groupId=190）
  5. 同 id 覆盖时 best-effort 删除旧 fileId
  6. 匿名 GET 校验

依赖：Python 3.8+ 标准库；token 来自 ~/.kvcli/config.json（kvcli auth login）。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

# ── 默认源（与旧 fr SupabaseConfig 对齐；仅迁移用） ──
DEFAULT_SUPABASE_URL = "https://kklrbynhqpwwhtfanqwt.supabase.co"
DEFAULT_SUPABASE_ANON = "sb_publishable_LMz3PGBaEJ3lJzMiS1BP1A_RajRck4P"

DEFAULT_BASE = os.environ.get("CHESS_SKIN_BASE_URL", "http://47.110.80.47:8988")
KV_KEY = "line_song:index"
TAG_PREFIX = "line-song"
FILE_KEY_PREFIX = "line/"
DEFAULT_GROUP = 190

SONG_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")


def die(msg, code=1):
    print(f"[ERR] {msg}", file=sys.stderr)
    sys.exit(code)


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def load_token():
    home = os.environ.get("USERPROFILE") or os.environ.get("HOME") or "."
    cfg = Path(home) / ".kvcli" / "config.json"
    env_cfg = os.environ.get("KVCLI_CONFIG")
    candidates = [Path(env_cfg)] if env_cfg else []
    candidates.append(cfg)
    for p in candidates:
        if p and p.is_file():
            try:
                return json.loads(p.read_text(encoding="utf-8"))["token"]
            except Exception as e:
                die(f"read token failed from {p}: {e}")
    die("token not found; run `kvcli auth login` first")


def slugify(raw: str) -> str:
    s = (raw or "").strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    if not s:
        s = "song"
    if not s[0].isalnum():
        s = "s" + s
    return s[:32]


def ensure_song_id(row: dict) -> str:
    raw = str(row.get("id") or row.get("slug") or row.get("name") or "")
    sid = slugify(raw)
    if not SONG_ID_RE.match(sid):
        die(f"cannot derive song id from row: {row.get('id')!r} / {row.get('name')!r}")
    return sid


def http_json(url, *, token=None, method="GET", body=None, headers=None, timeout=60):
    hdrs = dict(headers or {})
    if token:
        hdrs["Authorization"] = f"Bearer {token}"
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        if not raw:
            return {}
        return json.loads(raw)


def http_bytes(url, timeout=120):
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(), r.headers.get("Content-Type", "application/octet-stream")


def multipart_upload(base, token, file_bytes, file_name, key, tags, content_type, group_id):
    boundary = "----WebKitFormBoundary" + uuid.uuid4().hex
    parts = []
    def add(name, value, filename=None, ctype=None, is_bin=False):
        parts.append(f"--{boundary}".encode())
        if filename is not None:
            parts.append(
                f'Content-Disposition: form-data; name="{name}"; filename="{filename}"'.encode()
            )
            parts.append(f"Content-Type: {ctype or 'application/octet-stream'}".encode())
            parts.append(b"")
            parts.append(value if is_bin else value.encode())
        else:
            parts.append(f'Content-Disposition: form-data; name="{name}"'.encode())
            parts.append(b"")
            parts.append(value if isinstance(value, (bytes, bytearray)) else str(value).encode())

    add("accessLevel", "public")
    add("groupId", str(group_id))
    add("key", key)
    for t in tags:
        add("tags[]", t)
    add("file", file_bytes, filename=file_name, ctype=content_type, is_bin=True)
    parts.append(f"--{boundary}--".encode())
    parts.append(b"")
    payload = b"\r\n".join(parts)
    req = urllib.request.Request(
        f"{base}/api/v1/files",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(payload)),
        },
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def delete_file(base, token, file_id, group_id):
    qs = urllib.parse.urlencode({"groupId": group_id})
    req = urllib.request.Request(
        f"{base}/api/v1/files/{urllib.parse.quote(file_id)}?{qs}",
        method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        if not body:
            return
        resp = json.loads(body)
        if isinstance(resp, dict) and resp.get("code", 0) != 0:
            raise RuntimeError(resp)


def fetch_old_index(base, token, group_id):
    qs = urllib.parse.urlencode({"groupId": group_id})
    try:
        resp = http_json(f"{base}/api/v1/kv/{KV_KEY}?{qs}", token=token)
    except Exception as e:
        log(f"warn: fetch old index failed: {e}; treating as empty")
        return []
    if resp.get("code") != 0 or not resp.get("data"):
        return []
    try:
        return json.loads(resp["data"]["value"])
    except Exception:
        return []


def publish_index(base, token, group_id, metas):
    body = {
        "key": KV_KEY,
        "value": json.dumps(metas, ensure_ascii=False),
        "visibility": "public",
        "groupId": group_id,
        "tags": [TAG_PREFIX],
    }
    resp = http_json(f"{base}/api/v1/kv", token=token, method="POST", body=body)
    if resp.get("code") != 0:
        raise RuntimeError(f"publish failed: {resp}")


def collect_file_ids(meta: dict) -> list:
    out, seen = [], set()
    assets = meta.get("assets") if isinstance(meta, dict) else None
    if isinstance(assets, dict):
        for p in assets.values():
            if isinstance(p, dict):
                fid = p.get("fileId")
                if isinstance(fid, str) and fid and fid not in seen:
                    seen.add(fid)
                    out.append(fid)
    return out


def guess_name(url: str, fallback: str) -> str:
    try:
        path = urllib.parse.urlparse(url).path
        name = Path(path).name
        if name:
            return name
    except Exception:
        pass
    return fallback


def file_ref(info: dict, fallback_name: str, content_type: str) -> dict:
    data = info.get("data") if isinstance(info.get("data"), dict) else info
    fid = data.get("fileId") or data.get("id")
    if not fid:
        raise RuntimeError(f"upload missing fileId: {info}")
    return {
        "fileId": fid,
        "fileName": data.get("originalName") or data.get("fileName") or fallback_name,
        "sizeBytes": int(data.get("size") or data.get("sizeBytes") or 0),
        "contentType": data.get("contentType") or content_type,
    }


def fetch_supabase_music(supabase_url: str, anon: str) -> list:
    url = f"{supabase_url.rstrip('/')}/rest/v1/music?select=*"
    req = urllib.request.Request(
        url,
        headers={
            "apikey": anon,
            "Authorization": f"Bearer {anon}",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        rows = json.loads(r.read())
    if not isinstance(rows, list):
        die(f"unexpected supabase response: {rows!r}")
    return rows


def migrate_one(row, base, token, group_id, dry_run: bool) -> dict:
    song_id = ensure_song_id(row)
    name = row.get("name") or song_id
    artist = row.get("artist") or "Unknown"
    intro = row.get("intro") or ""
    bpm = int(row.get("bpm") or 120)
    duration_ms = int(row.get("duration_ms") or 180000)
    difficulty = int(row.get("difficulty") or 1)
    drop_ms = int(row.get("drop_duration_ms") or 2500)

    assets_src = {
        "audio": row.get("audio_url") or "",
        "cover": row.get("cover_url") or "",
        "chart": row.get("chart_url") or "",
    }
    for k, u in assets_src.items():
        if not u:
            die(f"song {song_id} missing {k}_url")

    log(f"  song {song_id}: {name}")
    assets = {}
    for asset_key, url in assets_src.items():
        fname = guess_name(url, f"{song_id}-{asset_key}")
        log(f"    download {asset_key} ← {url[:80]}…")
        blob, ctype = http_bytes(url)
        if dry_run:
            assets[asset_key] = {
                "fileId": "0" * 32,
                "fileName": fname,
                "sizeBytes": len(blob),
                "contentType": ctype or "application/octet-stream",
            }
            continue
        key = f"{FILE_KEY_PREFIX}{song_id}/{asset_key}"
        tags = [TAG_PREFIX, f"{TAG_PREFIX}:{song_id}", f"{TAG_PREFIX}:{song_id}:{asset_key}"]
        info = multipart_upload(
            base, token, blob, fname, key, tags, ctype or "application/octet-stream", group_id
        )
        assets[asset_key] = file_ref(info, fname, ctype or "application/octet-stream")
        log(f"    uploaded {asset_key} → {assets[asset_key]['fileId'][:8]}…")

    return {
        "id": song_id,
        "displayName": name,
        "artist": artist,
        "intro": intro,
        "bpm": bpm,
        "durationMs": duration_ms,
        "difficulty": difficulty,
        "dropDurationMs": drop_ms,
        "version": 1,
        "assets": assets,
    }


def main():
    ap = argparse.ArgumentParser(description="Migrate line songs Supabase → KV/File")
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--group", type=int, default=DEFAULT_GROUP)
    ap.add_argument("--supabase-url", default=DEFAULT_SUPABASE_URL)
    ap.add_argument("--supabase-anon", default=DEFAULT_SUPABASE_ANON)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="only migrate first N songs (0=all)")
    args = ap.parse_args()

    log(f"[1/5] fetch Supabase music @ {args.supabase_url}")
    try:
        rows = fetch_supabase_music(args.supabase_url, args.supabase_anon)
    except urllib.error.HTTPError as e:
        die(f"supabase REST failed: {e.code} {e.read()[:200]!r}")
    except Exception as e:
        die(f"supabase REST failed: {e}")
    log(f"  rows={len(rows)}")
    if args.limit > 0:
        rows = rows[: args.limit]
        log(f"  limit → {len(rows)}")

    token = None if args.dry_run else load_token()

    log(f"[2/5] upload assets → {args.base} groupId={args.group}")
    new_metas = []
    for row in rows:
        try:
            new_metas.append(
                migrate_one(row, args.base, token, args.group, args.dry_run)
            )
        except Exception as e:
            die(f"migrate row failed ({row.get('id')}/{row.get('name')}): {e}")

    if args.dry_run:
        log("[dry-run] skip publish; sample meta:")
        print(json.dumps(new_metas[:1], ensure_ascii=False, indent=2))
        log(f"OK dry-run: would publish {len(new_metas)} songs")
        return

    log(f"[3/5] merge + publish {KV_KEY}")
    old = fetch_old_index(args.base, token, args.group)
    by_id = {m["id"]: m for m in old if isinstance(m, dict) and m.get("id")}
    orphans = []
    for m in new_metas:
        prev = by_id.get(m["id"])
        if prev:
            keep = set(collect_file_ids(m))
            orphans.extend(fid for fid in collect_file_ids(prev) if fid not in keep)
        by_id[m["id"]] = m
    merged = list(by_id.values())
    publish_index(args.base, token, args.group, merged)
    log(f"  published {len(merged)} songs")

    log(f"[4/5] anon verify")
    qs = urllib.parse.urlencode({"groupId": args.group})
    resp = http_json(f"{args.base}/api/v1/kv/public/{KV_KEY}?{qs}")
    if resp.get("code") != 0:
        die(f"anon verify failed: {resp}")
    arr = json.loads(resp["data"]["value"])
    log(f"  anon count={len(arr)}")

    if orphans:
        log(f"[5/5] cleanup {len(orphans)} orphan files")
        for fid in orphans:
            try:
                delete_file(args.base, token, fid, args.group)
                log(f"  cleaned {fid[:8]}…")
            except Exception as e:
                log(f"  warn: delete {fid[:8]}… failed: {e}")
    else:
        log("[5/5] no orphans")

    log(f"OK: line_song:index has {len(merged)} songs at {args.base}")
    print(json.dumps({"count": len(merged), "ids": [m["id"] for m in new_metas]}, ensure_ascii=False))


if __name__ == "__main__":
    main()

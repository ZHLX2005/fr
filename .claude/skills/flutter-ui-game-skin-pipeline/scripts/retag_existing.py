#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
retag_existing.py —— 给已上传的棋子图片补 tag，并把 KV `chess_skin:index` 也加上 tag。

背景（2026-09-01）：
  add_skin.py 旧版本只发 `key=chess/<skinId>/<pieceKey>`（路径化 label）,
  没发后端的 `tags[]` 维度。新版本（add_skin.py）会同时发 key + tags。
  本脚本用来"补打"——把 tool/upload_chess_skins/chess_skins_file_ids.json 里
  84 个 file_id 全部 PATCH /api/v1/files/<id> 加上 tags,同时把 KV chess_skin:index
  重新写一次带上 tags=['chess-skin']。

⚠️ 跨组事实（已知）：
  - File: add_skin.py 没显式指定 groupId,旧文件落在 caller 的默认组（当前 23 个人空间）
  - KV:  chess_skin:index 在 groupId=190（shared,默认共享组）
  - 因此 file PATCH 不带 groupId（让后端按 fileId 定位到文件实际所在组）,
    KV 写回带 groupId=190。两者通过 fileId 字段在 KV meta 中关联。

用法：
    python retag_existing.py                  # 默认路径
    python retag_existing.py --dry-run        # 仅打印将要发的请求,不真打
    python retag_existing.py --base http://... # 自定义 baseUrl

行为：
  1. 读 tool/upload_chess_skins/chess_skins_file_ids.json（{skinId: {pieceKey: fileId}}）
  2. 对每个 file_id: PATCH /api/v1/files/<id> body={tags: [...]}
     · 失败 → 记录错误但继续;最后汇总
  3. 拉 KV chess_skin:index（登录态），合并（已无变化）+ 写回（带 tags）
  4. 验证 KV tag facet 含 chess-skin

依赖：Python 3.8+ 标准库（同 add_skin.py）。
"""
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path


# 默认 file_id 存档路径（相对 repo 根；脚本从 chess-skin-pipeline/scripts/ 上溯 4 级到 fr/）
REPO_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_FILE_IDS_JSON = REPO_ROOT / "tool" / "upload_chess_skins" / "chess_skins_file_ids.json"

KV_INDEX_KEY = "chess_skin:index"
SHARED_GROUP_ID = 190
COMMON_TAG = "chess-skin"


def die(msg, code=1):
    print(f"[ERR] {msg}", file=sys.stderr)
    sys.exit(code)


def log(msg, file=sys.stderr):
    print(msg, file=file, flush=True)


def load_token():
    """Windows + POSIX 兼容：优先 ~/.kvcli/config.json。"""
    p = Path.home() / ".kvcli" / "config.json"
    if not p.is_file():
        die(f"token not found at {p}; run `kvcli auth login` first")
    try:
        return json.loads(p.read_text(encoding="utf-8"))["token"]
    except Exception as e:
        die(f"read token failed from {p}: {e}")


def http_request(base_url, method, path, token=None, body=None, anonymous=False):
    """GET/PATCH/POST 通用 wrapper。后端响应是 {code, data, message} 信封,
    code != 0 时 raise（避免"HTTP 200 但业务失败"被误当成成功）。"""
    headers = {}
    if token and not anonymous:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{base_url}{path}", data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as r:
        resp = json.loads(r.read())
    if isinstance(resp, dict) and resp.get("code") != 0:
        raise RuntimeError(f"{method} {path} → code={resp.get('code')}, msg={resp.get('message')}")
    return resp


def piece_tags(skin_id, piece_key):
    """三级 tag：通用 / 皮肤级 / 棋子级（与 add_skin.py 完全一致）。"""
    return [COMMON_TAG, f"chess-skin:{skin_id}", f"chess-skin:{skin_id}:{piece_key}"]


def patch_file_tags(base_url, token, file_id, tags, dry_run=False):
    body = {"tags": tags}
    if dry_run:
        return {"ok": True, "dry_run": True, "file_id": file_id, "tags": tags}
    # 不带 groupId query —— file 的实际所在组不一定是 190（add_skin.py 没显式
    # 指定 file groupId,旧文件落在用户默认组 23）。后端按 fileId 定位,自带权限校验。
    return http_request(base_url, "PATCH", f"/api/v1/files/{file_id}", token, body)


def main():
    ap = argparse.ArgumentParser(description="Retro-tag existing chess skin files + KV index")
    ap.add_argument("--base", default=os.environ.get("CHESS_SKIN_BASE_URL", "http://47.110.80.47:8988"),
                    help="API base URL (default from env or hardcoded)")
    ap.add_argument("--group", type=int, default=SHARED_GROUP_ID, help="KV groupId")
    ap.add_argument("--ids-json", default=str(DEFAULT_FILE_IDS_JSON),
                    help=f"file_id 存档 JSON 路径 (default: {DEFAULT_FILE_IDS_JSON})")
    ap.add_argument("--dry-run", action="store_true", help="仅打印不发请求")
    args = ap.parse_args()

    ids_path = Path(args.ids_json)
    if not ids_path.is_file():
        die(f"file_id JSON not found: {ids_path}")
    mapping = json.loads(ids_path.read_text(encoding="utf-8"))
    if not isinstance(mapping, dict):
        die(f"unexpected mapping shape: {type(mapping)}")

    log(f"[1/3] retro-tagging {sum(len(v) for v in mapping.values())} files (groupId={args.group})")
    token = load_token()
    ok = 0
    fail = 0
    for skin_id, pieces in mapping.items():
        for piece_key, file_id in pieces.items():
            tags = piece_tags(skin_id, piece_key)
            try:
                patch_file_tags(args.base, token, file_id, tags, dry_run=args.dry_run)
                ok += 1
            except Exception as e:
                fail += 1
                log(f"  fail {skin_id}/{piece_key} -> {file_id}: {e}")
    log(f"  file patch done: ok={ok}, fail={fail}")

    log(f"[2/3] rewriting KV {KV_INDEX_KEY} with tags=['{COMMON_TAG}']")
    qs = urllib.parse.urlencode({"groupId": args.group})
    try:
        if args.dry_run:
            # dry-run: 不发 GET,也不发 POST,只打印 KV body 骨架
            kv_body = {
                "key": KV_INDEX_KEY,
                "value": "<would GET chess_skin:index first>",
                "visibility": "public",
                "groupId": args.group,
                "tags": [COMMON_TAG],
            }
            log(f"  dry-run: would POST /api/v1/kv with {kv_body}")
        else:
            # 后端响应是 {code:0, data:{key,value,tags,...}, message} 信封;
            # 取 data 后再读 value 字段(JSON 字符串,内含所有 skins 数组)
            get_resp = http_request(args.base, "GET", f"/api/v1/kv/{KV_INDEX_KEY}?{qs}", token)
            if get_resp.get("code") != 0 or not get_resp.get("data"):
                raise RuntimeError(f"GET KV 失败: {get_resp.get('message')}")
            metas = json.loads(get_resp["data"]["value"])
            kv_body = {
                "key": KV_INDEX_KEY,
                "value": json.dumps(metas, ensure_ascii=False),
                "visibility": "public",
                "groupId": args.group,
                "tags": [COMMON_TAG],
            }
            post_resp = http_request(args.base, "POST", "/api/v1/kv", token, kv_body)
            if post_resp.get("code") != 0:
                raise RuntimeError(f"POST KV 失败: {post_resp.get('message')}")
            log(f"  KV tags updated ({len(metas)} skins)")
    except Exception as e:
        log(f"  KV update failed: {e}")

    log(f"[3/3] anon verify tags facet (groupId={args.group})")
    qs2 = urllib.parse.urlencode({"groupId": args.group})
    try:
        # 注意:后端响应是 {code:0, data:{tags:[...], ...}, message} 信封
        facet_resp = http_request(args.base, "GET", f"/api/v1/kv/tags?{qs2}", token=token)
        if facet_resp.get("code") != 0:
            log(f"  KV tags facet query failed: {facet_resp.get('message')}")
            return
        tags_list = facet_resp.get("data", {}).get("tags", [])
        chess_tag = next((t for t in tags_list if t["tag"] == COMMON_TAG), None)
        if chess_tag:
            log(f"  KV tag facet OK: '{COMMON_TAG}' count={chess_tag['count']}")
        else:
            log(f"  KV tag facet WARN: '{COMMON_TAG}' not found in {[t['tag'] for t in tags_list]}")
    except Exception as e:
        log(f"  KV tags facet verify failed: {e}")

    if fail > 0:
        die(f"completed with {fail} file failures", code=2)
    log("OK: retro-tag done.")


if __name__ == "__main__":
    main()

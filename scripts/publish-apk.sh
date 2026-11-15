#!/usr/bin/env bash
# 把构建产物推到分发服务器（file server）的 fr_latest_apk。
#
# 用法：bash scripts/publish-apk.sh <apk 路径>
#
# ## 为什么单独抽成脚本 + 单独的 job
#
# 这条上传**跟构建的成败无关**：APK 构建 12 分钟全绿，只有上传会红。原来两者在同一个
# job 里，一次上传失败就得把 12 分钟的构建整个重跑一遍。现在 `publish` job 用
# `actions/download-artifact` 拿同一份产物，重跑一次只要 1 分钟。
#
# ## 为什么会失败（2026-11-15 实测，探针跑在真实 runner 上）
#
# GitHub 的 ubuntu-latest 有两种机器，出口链路差别极大：
#
#   网卡 eth0 / MTU 1500        → 25MB 3.8~6.0s，4~6MB/s      ✅
#   网卡 enp39s0 / MTU 9001     → 25MB 卡在 20KB/s，永远传不完 ❌
#
# 后者是 Azure 的加速网络（SR-IOV）机器：TCP 握手、请求头都正常，一到传大块数据就
# 零推进（`ParseMultipartForm failed: read tcp ... i/o timeout`，服务端 60s 读超时）。
# 把 guest 侧 MTU 降到 1300 也没用（实测仍 19KB/s），所以**这不是 MTU 问题，是那批
# 机器的数据面到这台服务器不通**，从 runner 内部无法绕开。
#
# 结论：碰到坏机器只能换一台 —— 也就是「重跑这个 job」。所以这里做两件事：
#   1. 先用 1MB 探针（`--speed-limit` 8 秒没进度就算死）判定链路，坏机器立刻报错，
#      把「换机器」写在错误信息里，而不是傻等 5×20 秒；
#   2. 好机器上照旧重试（跨境链路仍会偶发劣化），5 次都失败才红。
#
# ## 不吞错误
#
# 线上包悄悄停在旧版本比红一次严重得多（2026-09-22 就发生过）。所以本脚本任何一次
# 「拿不到 code:0 或 sha256 对不上」都以非 0 退出。

set -uo pipefail

# ─────────────────────────────────────────────────────────────────────────
# 写 job summary。有 GITHUB_STEP_SUMMARY 就写文件（CI），没有就打到 stdout（本机）。
write_summary() {
  local icon="$1" status="$2" sha="$3" extra="$4"
  local body
  body=$(
    echo "### APK 分发上传结果"
    echo
    echo "- 状态: $icon $status"
    echo "- sha256: \`$sha\`"
    echo "- 大小: $SIZE 字节"
    echo "- 分发地址: http://47.110.80.47:8988/files/by-key/$KEY"
    [ -n "$extra" ] && echo "- 备注: $extra"
  )
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "$body" >> "$GITHUB_STEP_SUMMARY"
  else
    printf '%s\n' "$body"
  fi
}

HOST="${HOST:-http://47.110.80.47:8988}"
KEY="${KEY:-fr_latest_apk}"
ATTEMPTS="${ATTEMPTS:-5}"

APK_FILE="${1:-}"
if [ -z "$APK_FILE" ] || [ ! -f "$APK_FILE" ]; then
  echo "::error::用法：bash scripts/publish-apk.sh <apk 路径>（收到「$APK_FILE」）"
  exit 2
fi

LOCAL_SHA=$(sha256sum "$APK_FILE" | cut -d' ' -f1)
SIZE=$(stat -c %s "$APK_FILE")
echo "上传 $APK_FILE（$SIZE 字节）"
echo "本地 sha256: $LOCAL_SHA"

# ── 机器体检（诊断用，不决定成败）─────────────────────────────────────────
IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
IFACE_MTU="?"
[ -n "$IFACE" ] && [ -r "/sys/class/net/$IFACE/mtu" ] && IFACE_MTU=$(cat "/sys/class/net/$IFACE/mtu")
echo "出口网卡: ${IFACE:-?}  MTU: $IFACE_MTU"

# ── 链路预检：1MB 探针。8 秒内推不动就直接判死，省下 5×20 秒的傻等 ─────────
head -c 1000000 /dev/urandom > /tmp/link_probe.bin
PROBE_RC=0
PROBE_SPEED=$(curl -sS -o /dev/null -w '%{speed_upload}' \
  --connect-timeout 10 --max-time 25 --speed-limit 50000 --speed-time 8 \
  -X POST "$HOST/api/v1/files" \
  -F "file=@/tmp/link_probe.bin" -F "key=fr_link_probe" \
  -F "accessLevel=public" -F "expireSeconds=60" 2>/dev/null) || PROBE_RC=$?

LINK_OK=false
[ "$PROBE_RC" = "0" ] && LINK_OK=true
echo "链路预检: exit=$PROBE_RC · ${PROBE_SPEED:-0} B/s"

if [ "$LINK_OK" != "true" ] && [ "$IFACE_MTU" != "?" ] && [ "$IFACE_MTU" -gt 1500 ]; then
  echo "::error::这台 runner 到分发服务器的数据面不通：网卡 $IFACE 是巨帧加速网络（MTU $IFACE_MTU），实测只有约 20KB/s（$SIZE 字节永远传不完）。"
  echo "::error::降 MTU 无效（实测仍 19KB/s）—— 只能换一台机器："
  echo "::error::在本页右上角 Re-run → Re-run failed jobs，或命令行 \`gh run rerun <run-id> --failed\`。"
  echo "::error::publish 是独立 job，只下载产物 + 上传，重跑约 1 分钟，不用再等 12 分钟构建。"
  write_summary "❌" "没通过链路预检" "$LOCAL_SHA" "网卡 $IFACE / MTU $IFACE_MTU（加速网络），预检 ${PROBE_SPEED:-0} B/s"
  exit 1
fi

# ── 正式上传：好机器上跨境仍偶发卡顿，重试几次 ─────────────────────────────
UPLOADED=false
RESPONSE=""
LAST_RC=0
for attempt in $(seq 1 "$ATTEMPTS"); do
  echo "--- upload attempt $attempt/$ATTEMPTS ---"
  LAST_RC=0
  RESPONSE=$(curl -sS --connect-timeout 15 --max-time 300 \
    --speed-limit 100000 --speed-time 20 \
    -X POST "$HOST/api/v1/files" \
    -F "file=@$APK_FILE" \
    -F "key=$KEY" \
    -F "accessLevel=public" \
    -F "expireSeconds=0") || LAST_RC=$?
  echo "curl exit=$LAST_RC · upload response: $RESPONSE"
  # 双重校验：code=0 且服务端回算的 sha256 与本地一致（防半截/被改写的包上线）
  if echo "$RESPONSE" | grep -Eq '"code":[[:space:]]*0' && echo "$RESPONSE" | grep -q "$LOCAL_SHA"; then
    UPLOADED=true
    echo "APK uploaded successfully (attempt $attempt)"
    break
  fi
  echo "attempt $attempt 失败（curl exit=$LAST_RC），10 秒后重试..."
  sleep 10
done

if [ "$UPLOADED" = "true" ]; then
  write_summary "✅" "成功" "$LOCAL_SHA" ""
  echo "download_url=$HOST/files/by-key/$KEY" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

write_summary "❌" "失败（已重试 $ATTEMPTS 次）" "$LOCAL_SHA" "最后响应/exit：\`${RESPONSE:-curl exit=$LAST_RC}\`"
echo "::error::APK 上传失败（重试 $ATTEMPTS 次仍失败），本次构建未发布到分发渠道"
exit 1

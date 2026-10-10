// lib/lab/demos/remotetype/rt_constants.dart
//
// RemoteType（远程输入）lab demo 常量。
// 直连模式：唯一后端是 mn-rt 的 server.js（固定部署地址内置，用户不填）。

/// mn-rt server 固定部署地址（server 托管的网页控制台同源）
const String kRemoteTypeServerUrl = 'http://1.94.101.189:8790';

/// 房间号字母表：与 mn-rt rt-crypto.js 的 ROOM_ALPHABET 逐字符一致。
/// 直连模式下派生房间号不再用于路由，仅作为 AAD 上下文标签（两端一致即可）。
const String kRtRoomAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 房间号长度（从派生字节映射而来）
const int kRtRoomCodeLen = 5;

/// PBKDF2 参数（key 预期高熵随机，迭代只求抹平实现差异）
const int kRtPbkdf2Iterations = 10000;
const String kRtPbkdf2Salt = 'RT1-pair';

/// HKDF info 标签（两端逐字节一致，改动必须同步 mn-rt 并重出对拍向量）
const String kRtInfoRoom = 'RT1-room';
const String kRtInfoSalt = 'RT1-salt';
const String kRtInfoKeyPhoneToPc = 'RT1-key-phone-pc';
const String kRtInfoKeyPcToPhone = 'RT1-key-pc-phone';

/// AAD 协议前缀
const String kRtAadPrefix = 'RT1';

/// 方向标签
const String kRtDirPhoneToPc = 'p2c';
const String kRtDirPcToPhone = 'c2p';

/// 输入同步防抖（ASR partial 高频变更）
const Duration kRtSyncDebounce = Duration(milliseconds: 250);

/// 全文上限（与 mn-rt sanitize 截断上限一致）
const int kRtMaxTextLength = 5000;

/// 构建标识：联调时核对手机上跑的是不是最新修复（每次改动 demo 逻辑时递增）
const String kRtBuildTag = 'b5-controller-listener';

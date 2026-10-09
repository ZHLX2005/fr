// lib/lab/demos/remotetype/rt_crypto.dart
//
// RT1 协议加密层 —— 与 mn-rt client/lib/rt-crypto.js 逐字节对齐。
// 跨语言契约由两侧单测钉死：mn-rt test/vectors/rt1-vectors.json（源）
// ↔ fr test/rt1_vectors_test.dart（消费同一组期望值）。
//
// 设计要点见 plan 与 rt_constants.dart 注释：一个 key 派生房间号/配对盐/双方向密钥，
// 过 relay 的一切都不是密钥本体，每条消息 AES-256-GCM + AAD 绑定。

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'rt_constants.dart';

/// 派生结果：房间号 + 配对盐 + 双方向 AES-256 密钥
class RtDerived {
  const RtDerived({
    required this.room,
    required this.pairSalt,
    required this.keyPhoneToPc,
    required this.keyPcToPhone,
  });

  final String room;
  final Uint8List pairSalt;
  final Uint8List keyPhoneToPc;
  final Uint8List keyPcToPhone;
}

/// key 归一化：大写 + 只留字母数字（与 mn-rt normalizeKey 一致）
String rtNormalizeKey(String raw) {
  return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

final AesGcm _aesGcm = AesGcm.with256bits();

/// 从用户 key 派生全部会话材料（与 mn-rt deriveFromKey 对齐）
Future<RtDerived> rtDeriveFromKey(String rawKey) async {
  final key = rtNormalizeKey(rawKey);
  if (key.isEmpty) {
    throw ArgumentError('pairing key is empty');
  }

  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: kRtPbkdf2Iterations,
    bits: 256,
  );
  final master = await pbkdf2.deriveKey(
    secretKey: SecretKeyData(utf8.encode(key)),
    nonce: utf8.encode(kRtPbkdf2Salt),
  );
  final masterBytes = await master.extractBytes();

  Future<Uint8List> expand(String info, int length) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: length);
    final k = await hkdf.deriveKey(
      secretKey: SecretKeyData(masterBytes),
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await k.extractBytes());
  }

  final roomBytes = await expand(kRtInfoRoom, 32);
  final room = _bytesToRoomCode(roomBytes);

  return RtDerived(
    room: room,
    pairSalt: await expand(kRtInfoSalt, 16),
    keyPhoneToPc: await expand(kRtInfoKeyPhoneToPc, 32),
    keyPcToPhone: await expand(kRtInfoKeyPcToPhone, 32),
  );
}

/// 字节 → 房间号：rejection sampling 消除取模偏置（与 mn-rt 一致）
String _bytesToRoomCode(List<int> bytes) {
  final alphabet = kRtRoomAlphabet.codeUnits;
  final out = StringBuffer();
  for (final b in bytes) {
    if (out.length >= kRtRoomCodeLen) break;
    if (b < 248) {
      // 31 * 8 = 248，丢弃尾部有偏字节
      out.writeCharCode(alphabet[b % alphabet.length]);
    }
  }
  if (out.length < kRtRoomCodeLen) {
    throw StateError('room derive failed');
  }
  return out.toString();
}

/// 配对应答：proof = HMAC-SHA256(key=pairSalt, data=nonce) hex
Future<String> rtPairProof(Uint8List pairSalt, String nonce) async {
  final mac = await Hmac.sha256().calculateMac(
    utf8.encode(nonce),
    secretKey: SecretKey(pairSalt),
  );
  return mac.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

/// 构造 AAD：绑定 协议版本|房间|方向|序号
String rtBuildAad(String room, String direction, int seq) {
  return '$kRtAadPrefix|$room|$direction|$seq';
}

/// 加密一条业务明文，产出 relay 信封（与 mn-rt seal 同构）
Future<Map<String, dynamic>> rtSeal({
  required Uint8List key,
  required String aad,
  required Map<String, dynamic> plaintext,
  String? sid,
  int seq = 0,
}) async {
  final nonce = _randomNonce();
  final secretBox = await _aesGcm.encrypt(
    utf8.encode(jsonEncode(plaintext)),
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: utf8.encode(aad),
  );
  final ct = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);
  return <String, dynamic>{
    'sid': sid ?? _randomSid(),
    'seq': seq,
    'nonce': base64Encode(nonce),
    'ct': base64Encode(ct),
  };
}

/// 解密 relay 信封；tag/AAD 校验失败抛 SecretBoxAuthenticationError
Future<Map<String, dynamic>> rtOpen({
  required Uint8List key,
  required String aad,
  required Map<String, dynamic> envelope,
}) async {
  final nonce = base64Decode(envelope['nonce'] as String);
  final body = base64Decode(envelope['ct'] as String);
  if (nonce.length != 12 || body.length < 16) {
    throw ArgumentError('malformed envelope');
  }
  final cipherText = body.sublist(0, body.length - 16);
  final mac = body.sublist(body.length - 16);
  final clear = await _aesGcm.decrypt(
    SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
    secretKey: SecretKey(key),
    aad: utf8.encode(aad),
  );
  return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
}

final Random _rng = Random.secure();

Uint8List _randomNonce() {
  return Uint8List.fromList(List<int>.generate(12, (_) => _rng.nextInt(256)));
}

String _randomSid() {
  final b = List<int>.generate(4, (_) => _rng.nextInt(256));
  return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

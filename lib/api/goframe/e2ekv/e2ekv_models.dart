/// e2ekv 数据模型 —— 与服务端 api/e2ekv/v1/e2ekv.go DTO 一致。
library;

// ── KDF 参数（setup body + 响应、kdf_meta 内嵌）──

class KdfParams {
  final String name; // 'PBKDF2-SHA256'
  final int iter;
  final String salt; // base64(16B)

  const KdfParams({required this.name, required this.iter, required this.salt});

  factory KdfParams.fromJson(Map<String, dynamic> j) => KdfParams(
        name: j['name'] as String? ?? 'PBKDF2-SHA256',
        iter: j['iter'] as int? ?? 600000,
        salt: j['salt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'name': name, 'iter': iter, 'salt': salt};
}

// ── Setup ──

class SetupRes {
  final String authHash; // 64 hex
  final KdfParams kdf;
  final String createdAt; // RFC3339

  const SetupRes({
    required this.authHash,
    required this.kdf,
    required this.createdAt,
  });

  factory SetupRes.fromJson(Map<String, dynamic> j) => SetupRes(
        authHash: j['auth_hash'] as String? ?? '',
        kdf: KdfParams.fromJson(j['kdf'] as Map<String, dynamic>? ?? const {}),
        createdAt: j['created_at'] as String? ?? '',
      );
}

// ── List ──

class BlobMeta {
  final String k;
  final int version;
  final int size;
  final String updatedAt;

  const BlobMeta({
    required this.k,
    required this.version,
    required this.size,
    required this.updatedAt,
  });

  factory BlobMeta.fromJson(Map<String, dynamic> j) => BlobMeta(
        k: j['k'] as String? ?? '',
        version: (j['version'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        updatedAt: j['updated_at'] as String? ?? '',
      );
}

class ListRes {
  final List<BlobMeta> items;
  final int total;
  const ListRes({required this.items, required this.total});
  factory ListRes.fromJson(Map<String, dynamic> j) => ListRes(
        items: (j['items'] as List<dynamic>? ?? const [])
            .map((e) => BlobMeta.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

// ── Get ──

class KdfBlobMeta {
  final int v; // 1
  final KdfParams kdf;
  final String cipher; // 'AES-256-GCM'
  final String dekInfo; // utf8(k)

  const KdfBlobMeta({
    required this.v,
    required this.kdf,
    required this.cipher,
    required this.dekInfo,
  });

  factory KdfBlobMeta.fromJson(Map<String, dynamic> j) => KdfBlobMeta(
        v: (j['v'] as num?)?.toInt() ?? 1,
        kdf: KdfParams.fromJson(j['kdf'] as Map<String, dynamic>? ?? const {}),
        cipher: j['cipher'] as String? ?? 'AES-256-GCM',
        dekInfo: j['dek_info'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'v': v,
        'kdf': kdf.toJson(),
        'cipher': cipher,
        'dek_info': dekInfo,
      };
}

class GetRes {
  final String k;
  final int version;
  final String nonce; // base64(12B)
  final String ciphertext; // base64(密文+tag)
  final KdfBlobMeta kdfMeta;
  final String updatedAt;

  const GetRes({
    required this.k,
    required this.version,
    required this.nonce,
    required this.ciphertext,
    required this.kdfMeta,
    required this.updatedAt,
  });

  factory GetRes.fromJson(Map<String, dynamic> j) => GetRes(
        k: j['k'] as String? ?? '',
        version: (j['version'] as num?)?.toInt() ?? 0,
        nonce: j['nonce'] as String? ?? '',
        ciphertext: j['ciphertext'] as String? ?? '',
        kdfMeta: KdfBlobMeta.fromJson(
            j['kdf_meta'] as Map<String, dynamic>? ?? const {}),
        updatedAt: j['updated_at'] as String? ?? '',
      );
}

// ── Put ──

class PutRes {
  final int version;
  final String updatedAt;
  const PutRes({required this.version, required this.updatedAt});
  factory PutRes.fromJson(Map<String, dynamic> j) => PutRes(
        version: (j['version'] as num?)?.toInt() ?? 0,
        updatedAt: j['updated_at'] as String? ?? '',
      );
}

// ── Delete ──

class DeleteRes {
  final String deletedAt;
  const DeleteRes({required this.deletedAt});
  factory DeleteRes.fromJson(Map<String, dynamic> j) =>
      DeleteRes(deletedAt: j['deleted_at'] as String? ?? '');
}
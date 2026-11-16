import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../api/mnws/nxkv/nxkv_controller.dart';

/// 选一张图（相册 / 拍照）并传到 PC 的**本机附件仓**，返回可直接插进正文的
/// 嵌入片段（`![名](fileId)`，服务端生成）。
///
/// 取消（没选图 / 没选来源）返回**空串** —— 调用方以空串为「什么都不做」，
/// 不是错误；真正的失败（上传挂了）抛异常，由调用方提示。
///
/// 压缩参数：`imageQuality: 85` + 最长边 1920 —— 手机截图/照片原图动辄 3~8MB，
/// 经桥 base64 传输再落盘又慢又占 PC 附件仓；验收截图 85 分辨率完全够读。
Future<String> pickAndUploadImage(
  NxKvController c,
  BuildContext context,
) async {
  final cs = Theme.of(context).colorScheme;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.photo_library_outlined, size: 20, color: cs.onSurfaceVariant),
            title: const Text('从相册选', style: TextStyle(fontSize: 13)),
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, size: 20, color: cs.onSurfaceVariant),
            title: const Text('拍一张', style: TextStyle(fontSize: 13)),
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return '';

  final x = await ImagePicker().pickImage(
    source: source,
    imageQuality: 85,
    maxWidth: 1920,
  );
  if (x == null) return '';

  final bytes = await x.readAsBytes();
  if (bytes.isEmpty) return '';
  final dot = x.name.lastIndexOf('.');
  final mime = x.mimeType ??
      (dot >= 0 && x.name.substring(dot + 1).toLowerCase() == 'png'
          ? 'image/png'
          : 'image/jpeg');
  final up = await c.uploadImage(name: x.name, bytes: bytes, contentType: mime);
  return up.markdown;
}

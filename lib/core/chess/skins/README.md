# Chess 模块 — 皮肤 (Skins)

> 国际象棋棋盘的棋子皮肤来源：**dart 端 const catalog + server 端 File API 公开下载 URL**。
> 实测（spec §0 设计变更，2026-08-29）：所有 webp 图走 `http://47.110.80.47:8988/files/<32-hex>`，无 token 也能下载成功（md5 一致）。

---

## 1. 数据流（启动期）

```
1. main() 调用 ChessSkinBundle.registerHardcoded()
2. 遍历 kChessSkinsCatalog（const List<ChessSkinMeta>，7 套皮肤 × 12 piece = 84 个 FileRef）
3. 每套构造 RemoteChessSkin(meta, fileResolver: PublicFileResolver(baseUrl: ...))
4. UI 端通过 ChessSkinBundle.byId('<skinId>') 拿到 ChessSkin
5. chess_board.dart 渲染时调 `skin.pieces['wK']` → CachedNetworkImage(url) → 自动 7 天磁盘缓存
```

**优势：**
- 客户端无登录即可拉图（File API 公开 endpoint）
- 84 个 file_id 全部 hardcode 在 dart 源 → 启动零网络拉取
- 缓存命中率高：换皮肤走同一 group，cached_network_image 复用

**代价：**
- 添加 / 更新皮肤 = 发新版本客户端（file_id 是 const 字符串）
- 84 个 file_id 占了约 4 KB const catalog（可接受）

---

## 2. 文件结构

```
lib/core/chess/skins/
├── chess_skin.dart          ← 接口合约 + Default + Bundle（启动期 registerHardcoded）
├── chess_skin_meta.dart     ← ChessSkinMeta + FileRef + 12-key 校验 + const 7 套 catalog
├── file_resolver.dart       ← FileResolver abstract + PublicFileResolver 默认
├── remote_chess_skin.dart   ← RemoteChessSkin implements ChessSkin（用 CachedNetworkImage）
└── README.md                ← 本文件
```

---

## 3. 资源记录

`tool/upload_chess_skins/chess_skins_file_ids.json` 存档 84 个 file_id + source 路径。
如需重新生成图片资源：

1. 找一张 14 张 webp 的 source 目录（用户当前是 `D:\DevProjects\my\test\image\chess\2\`）
2. 跑上传脚本（见 `tool/upload_chess_skins/`），走 `POST /api/v1/files` multipart（**不是** `/api/v1/upload`）
3. 把新 file_id 替换到 `chess_skin_meta.dart` 的 `kChessSkinsCatalog`

---

## 4. 与 ColorStrategy 的边界

- **棋盘两色格 / 选中 / 高亮 / 将军 / 升变面板**：走 `context.chessColors`（v6.2.1 第 6 strategy 通道，scheme 派生）
- **棋子图像**：走本目录的 `RemoteChessSkin.pieces`（dart const + 公开 URL 下载）
- **互相不重叠**：切主题只改颜色，不动棋子；换皮肤只改图像，不动颜色

---

## 5. 何时调 `ChessSkinBundle.registerHardcoded()`

启动期调用一次。看 `lib/main.dart`：

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ChessSkinBundle.registerHardcoded();  // ← 在 runApp() 之前调
  runApp(...);
}
```

跨多个测试调用是幂等的（已注册的 id 会被覆盖）。

---

## 6. widgets/ 占位

`lib/core/chess/widgets/` 目录保留给后续 widget 实现（当前空）：
- `chess_board.dart`（8x8 两色格 + 坐标 + 高亮）
- `chess_piece.dart`（用 `skin.pieces['wK']` 渲染）
- `chess_controller.dart`（触摸/拖拽 → Move）
- `chess_room_page.dart`（顶层页面）

业务逻辑（models / engine / p2p / skins）已完整可独立编译运行。

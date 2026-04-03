# fr

Flutter 应用，专注时间管理与数据追踪。

## 技术栈

- **框架**: Flutter 3.x
- **状态管理**: Provider / Riverpod
- **本地存储**: Hive + SharedPreferences
- **HTTP**: http + web_socket_channel

## 依赖项

| 分类 | 依赖 |
|------|------|
| UI | cupertino_icons, cached_network_image, flutter_markdown, flutter_widget_from_html, emoji_picker_flutter |
| 存储 | hive, hive_flutter, shared_preferences, path_provider |
| 媒体 | just_audio, audioplayers, video_player, chewie, record, image_picker, photo_manager |
| 网络 | http, web_socket_channel |
| 设备 | flutter_blue_plus, sensors_plus, permission_handler |
| 功能 | url_launcher, webview_flutter, app_settings, image_cropper, flutter_reorderable_grid_view, home_widget, flutter_local_notifications |
| 构建 | json_serializable, build_runner, flutter_launcher_icons |

## 开发

```bash
flutter pub get
flutter build web --release
```

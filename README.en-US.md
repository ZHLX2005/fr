

# fr (Little Bean)

A multi-functional Flutter application focused on time management, AI chat, data tracking, and experimental feature exploration.

## Features

### Core Features

- **Pomodoro Timer** - Focus timer with statistics and subject management
- **AI Chat** - Conversations with AI assistants and agents (Supabase backend)
- **Timetable** - Course schedule management (Hive local storage, supports recurring weeks)
- **Local Network Discovery** - LocalNet device discovery and communication (In-development placeholder)
- **Gallery Management** - Media resource management and browsing (In-development placeholder)

### Experimental Demos (Lab)

Managed via IoC container registration, containing 35 experimental pages:

| Demo              | Description                     |
| ----------------- | ------------------------------- |
| Grid Dashboard    | Dashboard layout                |
| Notebook AI Proto | AI Notebook prototype           |
| Clock Demo        | Clock/Timer UI                  |
| Network Demo      | Network functionality demo      |
| Network Env Demo  | Network environment detection   |
| Game 2048         | 2048 game                       |
| Free Canvas       | Free canvas                     |
| Drag Reorder      | Drag-to-reorder grid            |
| Web Bookmark      | Bookmark manager                |
| Storage Analyze   | Storage analysis                |
| Hexagon Panel     | Hexagon panel                   |
| Snake Game        | Snake game                      |
| API Test          | API testing tool                |
| Calendar          | Calendar component              |
| My Diary Header   | Diary header                    |
| Water Capsule     | Water capsule UI                |
| Speech Synthesis  | Speech synthesis                |
| Line Demo         | Music game (rhythm line)        |
| Torch Demo        | Flashlight control              |
| Sensor Demo       | Sensor data                     |
| Word Drag         | Word drag & categorize          |
| Overlay Demo      | Overlay window (Android)        |
| Body Map          | Body parts map                  |
| Localnet Demo     | Local network functionality demo|
| Gallery Demo      | Gallery functionality demo      |
| Schema Demo       | Schema navigation demo          |
| Color Palette     | Color palette tool              |
| GitHub Demo       | GitHub Actions/Issues           |
| QR Demo           | QR code scan & generate         |
| DoubleTime        | Dual timeline visualization     |
| Notification Demo | Local notification demo         |
| Novel Reader      | Novel reader prototype          |
| Arc Selector      | Arc selector                    |
| Demo Laboratory   | Rive animation lab              |
| Volume Decay      | Volume decay curve              |
| Rive Pendulum     | Rive pendulum animation         |

## Tech Stack

- **Framework**: Flutter (Dart SDK ^3.11.1)
- **State Management**: Provider + Riverpod
- **Local Storage**: Hive + SharedPreferences
- **Backend Service**: Supabase
- **HTTP/Networking**: http + web_socket_channel
- **Native Bridging**: MethodChannel + Overlay Window
- **Game Engine**: Flame
- **Animation**: Rive

## Dependencies

| Category     | Dependencies                                                                                                                                          |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| State Mgmt   | provider, flutter_riverpod                                                                                                                            |
| Storage      | hive, hive_flutter, shared_preferences, path_provider                                                                                                 |
| Data Models  | json_annotation, json_serializable, build_runner, uuid                                                                                                |
| Networking   | http, web_socket_channel, network_info_plus, supabase_flutter                                                                                         |
| Media        | just_audio, audioplayers, video_player, chewie, record, image_picker, image_cropper, photo_manager, file_picker, cached_network_image                 |
| UI Components| cupertino_icons, flutter_markdown, markdown, flutter_widget_from_html, emoji_picker_flutter, flutter_reorderable_grid_view, flutter_card_swiper       |
| Devices      | flutter_blue_plus, sensors_plus, permission_handler, app_settings, torch_light, screen_brightness, wakelock_plus, flutter_overlay_window              |
| Features     | url_launcher, webview_flutter, intl, home_widget, flutter_local_notifications, mobile_scanner, qr_flutter, open_filex, share_plus, flame              |
| Build Tools  | flutter_lints, flutter_launcher_icons                                                                                                                 |

## Project Structure

```
lib/
├── main.dart                    # Application entrypoint (Supabase + Hive initialization)
├── core/                        # Core feature modules
│   ├── body/                    # Body parts map (recording/visualization)
│   │   ├── models/              # Data models
│   │   ├── pages/               # Pages
│   │   ├── painters/            # Custom painters
│   │   └── widgets/             # Widgets
│   ├── color/                   # Color palette tool
│   │   └── theme/               # App theme configuration
│   ├── doubletime/              # Dual timeline visualization
│   ├── focus/                   # Pomodoro timer (timer/stats/subjects)
│   │   ├── models/
│   │   └── providers/
│   ├── github/                  # GitHub Actions & Issues integration
│   ├── line/                    # Rhythm game (Line game)
│   │   ├── models/
│   │   ├── pages/
│   │   ├── repository/
│   │   ├── settings/
│   │   └── widgets/
│   ├── localnet/                # Local network discovery & communication
│   │   ├── models/
│   │   ├── pages/
│   │   └── services/
│   ├── schema/                  # Schema navigation & parsing
│   ├── storage/                 # Storage management
│   ├── timetable/               # Timetable (DDD architecture)
│   │   ├── data/                # Data layer (Hive repository)
│   │   ├── domain/              # Domain models
│   │   └── presentation/        # Presentation layer
│   └── word_drag/               # Word drag & categorize
│       ├── models/
│       ├── providers/
│       └── widgets/
├── lab/                         # Experimental Demos
│   ├── demos/                   # 31 Demo pages
│   ├── models/                  # Data models
│   ├── providers/               # State management
│   ├── utils/                   # Utility functions
│   ├── widgets/                 # Common widgets
│   ├── lab_container.dart       # IoC container
│   └── lab_bootstrap.dart       # Demo registration bootstrap
├── models/                      # Shared data models
├── native/                      # Native bridging
│   ├── home_widget/             # Desktop widget
│   └── overlay/                 # Overlay service
├── providers/                   # Global state management
├── screens/                     # Screens/Pages
│   ├── chat/                    # AI chat & Agent chat
│   ├── gallery/                 # Gallery management
│   ├── home/                    # Home page
│   ├── lab/                     # Lab entry page
│   ├── native_controller/       # Native controller (media/notifications/system)
│   ├── profile/                 # Profile/Personal center
│   └── theme/                   # Theme settings
├── services/                    # Business services (API/Audio/Gallery/Messages, etc.)
├── utils/                       # Utility functions
├── widgets/                     # Common widgets (chat bubbles/Markdown/emojis, etc.)
└── generated/                   # Auto-generated OpenAPI code
    ├── api/                     # API clients
    ├── auth/                    # Authentication module
    └── model/                   # Data models
```

## Project Skill System (`.claude/skills/`)

Domain knowledge index used when Claude collaborates with the project. Uses a progressive `main SKILL.md + references/` structure organized by topic:

### Engineering Flow / Workflows

| Skill | Purpose |
|---|---|
| `flutter-work-flow` | Flutter main entry point; preferred for all Dart/Flutter issues |
| `flutter-add-page-workflow` | Workflow for adding new pages |
| `flutter-debug-logging` | Debugging errors/anomalous behavior (strategic logging) |
| `flutter-hive-workflow` | Hive storage management debugging & best practices |
| `flutter-message-workflow` | Adding new message types to the `message_strategy` system |
| `flutter-home-widget-realtime-sync` | Pushing real-time values to Android home widgets via `home_widget` |
| `lan-local-playbook` | LAN multiplayer development (`LanFramework` + `surround_game`) |
| `pr-workflow` | PR management workflow |
| `git-worktree-sync` | Syncing all `git worktree`s |
| `gh-upstream-release` | Fork mode: squash, push, and PR for release |

### Styling / UI

| Skill | Purpose |
|---|---|
| `styles-skill` | Flutter styling engineering main entry; includes refs for `banner-stretch`, `floating-pill-bottom-nav`, `border-emphasis-style`, `async-load-flag-pattern`, `lottery-workflow`, etc. |
| `rive-skills` | Comprehensive Rive animation platform (Luau/React/state machines) + specialized `rive ^0.14.5` Flutter DataBind for this project |

### Platform / Native

| Skill | Purpose |
|---|---|
| `android-media-projection-fix` | Android 14+ MediaProjection overlay screenshot; SOP for exception troubleshooting in `references/fgs-debug-cases.md` |
| `android-icon-processing` | Processing Android adaptive icon foreground (edge analysis/flood fill/island algorithm) |
| `webrtc-infrastructure` | WebRTC video calling + P2P real-time communication architecture |

### Architecture / Conventions

| Skill | Purpose |
|---|---|
| `api-module-auth` | `lib/api/` module conventions (directories as backend, deep dirs with light files, interceptor chains) |
| `block-note-core` | Block editor core architecture (Block models, RichText, editing strategies) |
| `knowledge-qa` | Deep search with `mmx` + writing knowledge Q&A documents |

### Meta Tools

| Skill | Purpose |
|---|---|
| `key_board_loop` | `loop` reflection mechanism (user privilege level) |
| `merge-skill` | Merging multiple skills into a unified document |

> For new skills, see `key_board_2`; for optimizing existing skill structures, see `key_board_3`.

## App Navigation

Bottom Navigation Bar (`XiaoDouZiBottomBar`, 5 slots + central "+" button):

| Index | Page                    | Description                                     |
| ----- | ----------------------- | ----------------------------------------------- |
| 0     | **ProfilePage**   | Profile/Personal center (default page)          |
| 1     | **HomePage**      | Chat home page                                  |
| 2     | **FocusHomePage** | Pomodoro timer (direct access via central "+" button) |
| 3     | **Placeholder**   | Local network discovery (in development)        |
| 4     | **Placeholder**   | Gallery management (in development)             |

- Supports deep linking `fr://lab` to directly open the Lab page
- Communicates with native Android via MethodChannel

## Development Guide

### Environment Requirements

- Dart SDK ^3.11.1
- No local Java/Android environment required
- All debugging is done via Web builds

### Build Commands

```bash
# Fetch dependencies
flutter pub get

# Web release build (primary verification method)
flutter build web --release

# Code analysis (checks for errors and orphaned files)
flutter analyze

# JSON serialization code generation
dart run build_runner build
```

### Workflow

1. After making code changes, run `flutter analyze | grep error` to verify no compilation errors
2. After passing compilation, individually `add` and `commit` modified files (do not use `add .`)
3. Push to GitHub to trigger the CI/CD pipeline and build the APK

## License

MIT

todo

* [ ] webrtc-demo
* [ ] udp opti
* [ ] Flutter package separation

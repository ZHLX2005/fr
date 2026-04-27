---
name: flutter-rive-workflow
description: Use when adding Rive animation demos to this Flutter project's lab module
---

# Flutter Rive Workflow

## Overview
Standard process for adding Rive animation demos to this project's lab/demo page architecture.

## When to Use
- Adding a new Rive animation demo page
- Loading a .riv file in this Flutter project
- Registering Rive demos in the lab module

## Core Pattern

### Step 1: Asset Placement
Place .riv file in `assets/rive/<animation-name>/` directory:
```
assets/rive/pendulum/pendulum.riv
```

### Step 2: Register Asset in pubspec.yaml
**Critical:** For directory assets, include trailing slash:
```yaml
assets:
  - assets/rive/smiley_stress_reliever.riv  # single file
  - assets/rive/pendulum/                    # directory with trailing slash
```

### Step 3: Create Demo Page
Create `lib/lab/demos/rive_<name>_demo.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;
import '../lab_container.dart';

class RiveNameDemo extends DemoPage {
  @override
  String get title => 'Rive Name';

  @override
  String get description => 'Description here';

  @override
  Widget buildPage(BuildContext context) {
    return const _RiveNamePage();
  }
}

class _RiveNamePage extends StatefulWidget {
  const _RiveNamePage();

  @override
  State<_RiveNamePage> createState() => _RiveNamePageState();
}

class _RiveNamePageState extends State<_RiveNamePage> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    'assets/rive/<name>/<name>.riv',
    riveFactory: rive.Factory.rive,
  );

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.08),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                Text(description, style: theme.textTheme.bodyMedium),
                Expanded(
                  child: rive.RiveWidgetBuilder(
                    fileLoader: _fileLoader,
                    builder: (context, state) => switch (state) {
                      rive.RiveLoading() => const Center(child: CircularProgressIndicator()),
                      rive.RiveFailed() => _RiveErrorView(error: state.error.toString()),
                      rive.RiveLoaded() => rive.RiveWidget(
                          controller: state.controller,
                          fit: rive.Fit.contain,
                        ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RiveErrorView extends StatelessWidget {
  final String error;
  const _RiveErrorView({required this.error});
  // ... error widget implementation
}

void registerRiveNameDemo() {
  demoRegistry.register(RiveNameDemo());
}
```

### Step 4: Register in lab_bootstrap.dart
```dart
import 'demos/rive_<name>_demo.dart';  // Add import

// In registerAllDemos():
registerRiveNameDemo();  // Add registration call
```

## Quick Reference

| Task | File | Key Point |
|------|------|-----------|
| Add asset | pubspec.yaml | Use trailing slash for directories |
| Load asset | FileLoader.fromAsset() | Path from assets root: `assets/rive/xxx/xxx.riv` |
| Display | RiveWidgetBuilder + RiveWidget | Handle Loading/Failed/Loaded states |
| Register | lab_bootstrap.dart | Add import + call register function |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Forgot to add asset path in pubspec.yaml | Add `assets/rive/<name>/` with trailing slash |
| Wrong asset path in FileLoader | Path starts from `assets/`, e.g., `assets/rive/pendulum/pendulum.riv` |
| Forgot to register demo | Both import AND registration call needed |
| Asset path typo | Verify file exists at `assets/rive/<name>/<name>.riv` |

## Verification
After implementation:
1. Run `flutter analyze lib/lab/demos/rive_<name>_demo.dart`
2. Commit and push to trigger GitHub pipeline
3. Verify asset loads correctly in app

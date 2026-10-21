# Rive Flutter Runtime Reference

> Official docs: https://rive.app/docs/runtimes/flutter/

## Overview

The Rive Flutter runtime provides native, high-performance Rive animation playback for Flutter applications on iOS, Android, macOS, Windows, Linux, and web.

## Installation

### pubspec.yaml

```yaml
dependencies:
  rive: ^0.13.0  # Check for latest version
```

```bash
flutter pub get
```

### iOS Minimum Version

Ensure `ios/Podfile` has:
```ruby
platform :ios, '14.0'
```

## Basic Usage

### Simple Animation

```dart
import 'package:rive/rive.dart';

class SimpleAnimation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/animation.riv',
      fit: BoxFit.cover,
    );
  }
}
```

### Network Animation

```dart
RiveAnimation.network(
  'https://example.com/animation.riv',
  fit: BoxFit.contain,
  placeHolder: CircularProgressIndicator(),
)
```

## Loading Methods

### Asset Loading

```dart
// From assets folder
RiveAnimation.asset('assets/animation.riv')

// With configuration
RiveAnimation.asset(
  'assets/button.riv',
  artboard: 'Button',           // Specific artboard
  animations: ['Idle'],          // Specific animations
  stateMachines: ['Controller'], // State machines
  fit: BoxFit.contain,
  alignment: Alignment.center,
  antialiasing: true,
)
```

### Network Loading

```dart
RiveAnimation.network(
  'https://cdn.example.com/animation.riv',
  placeHolder: Center(child: CircularProgressIndicator()),
  onInit: (artboard) => print('Loaded: ${artboard.name}'),
)
```

### Direct File

```dart
// From Uint8List
final bytes = await rootBundle.load('assets/animation.riv');
RiveAnimation.direct(
  bytes.buffer.asUint8List(),
)
```

## Controllers

### StateMachineController

```dart
class InteractiveAnimation extends StatefulWidget {
  @override
  _InteractiveAnimationState createState() => _InteractiveAnimationState();
}

class _InteractiveAnimationState extends State<InteractiveAnimation> {
  StateMachineController? _controller;
  SMIBool? _isHovered;
  SMITrigger? _onClick;

  void _onRiveInit(Artboard artboard) {
    final controller = StateMachineController.fromArtboard(
      artboard, 
      'ButtonController',
    );
    
    if (controller != null) {
      artboard.addController(controller);
      _controller = controller;
      
      // Get inputs
      _isHovered = controller.findInput<bool>('isHovered') as SMIBool?;
      _onClick = controller.findInput<bool>('onClick') as SMITrigger?;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _isHovered?.value = true,
      onExit: (_) => _isHovered?.value = false,
      child: GestureDetector(
        onTap: () => _onClick?.fire(),
        child: RiveAnimation.asset(
          'assets/button.riv',
          onInit: _onRiveInit,
        ),
      ),
    );
  }
}
```

### SimpleAnimation Controller

For basic playback control without state machines:

```dart
class ControlledAnimation extends StatefulWidget {
  @override
  _ControlledAnimationState createState() => _ControlledAnimationState();
}

class _ControlledAnimationState extends State<ControlledAnimation> {
  late RiveAnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SimpleAnimation('Idle');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/character.riv',
      controllers: [_controller],
    );
  }
}
```

### OneShotAnimation Controller

For animations that play once:

```dart
late RiveAnimationController _celebrateController;

@override
void initState() {
  super.initState();
  _celebrateController = OneShotAnimation(
    'Celebrate',
    autoplay: false,
    onStop: () => print('Animation finished'),
  );
}

void playCelebration() {
  _celebrateController.isActive = true;
}
```

## State Machine Inputs

### Input Types

| Type | Dart Class | Usage |
|------|------------|-------|
| Boolean | `SMIBool` | `input.value = true` |
| Number | `SMINumber` | `input.value = 42.0` |
| Trigger | `SMITrigger` | `input.fire()` |

### Getting Inputs

```dart
void _onRiveInit(Artboard artboard) {
  final controller = StateMachineController.fromArtboard(artboard, 'SM');
  artboard.addController(controller!);
  
  // By name
  final isActive = controller.findInput<bool>('isActive') as SMIBool?;
  final progress = controller.findInput<double>('progress') as SMINumber?;
  final trigger = controller.findInput<bool>('trigger') as SMITrigger?;
  
  // Alternative: getBool, getNumber, getTrigger
  final isActive2 = controller.getBool('isActive');
  final progress2 = controller.getNumber('progress');
}
```

### Using Inputs

```dart
// Boolean
_isActive?.value = true;
bool current = _isActive?.value ?? false;

// Number
_progress?.value = 0.75;
double current = _progress?.value ?? 0.0;

// Trigger (fire and forget)
_onClick?.fire();
```

## Rive Events

### Listening to Events

```dart
void _onRiveInit(Artboard artboard) {
  final controller = StateMachineController.fromArtboard(
    artboard, 
    'Main',
    onRiveEvent: _onRiveEvent,  // Event callback
  );
  artboard.addController(controller!);
}

void _onRiveEvent(RiveEvent event) {
  print('Event: ${event.name}');
  
  // Access custom properties
  if (event.properties != null) {
    final score = event.properties!['score'];
    final message = event.properties!['message'];
  }
  
  // Handle specific events
  switch (event.name) {
    case 'playSound':
      _audioPlayer.play(event.properties!['soundId']);
      break;
    case 'navigate':
      Navigator.pushNamed(context, event.properties!['route']);
      break;
  }
}
```

### Audio Events

```dart
void _onRiveEvent(RiveEvent event) {
  if (event is RiveAudioEvent) {
    // Audio-specific properties
    print('Audio asset: ${event.audioAsset}');
    print('Volume: ${event.volume}');
    
    // Custom audio handling
    _playAudio(event.audioAsset, volume: event.volume);
  }
}
```

## Text Runs

### Updating Text

```dart
class DynamicText extends StatefulWidget {
  final String message;
  
  const DynamicText({required this.message});
  
  @override
  _DynamicTextState createState() => _DynamicTextState();
}

class _DynamicTextState extends State<DynamicText> {
  Artboard? _artboard;
  TextValueRun? _textRun;

  void _onRiveInit(Artboard artboard) {
    _artboard = artboard;
    _textRun = artboard.textRun('messageText');
    _updateText();
    
    final controller = StateMachineController.fromArtboard(artboard, 'Main');
    artboard.addController(controller!);
  }

  void _updateText() {
    _textRun?.text = widget.message;
  }

  @override
  void didUpdateWidget(DynamicText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _updateText();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/banner.riv',
      onInit: _onRiveInit,
    );
  }
}
```

## Data Binding / View Models

### Accessing View Models

```dart
void _onRiveInit(Artboard artboard) {
  final controller = StateMachineController.fromArtboard(artboard, 'Main');
  artboard.addController(controller!);
  
  // Get View Model instance
  final viewModel = controller.viewModelInstance('UserVM');
  
  // Set properties
  viewModel?.setString('username', 'John');
  viewModel?.setNumber('score', 100.0);
  viewModel?.setBoolean('isActive', true);
  
  // Get properties
  final username = viewModel?.getString('username');
  final score = viewModel?.getNumber('score');
}
```

## Layout and Sizing

### Fit Options

```dart
RiveAnimation.asset(
  'assets/animation.riv',
  fit: BoxFit.contain,  // Standard Flutter BoxFit
)

// Options:
// BoxFit.contain - Fit inside, maintain aspect ratio
// BoxFit.cover - Fill, may crop
// BoxFit.fill - Stretch to fill
// BoxFit.fitWidth - Match width
// BoxFit.fitHeight - Match height
// BoxFit.none - No scaling
// BoxFit.scaleDown - Contain only if larger
```

### Alignment

```dart
RiveAnimation.asset(
  'assets/animation.riv',
  alignment: Alignment.center,  // Standard Flutter Alignment
)
```

### Constrained Sizing

```dart
SizedBox(
  width: 200,
  height: 200,
  child: RiveAnimation.asset('assets/icon.riv'),
)

// Or with AspectRatio
AspectRatio(
  aspectRatio: 16 / 9,
  child: RiveAnimation.asset('assets/banner.riv'),
)
```

## Hit Testing & Interaction

### GestureDetector Wrapper

```dart
GestureDetector(
  onTap: () => _triggerInput?.fire(),
  onTapDown: (_) => _isPressedInput?.value = true,
  onTapUp: (_) => _isPressedInput?.value = false,
  onTapCancel: () => _isPressedInput?.value = false,
  child: RiveAnimation.asset(
    'assets/button.riv',
    onInit: _onRiveInit,
  ),
)
```

### MouseRegion for Hover

```dart
MouseRegion(
  onEnter: (_) => _isHoveredInput?.value = true,
  onExit: (_) => _isHoveredInput?.value = false,
  child: GestureDetector(
    onTap: () => _onClickInput?.fire(),
    child: RiveAnimation.asset(
      'assets/button.riv',
      onInit: _onRiveInit,
    ),
  ),
)
```

### Built-in Hit Testing

Rive handles hit testing for Listeners defined in the file:

```dart
RiveAnimation.asset(
  'assets/interactive.riv',
  stateMachines: ['Main'],
  // Rive automatically handles pointer events for Listeners
)
```

## Error Handling

### Load Errors

```dart
RiveAnimation.network(
  'https://example.com/animation.riv',
  placeHolder: Center(child: CircularProgressIndicator()),
  onInit: (artboard) {
    // Success
  },
)

// Or with try-catch for manual loading
try {
  final bytes = await rootBundle.load('assets/animation.riv');
  final file = RiveFile.import(bytes);
} catch (e) {
  print('Failed to load Rive file: $e');
}
```

### Missing State Machine/Artboard

```dart
void _onRiveInit(Artboard artboard) {
  final controller = StateMachineController.fromArtboard(artboard, 'Main');
  
  if (controller == null) {
    print('State machine "Main" not found');
    return;
  }
  
  artboard.addController(controller);
}
```

## Performance Optimization

### Antialiasing

```dart
RiveAnimation.asset(
  'assets/animation.riv',
  antialiasing: false,  // Disable for better performance on simple graphics
)
```

### Controller Disposal

```dart
@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

### Pausing Off-Screen

```dart
class OptimizedAnimation extends StatefulWidget {
  @override
  _OptimizedAnimationState createState() => _OptimizedAnimationState();
}

class _OptimizedAnimationState extends State<OptimizedAnimation> 
    with WidgetsBindingObserver {
  RiveAnimationController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause when app is backgrounded
    _controller?.isActive = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/animation.riv',
      controllers: [_controller!],
    );
  }
}
```

## Multiple Artboards

### Switching Artboards

```dart
class MultiArtboard extends StatefulWidget {
  @override
  _MultiArtboardState createState() => _MultiArtboardState();
}

class _MultiArtboardState extends State<MultiArtboard> {
  String _currentArtboard = 'Artboard1';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RiveAnimation.asset(
            'assets/multi.riv',
            artboard: _currentArtboard,
            key: ValueKey(_currentArtboard), // Force rebuild
          ),
        ),
        Row(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _currentArtboard = 'Artboard1'),
              child: Text('Artboard 1'),
            ),
            ElevatedButton(
              onPressed: () => setState(() => _currentArtboard = 'Artboard2'),
              child: Text('Artboard 2'),
            ),
          ],
        ),
      ],
    );
  }
}
```

## Common Patterns

### Animated Icon Button

```dart
class AnimatedIconButton extends StatefulWidget {
  final VoidCallback onPressed;
  
  const AnimatedIconButton({required this.onPressed});
  
  @override
  _AnimatedIconButtonState createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<AnimatedIconButton> {
  SMIBool? _isHovered;
  SMITrigger? _onClick;

  void _onInit(Artboard artboard) {
    final controller = StateMachineController.fromArtboard(artboard, 'Button');
    artboard.addController(controller!);
    _isHovered = controller.findInput('isHovered') as SMIBool?;
    _onClick = controller.findInput('onClick') as SMITrigger?;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _isHovered?.value = true,
      onExit: (_) => _isHovered?.value = false,
      child: GestureDetector(
        onTap: () {
          _onClick?.fire();
          widget.onPressed();
        },
        child: SizedBox(
          width: 48,
          height: 48,
          child: RiveAnimation.asset(
            'assets/icon_button.riv',
            onInit: _onInit,
          ),
        ),
      ),
    );
  }
}
```

### Loading Indicator

```dart
class RiveLoadingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: RiveAnimation.asset(
        'assets/loading.riv',
        fit: BoxFit.contain,
      ),
    );
  }
}
```

## See Also

- [Rive State Machine](./rive-state-machine.md)
- [Rive Events](./rive-events.md)
- [Rive Data Binding](./rive-data-binding.md)

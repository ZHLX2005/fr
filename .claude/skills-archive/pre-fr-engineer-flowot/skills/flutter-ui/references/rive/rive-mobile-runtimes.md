# Rive Mobile Runtimes Reference

> Official docs: 
> - iOS/Apple: https://rive.app/docs/runtimes/apple/
> - Android: https://rive.app/docs/runtimes/android/
> - React Native: https://rive.app/docs/runtimes/react-native/

## Overview

Rive provides native runtimes for mobile platforms with high-performance rendering and platform-specific APIs.

---

# iOS / Apple Platforms

## Installation

### Swift Package Manager

1. Xcode → File → Add Packages
2. Enter: `https://github.com/rive-app/rive-ios`
3. Select version and add to target

### CocoaPods

```ruby
# Podfile
pod 'RiveRuntime', '~> 5.0'
```

```bash
pod install
```

## Basic Usage

### SwiftUI

```swift
import SwiftUI
import RiveRuntime

struct ContentView: View {
    var body: some View {
        RiveViewModel(fileName: "animation").view()
    }
}
```

### UIKit

```swift
import UIKit
import RiveRuntime

class ViewController: UIViewController {
    var riveView: RiveView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        riveView = RiveView()
        riveView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(riveView)
        
        NSLayoutConstraint.activate([
            riveView.topAnchor.constraint(equalTo: view.topAnchor),
            riveView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            riveView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            riveView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        // Load animation
        let model = RiveModel(fileName: "animation")
        riveView.configure(model)
    }
}
```

## RiveViewModel (SwiftUI)

### Full Configuration

```swift
import RiveRuntime

struct AnimatedView: View {
    @StateObject var viewModel = RiveViewModel(
        fileName: "button",
        stateMachineName: "Button State Machine",
        fit: .contain,
        alignment: .center,
        autoPlay: true
    )
    
    var body: some View {
        viewModel.view()
            .onTapGesture {
                viewModel.triggerInput("onClick")
            }
    }
}
```

### State Machine Inputs

```swift
@StateObject var viewModel = RiveViewModel(fileName: "interactive")

// Boolean
viewModel.setInput("isHovered", value: true)

// Number  
viewModel.setInput("progress", value: 0.75)

// Trigger
viewModel.triggerInput("onClick")
```

### Rive Events

```swift
class MyViewModel: RiveViewModel {
    override init(fileName: String) {
        super.init(fileName: fileName, stateMachineName: "Main")
    }
    
    @RiveEvent("onComplete") 
    func handleComplete(_ event: RiveEvent) {
        print("Animation complete!")
    }
    
    @RiveEvent("playSound")
    func handleSound(_ event: RiveEvent) {
        let soundId = event.properties["soundId"] as? String
        AudioPlayer.play(soundId)
    }
}
```

### Text Runs

```swift
viewModel.setTextRunValue("username", textValue: "John Doe")
```

## Layout Options

### Fit

```swift
RiveViewModel(fileName: "animation", fit: .contain)

// Options:
// .contain - Fit inside, maintain aspect ratio
// .cover - Fill, may crop  
// .fill - Stretch to fill
// .fitWidth - Match width
// .fitHeight - Match height
// .none - No scaling
// .scaleDown - Contain only if larger
```

### Alignment

```swift
RiveViewModel(fileName: "animation", alignment: .center)

// Options: .topLeft, .topCenter, .topRight,
//          .centerLeft, .center, .centerRight,
//          .bottomLeft, .bottomCenter, .bottomRight
```

---

# Android

## Installation

### Gradle (Kotlin DSL)

```kotlin
// build.gradle.kts (app)
dependencies {
    implementation("app.rive:rive-android:9.0.0")
}
```

### Gradle (Groovy)

```groovy
// build.gradle (app)
dependencies {
    implementation 'app.rive:rive-android:9.0.0'
}
```

## Basic Usage

### XML Layout

```xml
<!-- activity_main.xml -->
<app.rive.runtime.kotlin.RiveAnimationView
    android:id="@+id/riveView"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    app:riveResource="@raw/animation"
    app:riveAutoPlay="true" />
```

### Kotlin

```kotlin
import app.rive.runtime.kotlin.RiveAnimationView

class MainActivity : AppCompatActivity() {
    private lateinit var riveView: RiveAnimationView
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        riveView = findViewById(R.id.riveView)
    }
}
```

### Jetpack Compose

```kotlin
import app.rive.runtime.kotlin.RiveAnimationView

@Composable
fun RiveAnimation() {
    AndroidView(
        factory = { context ->
            RiveAnimationView(context).apply {
                setRiveResource(R.raw.animation)
                autoplay = true
            }
        },
        modifier = Modifier.fillMaxSize()
    )
}
```

## State Machine Control

### Getting Inputs

```kotlin
riveView.setRiveResource(R.raw.button)
riveView.autoplay = true

// Wait for load
riveView.registerListener(object : RiveFileController.Listener {
    override fun notifyLoop(animation: PlayableInstance) {}
    override fun notifyPause(animation: PlayableInstance) {}
    override fun notifyPlay(animation: PlayableInstance) {}
    override fun notifyStateChanged(stateMachineName: String, stateName: String) {}
    override fun notifyStop(animation: PlayableInstance) {}
})
```

### Setting Inputs

```kotlin
// Boolean
riveView.setBooleanState("ButtonController", "isHovered", true)

// Number
riveView.setNumberState("ProgressController", "progress", 0.75f)

// Trigger
riveView.fireState("ButtonController", "onClick")
```

## Rive Events

```kotlin
riveView.addEventListener(object : RiveEventListener {
    override fun notifyEvent(event: RiveEvent) {
        Log.d("Rive", "Event: ${event.name}")
        
        // Access properties
        event.properties["score"]?.let { score ->
            updateScore(score as Number)
        }
    }
})
```

## Text Runs

```kotlin
riveView.setTextRunValue("username", "John Doe")
```

## Layout Options

### XML Attributes

```xml
<app.rive.runtime.kotlin.RiveAnimationView
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    app:riveResource="@raw/animation"
    app:riveFit="CONTAIN"
    app:riveAlignment="CENTER"
    app:riveAutoPlay="true"
    app:riveStateMachine="Main" />
```

### Programmatic

```kotlin
riveView.fit = Fit.CONTAIN
riveView.alignment = Alignment.CENTER
```

---

# React Native

## Installation

```bash
npm install rive-react-native

# iOS
cd ios && pod install
```

### Expo

```bash
npx expo install rive-react-native
```

## Basic Usage

```tsx
import Rive from 'rive-react-native';

function App() {
  return (
    <Rive
      resourceName="animation"  // From res/raw (Android) or assets (iOS)
      style={{ width: 300, height: 300 }}
      autoplay={true}
    />
  );
}
```

### Loading from URL

```tsx
<Rive
  url="https://example.com/animation.riv"
  style={{ width: 300, height: 300 }}
  autoplay={true}
/>
```

## Ref Methods

```tsx
import { useRef } from 'react';
import Rive, { RiveRef } from 'rive-react-native';

function InteractiveAnimation() {
  const riveRef = useRef<RiveRef>(null);

  const handlePress = () => {
    riveRef.current?.fireState('Main', 'onClick');
  };

  return (
    <Pressable onPress={handlePress}>
      <Rive
        ref={riveRef}
        resourceName="button"
        stateMachineName="Main"
        style={{ width: 200, height: 60 }}
      />
    </Pressable>
  );
}
```

### Available Ref Methods

| Method | Description |
|--------|-------------|
| `play()` | Play animation |
| `pause()` | Pause animation |
| `stop()` | Stop animation |
| `reset()` | Reset to initial state |
| `fireState(sm, trigger)` | Fire trigger input |
| `setBooleanState(sm, name, value)` | Set boolean input |
| `setNumberState(sm, name, value)` | Set number input |
| `setTextRunValue(name, text)` | Update text run |

## State Machine Inputs

```tsx
const riveRef = useRef<RiveRef>(null);

// Boolean
riveRef.current?.setBooleanState('Controller', 'isActive', true);

// Number
riveRef.current?.setNumberState('Controller', 'progress', 0.5);

// Trigger
riveRef.current?.fireState('Controller', 'onClick');
```

## Props Reference

| Prop | Type | Description |
|------|------|-------------|
| `resourceName` | string | Asset name (no extension) |
| `url` | string | Remote .riv URL |
| `artboardName` | string | Specific artboard |
| `animationName` | string | Specific animation |
| `stateMachineName` | string | State machine to use |
| `autoplay` | boolean | Auto-start playback |
| `fit` | Fit | Scale behavior |
| `alignment` | Alignment | Position in container |
| `style` | ViewStyle | Container styles |

### Fit Options

```tsx
import { Fit } from 'rive-react-native';

<Rive fit={Fit.Contain} />

// Options:
// Fit.Cover
// Fit.Contain  
// Fit.Fill
// Fit.FitWidth
// Fit.FitHeight
// Fit.None
// Fit.ScaleDown
```

### Alignment Options

```tsx
import { Alignment } from 'rive-react-native';

<Rive alignment={Alignment.Center} />

// Options:
// Alignment.TopLeft, TopCenter, TopRight
// Alignment.CenterLeft, Center, CenterRight
// Alignment.BottomLeft, BottomCenter, BottomRight
```

## Event Callbacks

```tsx
<Rive
  resourceName="game"
  stateMachineName="Main"
  onPlay={() => console.log('Playing')}
  onPause={() => console.log('Paused')}
  onStop={() => console.log('Stopped')}
  onLoopEnd={() => console.log('Loop ended')}
  onStateChanged={(stateMachine, state) => {
    console.log(`State: ${state} in ${stateMachine}`);
  }}
  onRiveEventReceived={(event) => {
    console.log('Event:', event.name, event.properties);
  }}
/>
```

## Platform-Specific Setup

### iOS

Add .riv files to Xcode project assets or bundle resources.

### Android

Place .riv files in `android/app/src/main/res/raw/`.

### Expo

```bash
# Place in assets folder
npx expo prebuild
```

## Troubleshooting

### Animation Not Showing (React Native)

1. Verify file is in correct platform folder
2. Check resource name matches file (without .riv)
3. Rebuild native app after adding files

### iOS Build Errors

1. Run `pod install` after adding package
2. Check minimum iOS version (14.0+)

### Android Build Errors

1. Sync Gradle after adding dependency
2. Check minSdk version (21+)

---

## See Also

- [Rive State Machine](./rive-state-machine.md)
- [Rive Events](./rive-events.md)
- [Rive Data Binding](./rive-data-binding.md)

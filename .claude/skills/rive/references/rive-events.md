# Rive Events Reference

> Official docs: https://rive.app/docs/editor/events/

## Overview

**Rive Events** enable communication from Rive animations to your application code. They fire at specific moments during animation playback, allowing you to trigger app-side logic like sounds, analytics, navigation, or state changes.

## Types of Events

| Type | Purpose | Example Use |
|------|---------|-------------|
| **General Event** | Signal to app code | Analytics, navigation |
| **Audio Event** | Play embedded audio | Sound effects, music |
| **Custom Properties** | Pass data with event | Score values, IDs |

## Creating Events

### In the Editor

1. Open **State Machine** editor
2. Select a state or timeline
3. In Inspector, find **Events** section
4. Click **+** to add event
5. Name the event (e.g., "onComplete", "playSound")

### Event Placement

Events can be placed on:
- **Timeline keyframes**: Fire at specific frame
- **State entry**: Fire when entering a state
- **State exit**: Fire when leaving a state
- **Transitions**: Fire during transition

## Event Properties

### Basic Properties

| Property | Description |
|----------|-------------|
| **Name** | Identifier used in runtime code |
| **Type** | General or Audio |

### Custom Properties

Add data to events:

| Property Type | Example |
|---------------|---------|
| **Number** | `score: 100` |
| **String** | `message: "Level Complete"` |
| **Boolean** | `success: true` |

## Audio Events

### Importing Audio

1. Drag audio file into Rive (MP3, WAV, OGG)
2. Audio appears in Assets panel
3. Create Audio Event and link the asset

### Audio Event Properties

| Property | Description |
|----------|-------------|
| **Asset** | Which audio file to play |
| **Volume** | 0.0 to 1.0 |
| **Loop** | Repeat playback |

### Supported Formats

| Format | Support |
|--------|---------|
| MP3 | ✅ All platforms |
| WAV | ✅ All platforms |
| OGG | ✅ Most platforms |
| AAC | ⚠️ Platform-dependent |

## Runtime Event Handling

### JavaScript/Web

```javascript
import { Rive } from '@rive-app/canvas';

const rive = new Rive({
  src: 'animation.riv',
  canvas: document.getElementById('canvas'),
  stateMachines: 'State Machine 1',
  autoplay: true,
  onLoad: () => {
    // Listen to all Rive events
    rive.on('riveevent', (event) => {
      console.log('Event fired:', event.data.name);
      
      // Access custom properties
      if (event.data.properties) {
        console.log('Properties:', event.data.properties);
      }
    });
  }
});

// Alternative: specific event handling
rive.on('riveevent', (event) => {
  switch (event.data.name) {
    case 'onButtonClick':
      handleButtonClick();
      break;
    case 'onLevelComplete':
      const score = event.data.properties?.score;
      handleLevelComplete(score);
      break;
    case 'playExplosion':
      playSound('explosion.mp3');
      break;
  }
});
```

### React

```tsx
import { useRive } from '@rive-app/react-canvas';
import { useEffect } from 'react';

function GameAnimation() {
  const { rive, RiveComponent } = useRive({
    src: 'game.riv',
    stateMachines: 'Game State Machine',
    autoplay: true,
  });

  useEffect(() => {
    if (!rive) return;

    const handleRiveEvent = (event: any) => {
      const eventName = event.data.name;
      const properties = event.data.properties;

      switch (eventName) {
        case 'scoreUpdated':
          updateScore(properties.score);
          break;
        case 'gameOver':
          showGameOverScreen(properties.finalScore);
          break;
        case 'playSound':
          playAudio(properties.soundId);
          break;
      }
    };

    rive.on('riveevent', handleRiveEvent);

    return () => {
      rive.off('riveevent', handleRiveEvent);
    };
  }, [rive]);

  return <RiveComponent />;
}
```

### React with Callback Prop

```tsx
import { Rive } from '@rive-app/react-canvas';

function AnimatedButton({ onAction }: { onAction: () => void }) {
  return (
    <Rive
      src="button.riv"
      stateMachines="Button"
      onRiveEventReceived={(event) => {
        if (event.data.name === 'buttonPressed') {
          onAction();
        }
      }}
    />
  );
}
```

### Flutter

```dart
import 'package:rive/rive.dart';

class MyRiveWidget extends StatefulWidget {
  @override
  _MyRiveWidgetState createState() => _MyRiveWidgetState();
}

class _MyRiveWidgetState extends State<MyRiveWidget> {
  void _onRiveEvent(RiveEvent event) {
    print('Rive event: ${event.name}');
    
    // Handle specific events
    if (event.name == 'playSound') {
      // Play audio
      _audioPlayer.play('assets/sounds/${event.properties['soundId']}.mp3');
    } else if (event.name == 'navigate') {
      // Navigate to another screen
      Navigator.pushNamed(context, event.properties['route']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/animation.riv',
      stateMachines: ['State Machine 1'],
      onInit: (artboard) {
        final controller = StateMachineController.fromArtboard(
          artboard,
          'State Machine 1',
          onRiveEvent: _onRiveEvent,
        );
        artboard.addController(controller!);
      },
    );
  }
}
```

### Unity (C#)

```csharp
using Rive;
using UnityEngine;

public class RiveEventHandler : MonoBehaviour
{
    private RiveWidget riveWidget;

    void Start()
    {
        riveWidget = GetComponent<RiveWidget>();
        riveWidget.OnRiveEvent += HandleRiveEvent;
    }

    void HandleRiveEvent(RiveEvent riveEvent)
    {
        Debug.Log($"Rive Event: {riveEvent.Name}");

        switch (riveEvent.Name)
        {
            case "playSound":
                string soundId = riveEvent.GetString("soundId");
                AudioManager.Instance.PlaySound(soundId);
                break;
                
            case "dealDamage":
                float damage = riveEvent.GetNumber("amount");
                GameManager.Instance.DealDamage(damage);
                break;
                
            case "showDialog":
                string message = riveEvent.GetString("message");
                UIManager.Instance.ShowDialog(message);
                break;
        }
    }

    void OnDestroy()
    {
        if (riveWidget != null)
        {
            riveWidget.OnRiveEvent -= HandleRiveEvent;
        }
    }
}
```

## Audio Event Handling

### Web - Built-in Audio

Rive Web runtime can play audio events automatically:

```javascript
const rive = new Rive({
  src: 'animation.riv',
  canvas: document.getElementById('canvas'),
  stateMachines: 'State Machine 1',
  autoplay: true,
  enableRiveAudio: true, // Enable built-in audio playback
});
```

### Web - Custom Audio Handling

For more control, handle audio events manually:

```javascript
rive.on('riveevent', (event) => {
  if (event.data.type === 'audio') {
    // Custom audio handling
    const audioContext = new AudioContext();
    // ... custom audio logic
  }
});
```

### Flutter - Audio Events

```dart
void _onRiveEvent(RiveEvent event) {
  if (event is RiveAudioEvent) {
    // Audio events have additional properties
    print('Audio asset: ${event.audioAsset}');
    print('Volume: ${event.volume}');
    
    // Play with custom audio player if needed
    _playCustomAudio(event.audioAsset, event.volume);
  }
}
```

## Event Timing

### Frame-Accurate Events

Events on timeline keyframes fire at the exact frame:

```
Timeline: [----*----*----*----]
                ↑    ↑    ↑
             Event Event Event
             @10   @20   @30
```

### State Events

| Timing | When Fires |
|--------|------------|
| **On Enter** | Immediately when state becomes active |
| **On Exit** | Just before leaving state |
| **During** | At keyframe within state's animation |

## Common Patterns

### Progress Tracking

```javascript
// In Rive: Add events at 25%, 50%, 75%, 100% of animation

rive.on('riveevent', (event) => {
  switch (event.data.name) {
    case 'progress25':
      updateProgress(25);
      break;
    case 'progress50':
      updateProgress(50);
      break;
    case 'progress75':
      updateProgress(75);
      break;
    case 'complete':
      updateProgress(100);
      onAnimationComplete();
      break;
  }
});
```

### Sound Effects Sync

```javascript
// Rive events: "footstep", "jump", "land"

rive.on('riveevent', (event) => {
  const sounds = {
    footstep: 'step.mp3',
    jump: 'whoosh.mp3',
    land: 'thud.mp3',
  };
  
  const soundFile = sounds[event.data.name];
  if (soundFile) {
    playSound(soundFile, event.data.properties?.volume ?? 1.0);
  }
});
```

### Analytics Integration

```javascript
rive.on('riveevent', (event) => {
  // Track all Rive events in analytics
  analytics.track('rive_event', {
    event_name: event.data.name,
    ...event.data.properties,
    timestamp: Date.now(),
  });
});
```

### Modal/Dialog Triggers

```tsx
function InteractiveAnimation() {
  const [showModal, setShowModal] = useState(false);
  const [modalContent, setModalContent] = useState('');

  const { RiveComponent } = useRive({
    src: 'interactive.riv',
    stateMachines: 'Main',
    autoplay: true,
  });

  useEffect(() => {
    rive?.on('riveevent', (event) => {
      if (event.data.name === 'showInfo') {
        setModalContent(event.data.properties.content);
        setShowModal(true);
      }
    });
  }, [rive]);

  return (
    <>
      <RiveComponent />
      {showModal && <Modal content={modalContent} onClose={() => setShowModal(false)} />}
    </>
  );
}
```

## Best Practices

### Naming Conventions

```
✅ Good names:
- onButtonClick
- playFootstep
- levelComplete
- showTutorial

❌ Avoid:
- event1
- e
- click
```

### Event Granularity

```
✅ Specific events:
- playWalkSound
- playJumpSound
- playLandSound

🤔 Consider consolidating:
- playSound (with soundId property)
```

### Performance

- Events have minimal overhead
- Audio events may have loading latency on first play
- Preload audio assets when possible

### Debugging

```javascript
// Log all events during development
rive.on('riveevent', (event) => {
  console.log('[Rive Event]', {
    name: event.data.name,
    type: event.data.type,
    properties: event.data.properties,
  });
});
```

## Troubleshooting

### Events Not Firing

1. Verify state machine is playing (`autoplay: true`)
2. Check event is on active state/timeline
3. Ensure event listener is registered after `onLoad`

### Audio Not Playing

1. Check `enableRiveAudio: true` for built-in playback
2. Verify audio asset is embedded in .riv file
3. Check browser autoplay policies (may require user interaction)

### Missing Properties

1. Verify properties are defined in Rive editor
2. Check property names match exactly (case-sensitive)
3. Access via `event.data.properties.propertyName`

## See Also

- [Rive State Machine](./rive-state-machine.md)
- [Rive Data Binding](./rive-data-binding.md)
- [Rive React Runtime](./rive-react-runtime.md)

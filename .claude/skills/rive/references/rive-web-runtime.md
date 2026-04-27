# Rive Web (JS) Runtime Reference

> Official docs: https://rive.app/docs/runtimes/web/

## Overview

The Rive Web runtime provides direct JavaScript/TypeScript access to Rive animations without framework dependencies. For React-specific usage, see [Rive React Runtime](./rive-react-runtime.md).

## Installation

### NPM Packages

| Package | Renderer | Use Case |
|---------|----------|----------|
| `@rive-app/canvas` | Canvas 2D + WebGL | Recommended default |
| `@rive-app/webgl` | WebGL only | Best performance |
| `@rive-app/canvas-lite` | Canvas 2D only | Smaller bundle, no WebGL |
| `@rive-app/webgl2` | WebGL 2 | Advanced features |

```bash
# Recommended
npm install @rive-app/canvas

# WebGL only (best performance)
npm install @rive-app/webgl

# Smallest bundle (Canvas 2D only)
npm install @rive-app/canvas-lite
```

### CDN

```html
<script src="https://unpkg.com/@rive-app/canvas@latest"></script>
<script>
  const rive = new rive.Rive({
    src: 'animation.riv',
    canvas: document.getElementById('canvas'),
    autoplay: true,
  });
</script>
```

## Basic Setup

### Minimal Example

```html
<canvas id="canvas" width="500" height="500"></canvas>

<script type="module">
  import { Rive } from '@rive-app/canvas';

  const riveInstance = new Rive({
    src: 'animation.riv',
    canvas: document.getElementById('canvas'),
    autoplay: true,
  });
</script>
```

### TypeScript

```typescript
import { Rive, Layout, Fit, Alignment } from '@rive-app/canvas';

const riveInstance = new Rive({
  src: 'animation.riv',
  canvas: document.getElementById('canvas') as HTMLCanvasElement,
  autoplay: true,
  layout: new Layout({
    fit: Fit.Contain,
    alignment: Alignment.Center,
  }),
  onLoad: () => {
    console.log('Rive loaded');
  },
});
```

## Constructor Options

### Rive Configuration

| Option | Type | Description |
|--------|------|-------------|
| `src` | string | URL to .riv file |
| `buffer` | ArrayBuffer | .riv file as buffer |
| `canvas` | HTMLCanvasElement | Target canvas |
| `artboard` | string | Artboard name (optional) |
| `animations` | string[] | Animation names to play |
| `stateMachines` | string[] | State machine names |
| `autoplay` | boolean | Start playing immediately |
| `layout` | Layout | Fit and alignment |
| `useOffscreenRenderer` | boolean | Use OffscreenCanvas |
| `enableRiveAssetCDN` | boolean | Load assets from CDN |

### Layout Options

```typescript
import { Layout, Fit, Alignment } from '@rive-app/canvas';

const layout = new Layout({
  fit: Fit.Contain,      // How to fit in canvas
  alignment: Alignment.Center,  // Position in canvas
  minX: 0,               // Viewport bounds
  minY: 0,
  maxX: 500,
  maxY: 500,
});
```

### Fit Options

| Fit | Behavior |
|-----|----------|
| `Fit.Cover` | Fill canvas, may crop |
| `Fit.Contain` | Fit inside, may letterbox |
| `Fit.Fill` | Stretch to fill exactly |
| `Fit.FitWidth` | Match width, scale height |
| `Fit.FitHeight` | Match height, scale width |
| `Fit.None` | No scaling |
| `Fit.ScaleDown` | Contain only if larger |

### Alignment Options

| Alignment | Position |
|-----------|----------|
| `Alignment.Center` | Center |
| `Alignment.TopLeft` | Top-left corner |
| `Alignment.TopCenter` | Top center |
| `Alignment.TopRight` | Top-right corner |
| `Alignment.CenterLeft` | Center left |
| `Alignment.CenterRight` | Center right |
| `Alignment.BottomLeft` | Bottom-left corner |
| `Alignment.BottomCenter` | Bottom center |
| `Alignment.BottomRight` | Bottom-right corner |

## Loading Files

### From URL

```typescript
const rive = new Rive({
  src: 'https://example.com/animation.riv',
  canvas: document.getElementById('canvas'),
  autoplay: true,
});
```

### From ArrayBuffer

```typescript
// Fetch as buffer
const response = await fetch('animation.riv');
const buffer = await response.arrayBuffer();

const rive = new Rive({
  buffer: buffer,
  canvas: document.getElementById('canvas'),
  autoplay: true,
});
```

### From Base64

```typescript
function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

const rive = new Rive({
  buffer: base64ToArrayBuffer(base64String),
  canvas: document.getElementById('canvas'),
  autoplay: true,
});
```

## Lifecycle Callbacks

```typescript
const rive = new Rive({
  src: 'animation.riv',
  canvas: document.getElementById('canvas'),
  
  onLoad: () => {
    console.log('File loaded, ready to play');
  },
  
  onLoadError: (error) => {
    console.error('Failed to load:', error);
  },
  
  onPlay: (event) => {
    console.log('Started playing:', event.data);
  },
  
  onPause: (event) => {
    console.log('Paused:', event.data);
  },
  
  onStop: (event) => {
    console.log('Stopped:', event.data);
  },
  
  onLoop: (event) => {
    console.log('Looped:', event.data);
  },
  
  onStateChange: (event) => {
    console.log('State changed:', event.data);
  },
});
```

## Playback Control

### Basic Controls

```typescript
const rive = new Rive({ /* config */ });

// Play/Pause/Stop
rive.play();
rive.pause();
rive.stop();

// Play specific animations
rive.play('Idle');
rive.play(['Walk', 'Wave']); // Multiple

// Check state
const isPlaying = rive.isPlaying;
const isPaused = rive.isPaused;
```

### Playback Speed

```typescript
// Get/set playback speed
rive.playbackSpeed = 0.5;  // Half speed
rive.playbackSpeed = 2.0;  // Double speed
rive.playbackSpeed = -1.0; // Reverse
```

### Scrubbing

```typescript
// Set animation time directly
rive.scrub('AnimationName', 0.5); // 50% through animation
```

## State Machine Control

### Getting Inputs

```typescript
const rive = new Rive({
  src: 'button.riv',
  canvas: document.getElementById('canvas'),
  stateMachines: 'Button',
  autoplay: true,
  onLoad: () => {
    const inputs = rive.stateMachineInputs('Button');
    
    // List all inputs
    inputs.forEach(input => {
      console.log(input.name, input.type);
    });
  },
});
```

### Setting Input Values

```typescript
const inputs = rive.stateMachineInputs('StateMachine');

// Boolean
const isHovered = inputs.find(i => i.name === 'isHovered');
isHovered.value = true;

// Number
const progress = inputs.find(i => i.name === 'progress');
progress.value = 0.75;

// Trigger
const onClick = inputs.find(i => i.name === 'onClick');
onClick.fire();
```

### Input Types

```typescript
import { StateMachineInputType } from '@rive-app/canvas';

const inputs = rive.stateMachineInputs('SM');

inputs.forEach(input => {
  switch (input.type) {
    case StateMachineInputType.Boolean:
      input.value = true; // Set boolean
      break;
    case StateMachineInputType.Number:
      input.value = 42; // Set number
      break;
    case StateMachineInputType.Trigger:
      input.fire(); // Fire trigger
      break;
  }
});
```

## Event Handling

### Rive Events

```typescript
const rive = new Rive({
  src: 'interactive.riv',
  canvas: document.getElementById('canvas'),
  stateMachines: 'Main',
  autoplay: true,
});

// Listen to all Rive events
rive.on('riveevent', (event) => {
  console.log('Event:', event.data.name);
  console.log('Properties:', event.data.properties);
});

// Multiple event types
rive.on('play', () => console.log('Playing'));
rive.on('pause', () => console.log('Paused'));
rive.on('statechange', (event) => console.log('State:', event.data));
```

### Removing Listeners

```typescript
const handler = (event) => console.log(event);

rive.on('riveevent', handler);

// Remove specific listener
rive.off('riveevent', handler);

// Remove all listeners for event type
rive.removeAllRiveEventListeners('riveevent');
```

## Pointer Events

### Mouse/Touch Interaction

```typescript
const canvas = document.getElementById('canvas');
const rive = new Rive({
  src: 'button.riv',
  canvas: canvas,
  stateMachines: 'Button',
  autoplay: true,
});

// Rive handles events if state machine has listeners
// But you can also manually forward events:

canvas.addEventListener('mousemove', (e) => {
  const rect = canvas.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const y = e.clientY - rect.top;
  rive.pointerMove(x, y);
});

canvas.addEventListener('mousedown', (e) => {
  const rect = canvas.getBoundingClientRect();
  rive.pointerDown(e.clientX - rect.left, e.clientY - rect.top);
});

canvas.addEventListener('mouseup', (e) => {
  const rect = canvas.getBoundingClientRect();
  rive.pointerUp(e.clientX - rect.left, e.clientY - rect.top);
});
```

## Artboard Access

### Getting Artboard Info

```typescript
const rive = new Rive({
  src: 'multi-artboard.riv',
  canvas: document.getElementById('canvas'),
  onLoad: () => {
    // Current artboard
    const artboard = rive.artboard;
    console.log('Artboard:', artboard.name);
    console.log('Bounds:', artboard.bounds);
    
    // List all artboards
    const artboardNames = rive.artboardNames;
    console.log('Available:', artboardNames);
  },
});
```

### Switching Artboards

```typescript
// Load different artboard
rive.load({
  src: 'multi-artboard.riv',
  artboard: 'ArtboardName',
  autoplay: true,
});
```

## Text Runs

### Accessing Text Runs

```typescript
const rive = new Rive({
  src: 'text.riv',
  canvas: document.getElementById('canvas'),
  autoplay: true,
  onLoad: () => {
    // Get text run by name
    const textRun = rive.artboard.textRun('username');
    
    // Update text
    textRun.text = 'Hello, World!';
  },
});
```

## View Models (Data Binding)

### Basic Usage

```typescript
const rive = new Rive({
  src: 'data-bound.riv',
  canvas: document.getElementById('canvas'),
  stateMachines: 'Main',
  autoplay: true,
  onLoad: () => {
    const viewModel = rive.viewModelInstance('UserVM');
    
    // Set properties
    viewModel.setString('username', 'John');
    viewModel.setNumber('score', 100);
    viewModel.setBoolean('isActive', true);
    viewModel.setColor('accentColor', '#FF5500');
    
    // Fire trigger
    viewModel.fireTrigger('refresh');
    
    // Get properties
    const username = viewModel.getString('username');
    const score = viewModel.getNumber('score');
  },
});
```

## Cleanup

### Proper Disposal

```typescript
const rive = new Rive({ /* config */ });

// When done (component unmount, page leave, etc.)
function cleanup() {
  rive.cleanup();
  rive.stop();
}

// Or use cleanup callback
const rive = new Rive({
  src: 'animation.riv',
  canvas: document.getElementById('canvas'),
  onLoad: () => {
    // Setup complete
  },
});

// Later
rive.cleanup();
```

## WASM Optimization

### Preloading WASM

```typescript
import { RuntimeLoader } from '@rive-app/canvas';

// Preload WASM before creating Rive instances
RuntimeLoader.getInstance().then(() => {
  // WASM is ready
  const rive = new Rive({ /* config */ });
});
```

### Custom WASM Location

```typescript
import { RuntimeLoader } from '@rive-app/canvas';

// Set custom WASM path
RuntimeLoader.setWasmUrl('/custom/path/rive.wasm');

// Then create Rive instance
const rive = new Rive({ /* config */ });
```

## Canvas Resizing

### Responsive Canvas

```typescript
const canvas = document.getElementById('canvas') as HTMLCanvasElement;
const rive = new Rive({
  src: 'animation.riv',
  canvas: canvas,
  autoplay: true,
});

function resizeCanvas() {
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  
  // Notify Rive of resize
  rive.resizeDrawingSurfaceToCanvas();
}

window.addEventListener('resize', resizeCanvas);
resizeCanvas();
```

## Performance Tips

### Renderer Selection

| Scenario | Package |
|----------|---------|
| Default / Unknown | `@rive-app/canvas` |
| Performance critical | `@rive-app/webgl` |
| Bundle size critical | `@rive-app/canvas-lite` |
| Many simultaneous | `@rive-app/webgl` |

### Best Practices

1. **Cleanup**: Always call `cleanup()` when done
2. **Reuse**: Reuse Rive instances when possible
3. **Lazy load**: Load .riv files on demand
4. **Preload WASM**: Load WASM early in app lifecycle
5. **Right-size canvas**: Match canvas to display size

## Troubleshooting

### Animation Not Playing

1. Check `autoplay: true`
2. Verify animation/state machine name
3. Ensure canvas is visible

### Black Canvas

1. Check .riv file path
2. Verify CORS headers on .riv file
3. Check console for errors

### Performance Issues

1. Use `@rive-app/webgl` for better performance
2. Reduce canvas size
3. Limit concurrent Rive instances

### Memory Leaks

1. Always call `cleanup()` on unmount
2. Remove event listeners
3. Null references after cleanup

## See Also

- [Rive React Runtime](./rive-react-runtime.md)
- [Rive State Machine](./rive-state-machine.md)
- [Rive Events](./rive-events.md)

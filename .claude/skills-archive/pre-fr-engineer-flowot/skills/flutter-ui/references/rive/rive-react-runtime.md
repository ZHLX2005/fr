# Rive React/Next.js Runtime Reference

Complete API documentation for integrating Rive with React and Next.js applications.

## Installation

### Recommended Package

```bash
npm install @rive-app/react-canvas
```

### Alternative Packages

| Package | Description |
|---------|-------------|
| `@rive-app/react-canvas` | Canvas renderer (recommended) |
| `@rive-app/react-canvas-lite` | Smaller bundle, no Rive Text support |
| `@rive-app/react-webgl` | WebGL renderer (Skia-based) |
| `@rive-app/react-webgl2` | Rive Renderer (WebGL2, smaller) |

---

## Basic Usage

### Simple Component

```tsx
import Rive from '@rive-app/react-canvas';

function MyAnimation() {
  return (
    <Rive
      src="/animation.riv"
      stateMachines="MainStateMachine"
    />
  );
}
```

### With useRive Hook

```tsx
import { useRive } from '@rive-app/react-canvas';

function MyAnimation() {
  const { rive, RiveComponent } = useRive({
    src: '/animation.riv',
    stateMachines: 'MainStateMachine',
    autoplay: true,
  });

  return (
    <RiveComponent 
      style={{ width: 400, height: 400 }}
      onMouseEnter={() => rive?.play()}
      onMouseLeave={() => rive?.pause()}
    />
  );
}
```

---

## useRive Hook

### Parameters

```typescript
interface UseRiveParameters {
  // Source
  src?: string;                    // URL or path to .riv file
  buffer?: ArrayBuffer;            // Raw .riv data

  // Artboard selection
  artboard?: string;               // Artboard name (default: first)

  // Animation/State Machine
  animations?: string | string[];  // Linear animation names
  stateMachines?: string | string[]; // State machine names

  // Playback
  autoplay?: boolean;              // Auto-start (default: true)

  // Layout
  layout?: Layout;                 // Fit and alignment

  // Callbacks
  onLoad?: (rive: Rive) => void;
  onLoadError?: (error: Error) => void;
  onPlay?: (event: Event) => void;
  onPause?: (event: Event) => void;
  onStop?: (event: Event) => void;
  onLoop?: (event: Event) => void;
  onStateChange?: (event: StateChangeEvent) => void;

  // Advanced
  useOffscreenRenderer?: boolean;
  shouldDisableRiveListeners?: boolean;
  isTouchScrollEnabled?: boolean;
}
```

### Return Values

```typescript
interface UseRiveReturn {
  rive: Rive | null;               // Rive instance (null until loaded)
  RiveComponent: React.FC<RiveComponentProps>; // Component to render
}
```

### Example with All Options

```tsx
import { useRive, Layout, Fit, Alignment } from '@rive-app/react-canvas';

function CompleteExample() {
  const { rive, RiveComponent } = useRive({
    src: '/interactive.riv',
    artboard: 'MainArtboard',
    stateMachines: 'MainStateMachine',
    autoplay: false,
    layout: new Layout({
      fit: Fit.Contain,
      alignment: Alignment.Center,
    }),
    onLoad: (riveInstance) => {
      console.log('Rive loaded!', riveInstance);
    },
    onStateChange: (event) => {
      console.log('State changed:', event.data);
    },
  });

  return <RiveComponent style={{ width: '100%', height: '100%' }} />;
}
```

---

## RiveComponent Props

```typescript
interface RiveComponentProps {
  className?: string;
  style?: React.CSSProperties;
  onMouseEnter?: () => void;
  onMouseLeave?: () => void;
  onClick?: () => void;
  // ... standard HTML div props
}
```

---

## Layout

### Fit Options

```typescript
import { Fit } from '@rive-app/react-canvas';

// Available fits
Fit.Cover     // Scale to cover, may crop
Fit.Contain   // Scale to fit, may letterbox
Fit.Fill      // Stretch to fill
Fit.FitWidth  // Scale to width
Fit.FitHeight // Scale to height
Fit.None      // No scaling
Fit.ScaleDown // Scale down only if needed
```

### Alignment Options

```typescript
import { Alignment } from '@rive-app/react-canvas';

// Available alignments
Alignment.Center
Alignment.TopLeft
Alignment.TopCenter
Alignment.TopRight
Alignment.CenterLeft
Alignment.CenterRight
Alignment.BottomLeft
Alignment.BottomCenter
Alignment.BottomRight
```

### Creating Layout

```tsx
import { Layout, Fit, Alignment } from '@rive-app/react-canvas';

const layout = new Layout({
  fit: Fit.Contain,
  alignment: Alignment.Center,
});

// Or with min/max bounds
const constrainedLayout = new Layout({
  fit: Fit.Contain,
  alignment: Alignment.Center,
  minX: 0,
  minY: 0,
  maxX: 800,
  maxY: 600,
});
```

---

## Rive Instance API

### Playback Control

```typescript
// Start playing
rive.play();
rive.play('AnimationName');
rive.play('StateMachineName');

// Pause
rive.pause();
rive.pause('AnimationName');

// Stop (resets to beginning)
rive.stop();
rive.stop('AnimationName');

// Reset to initial state
rive.reset();

// Check playing state
const isPlaying = rive.isPlaying;
const isPaused = rive.isPaused;
const isStopped = rive.isStopped;
```

### State Machine Inputs

```typescript
// Get all inputs for a state machine
const inputs = rive.stateMachineInputs('StateMachineName');

// Input types
interface SMIInput {
  name: string;
  type: StateMachineInputType;
}

interface SMINumber extends SMIInput {
  value: number;
}

interface SMIBool extends SMIInput {
  value: boolean;
}

interface SMITrigger extends SMIInput {
  fire(): void;
}

// Finding inputs
const numberInput = inputs?.find(i => i.name === 'progress') as SMINumber;
const boolInput = inputs?.find(i => i.name === 'isActive') as SMIBool;
const triggerInput = inputs?.find(i => i.name === 'onClick') as SMITrigger;

// Setting values
if (numberInput) numberInput.value = 50;
if (boolInput) boolInput.value = true;
if (triggerInput) triggerInput.fire();
```

### Using useStateMachineInput Hook

```tsx
import { useRive, useStateMachineInput } from '@rive-app/react-canvas';

function WithInput() {
  const { rive, RiveComponent } = useRive({
    src: '/interactive.riv',
    stateMachines: 'Controls',
    autoplay: true,
  });

  const progressInput = useStateMachineInput(rive, 'Controls', 'progress');
  const isActiveInput = useStateMachineInput(rive, 'Controls', 'isActive');

  return (
    <div>
      <RiveComponent />
      <input
        type="range"
        min={0}
        max={100}
        onChange={(e) => {
          if (progressInput) progressInput.value = Number(e.target.value);
        }}
      />
      <button onClick={() => {
        if (isActiveInput) isActiveInput.value = !isActiveInput.value;
      }}>
        Toggle Active
      </button>
    </div>
  );
}
```

### Event Listeners

```typescript
// State change events
rive.on(EventType.StateChange, (event) => {
  console.log('States:', event.data);
});

// Rive events (from Event reporting in state machines)
rive.on(EventType.RiveEvent, (event) => {
  console.log('Event name:', event.data.name);
  console.log('Event properties:', event.data.properties);
});

// Loop event
rive.on(EventType.Loop, (event) => {
  console.log('Animation looped:', event.data);
});

// Play/Pause events
rive.on(EventType.Play, () => console.log('Playing'));
rive.on(EventType.Pause, () => console.log('Paused'));
rive.on(EventType.Stop, () => console.log('Stopped'));
```

### Text Runs

```typescript
// Get text run by name
const textRun = rive.getTextRunValue('MyTextRun');

// Set text run value
rive.setTextRunValue('MyTextRun', 'New Text!');
```

### Artboard Information

```typescript
// Get artboard bounds
const bounds = rive.bounds;
console.log('Width:', bounds.maxX - bounds.minX);
console.log('Height:', bounds.maxY - bounds.minY);

// Get source information
const source = rive.source;
```

---

## Scroll-Based Animations

### Basic Scroll Binding

```tsx
import { useRive } from '@rive-app/react-canvas';
import { useEffect, useRef } from 'react';

function ScrollAnimation() {
  const { rive, RiveComponent } = useRive({
    src: '/scroll-animation.riv',
    stateMachines: 'ScrollController',
    autoplay: true,
  });
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!rive) return;

    const scrollInput = rive.stateMachineInputs('ScrollController')
      ?.find(i => i.name === 'scrollProgress');

    const handleScroll = () => {
      if (!containerRef.current || !scrollInput) return;

      const rect = containerRef.current.getBoundingClientRect();
      const windowHeight = window.innerHeight;

      // Calculate progress (0-100)
      const progress = Math.max(0, Math.min(100,
        ((windowHeight - rect.top) / (windowHeight + rect.height)) * 100
      ));

      scrollInput.value = progress;
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll(); // Initial call

    return () => window.removeEventListener('scroll', handleScroll);
  }, [rive]);

  return (
    <div ref={containerRef} style={{ height: '200vh' }}>
      <div style={{ 
        position: 'sticky', 
        top: 0, 
        height: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <RiveComponent style={{ width: '100%', height: '100%' }} />
      </div>
    </div>
  );
}
```

### Multi-Section Scroll Story

```tsx
import { useRive } from '@rive-app/react-canvas';
import { useEffect, useRef } from 'react';

interface Section {
  title: string;
  riveFile: string;
  stateMachine: string;
}

const sections: Section[] = [
  { title: 'Scene 1', riveFile: '/scene1.riv', stateMachine: 'Main' },
  { title: 'Scene 2', riveFile: '/scene2.riv', stateMachine: 'Main' },
  { title: 'Scene 3', riveFile: '/scene3.riv', stateMachine: 'Main' },
];

function ScrollStory() {
  return (
    <div>
      {sections.map((section, index) => (
        <ScrollSection key={index} {...section} />
      ))}
    </div>
  );
}

function ScrollSection({ riveFile, stateMachine }: Section) {
  const { rive, RiveComponent } = useRive({
    src: riveFile,
    stateMachines: stateMachine,
    autoplay: true,
  });
  const sectionRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!rive || !sectionRef.current) return;

    const progressInput = rive.stateMachineInputs(stateMachine)
      ?.find(i => i.name === 'progress');

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && progressInput) {
            // Calculate progress within section
            const rect = entry.boundingClientRect;
            const viewportHeight = window.innerHeight;
            const progress = Math.max(0, Math.min(100,
              ((viewportHeight - rect.top) / rect.height) * 100
            ));
            progressInput.value = progress;
          }
        });
      },
      { threshold: Array.from({ length: 100 }, (_, i) => i / 100) }
    );

    observer.observe(sectionRef.current);

    return () => observer.disconnect();
  }, [rive, stateMachine]);

  return (
    <section ref={sectionRef} style={{ height: '150vh', position: 'relative' }}>
      <div style={{
        position: 'sticky',
        top: 0,
        height: '100vh',
      }}>
        <RiveComponent style={{ width: '100%', height: '100%' }} />
      </div>
    </section>
  );
}
```

### Parallax Effect

```tsx
function ParallaxLayer({ 
  src, 
  scrollMultiplier = 1,
  zIndex = 0,
}: {
  src: string;
  scrollMultiplier?: number;
  zIndex?: number;
}) {
  const { rive, RiveComponent } = useRive({
    src,
    stateMachines: 'Parallax',
    autoplay: true,
  });
  const [offset, setOffset] = useState(0);

  useEffect(() => {
    const handleScroll = () => {
      setOffset(window.scrollY * scrollMultiplier);
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, [scrollMultiplier]);

  return (
    <div style={{
      position: 'fixed',
      top: 0,
      left: 0,
      width: '100%',
      height: '100%',
      transform: `translateY(${-offset}px)`,
      zIndex,
      pointerEvents: 'none',
    }}>
      <RiveComponent style={{ width: '100%', height: '100%' }} />
    </div>
  );
}
```

---

## Data Binding (View Models)

### Setting View Model Data at Runtime

```tsx
function DataBoundAnimation() {
  const { rive, RiveComponent } = useRive({
    src: '/data-bound.riv',
    stateMachines: 'Main',
    autoplay: true,
  });

  useEffect(() => {
    if (!rive) return;

    // Access view model (requires Rive runtime with data binding support)
    // Note: API may vary based on runtime version
  }, [rive]);

  return <RiveComponent />;
}
```

---

## Loading States and Error Handling

```tsx
import { useRive } from '@rive-app/react-canvas';
import { useState } from 'react';

function RobustAnimation() {
  const [isLoaded, setIsLoaded] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const { rive, RiveComponent } = useRive({
    src: '/animation.riv',
    stateMachines: 'Main',
    autoplay: true,
    onLoad: () => setIsLoaded(true),
    onLoadError: (err) => setError(err),
  });

  if (error) {
    return <div>Failed to load animation: {error.message}</div>;
  }

  return (
    <div style={{ position: 'relative' }}>
      {!isLoaded && <div className="loading-spinner" />}
      <RiveComponent style={{ 
        width: '100%', 
        height: '100%',
        opacity: isLoaded ? 1 : 0,
      }} />
    </div>
  );
}
```

---

## Performance Optimization

### Lazy Loading

```tsx
import { lazy, Suspense } from 'react';

const RiveAnimation = lazy(() => import('./RiveAnimation'));

function App() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <RiveAnimation />
    </Suspense>
  );
}
```

### Conditional Rendering

```tsx
import { useRive } from '@rive-app/react-canvas';
import { useInView } from 'react-intersection-observer';

function LazyRive() {
  const { ref, inView } = useInView({
    triggerOnce: true,
    threshold: 0.1,
  });

  return (
    <div ref={ref} style={{ minHeight: 400 }}>
      {inView && <RiveAnimation />}
    </div>
  );
}
```

### Caching Rive Files

```tsx
import { RuntimeLoader } from '@rive-app/react-canvas';

// Preload at app initialization
async function preloadRiveFiles() {
  await Promise.all([
    fetch('/animation1.riv'),
    fetch('/animation2.riv'),
    fetch('/animation3.riv'),
  ]);
}
```

---

## Next.js Specific

### App Router (Next.js 13+)

```tsx
'use client';

import { useRive } from '@rive-app/react-canvas';

export default function RiveSection() {
  const { RiveComponent } = useRive({
    src: '/animations/hero.riv',
    stateMachines: 'Main',
    autoplay: true,
  });

  return <RiveComponent style={{ width: '100%', height: 400 }} />;
}
```

### Public Directory

Place `.riv` files in `/public` directory:

```
public/
  animations/
    hero.riv
    scroll.riv
```

Reference as:
```tsx
src="/animations/hero.riv"
```

### Dynamic Import for SSR

```tsx
import dynamic from 'next/dynamic';

const RiveAnimation = dynamic(
  () => import('../components/RiveAnimation'),
  { ssr: false, loading: () => <div>Loading...</div> }
);
```

---

## TypeScript Types

### Import Types

```typescript
import {
  useRive,
  useStateMachineInput,
  Layout,
  Fit,
  Alignment,
  EventType,
  StateMachineInputType,
} from '@rive-app/react-canvas';

import type {
  Rive,
  SMIInput,
  SMINumber,
  SMIBool,
  SMITrigger,
  Event as RiveEvent,
  StateChangeEvent,
} from '@rive-app/react-canvas';
```

### Custom Hook Example

```typescript
import { useRive, SMINumber } from '@rive-app/react-canvas';

function useScrollRive(src: string, stateMachine: string, inputName: string) {
  const { rive, RiveComponent } = useRive({
    src,
    stateMachines: stateMachine,
    autoplay: true,
  });

  const updateScroll = useCallback((progress: number) => {
    if (!rive) return;
    
    const input = rive.stateMachineInputs(stateMachine)
      ?.find(i => i.name === inputName) as SMINumber | undefined;
    
    if (input) {
      input.value = progress;
    }
  }, [rive, stateMachine, inputName]);

  return { RiveComponent, updateScroll };
}
```

---

## Troubleshooting

### Common Issues

1. **Animation not showing**
   - Check container has dimensions (width/height)
   - Verify file path is correct
   - Ensure `RiveComponent` is rendered

2. **State machine not responding**
   - Verify state machine name matches exactly
   - Check input names are correct
   - Ensure rive instance is loaded before accessing inputs

3. **Performance issues**
   - Use `react-canvas` over `react-webgl` for most cases
   - Lazy load animations not in viewport
   - Avoid creating new Layout instances on every render

4. **SSR errors in Next.js**
   - Use `'use client'` directive
   - Or use `dynamic` import with `{ ssr: false }`

### Debug Mode

```tsx
const { rive, RiveComponent } = useRive({
  src: '/animation.riv',
  stateMachines: 'Main',
  onLoad: (riveInstance) => {
    console.log('Artboards:', riveInstance.artboardName);
    console.log('State Machines:', riveInstance.stateMachineNames);
    console.log('Inputs:', riveInstance.stateMachineInputs('Main'));
  },
});
```

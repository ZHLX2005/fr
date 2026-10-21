# Rive State Machine Reference

> Official docs: https://rive.app/docs/editor/state-machine/

## Overview

**State Machines** in Rive control animation logic and interactivity. They determine which animations play, when they transition, and how they respond to inputs.

## Core Concepts

### What is a State Machine?

A State Machine is a graph of:
- **States**: Containers for animations
- **Transitions**: Connections between states with conditions
- **Inputs**: Variables that drive transitions
- **Layers**: Parallel state machines for concurrent animations

### Creating a State Machine

1. Switch to **Animate** mode
2. Click **+** next to Animations
3. Select **State Machine**
4. Name it descriptively (e.g., "Button States", "Character Controller")

## States

### State Types

| Type | Icon | Purpose |
|------|------|---------|
| **Animation State** | ▶️ | Plays a timeline animation |
| **Entry State** | 🟢 | Starting point (auto-created) |
| **Exit State** | 🔴 | Ending point for one-shot flows |
| **Any State** | ⭐ | Transition from ANY current state |
| **Blend State** | 🔀 | Blend multiple animations |

### Animation States

The most common state type. Properties:

| Property | Description |
|----------|-------------|
| **Animation** | Which timeline to play |
| **Speed** | Playback speed multiplier |
| **Loop** | One-shot, Loop, Ping-Pong |
| **Mix** | Blend weight with other layers |

### Entry State

- Every layer has exactly ONE entry state
- Cannot be deleted
- First transition from Entry starts the state machine

### Exit State

- Signals the state machine layer has completed
- Useful for one-shot sequences
- Optional—many state machines loop indefinitely

### Any State

- Transitions FROM Any State can fire from any current state
- Useful for global interrupts (e.g., "damage" animation from any pose)
- Creates implicit transitions from all states

### Blend States

Blend multiple animations based on inputs:

#### 1D Blend Space

```
0%      50%      100%
├────────┼────────┤
Idle    Walk     Run

Input "Speed" interpolates between animations
```

#### 2D Blend Space (Direct Blend)

Blend based on two inputs (X/Y):
- Useful for directional movement
- Each animation has X/Y coordinates in blend space

## Inputs

> ⚠️ **Note**: Traditional inputs (Number, Boolean, Trigger) still work but **Data Binding with View Models** is the recommended modern approach for runtime control.

### Input Types

| Type | Description | Use Case |
|------|-------------|----------|
| **Number** | Float value | Blend spaces, thresholds |
| **Boolean** | True/False | Toggle states |
| **Trigger** | One-shot signal | Fire-and-forget events |

### Creating Inputs

1. In State Machine editor, find **Inputs** panel
2. Click **+**
3. Select type
4. Name descriptively (e.g., "isHovered", "health", "onClick")

### Number Inputs

```
Range: -∞ to +∞ (or set min/max)
Default: 0

Example conditions:
- health > 50 → "Healthy" state
- health <= 50 → "Hurt" state
```

### Boolean Inputs

```
Values: true or false
Default: false

Example conditions:
- isEnabled == true → "Active" state
- isEnabled == false → "Disabled" state
```

### Trigger Inputs

```
Behavior: Fires once, auto-resets

Example:
- "clicked" trigger → Play "Click" animation
- Animation completes → Returns to previous state
```

## Transitions

### What is a Transition?

A **Transition** is a connection between two states that:
- Has conditions for when to fire
- Has duration for how to blend
- Has easing for blend curve

### Creating Transitions

1. Hover over source state
2. Click and drag the arrow
3. Connect to destination state
4. Configure in Inspector

### Transition Properties

| Property | Description |
|----------|-------------|
| **Duration** | Blend time in ms (0 = instant) |
| **Easing** | Blend curve (Linear, Ease In, etc.) |
| **Exit Time** | % of animation before transition can fire |
| **Conditions** | Rules that must be true |

### Transition Conditions

Multiple conditions = AND (all must be true)

| Operator | Types | Example |
|----------|-------|---------|
| `==` | All | `isReady == true` |
| `!=` | All | `state != "idle"` |
| `>` | Number | `speed > 5` |
| `>=` | Number | `health >= 100` |
| `<` | Number | `progress < 1` |
| `<=` | Number | `energy <= 0` |

### Exit Time

```
Exit Time: 75%
→ Transition only evaluates after 75% of current animation played

Exit Time: 100%  
→ Animation must complete before transitioning

Exit Time: 0%
→ Can transition immediately
```

### Instant vs Blended Transitions

```
Duration: 0ms
→ Instant cut to next state

Duration: 200ms
→ Cross-fade over 200ms
```

## Listeners

**Listeners** detect user interactions and trigger responses.

### Listener Types

| Type | Fires When |
|------|------------|
| **Pointer Down** | Mouse/touch press |
| **Pointer Up** | Mouse/touch release |
| **Pointer Enter** | Cursor enters hit area |
| **Pointer Exit** | Cursor leaves hit area |
| **Pointer Move** | Cursor moves within hit area |

### Creating Listeners

1. Select target object (shape, group, etc.)
2. In State Machine, add Listener
3. Set type (Pointer Down, etc.)
4. Add Actions

### Hit Areas

By default, listeners use the object's shape as hit area.

For custom hit areas:
1. Create a shape for the hit area
2. Set opacity to 0 (invisible)
3. Attach listener to that shape

### Listener Actions

What happens when listener fires:

| Action | Description |
|--------|-------------|
| **Fire Trigger** | Fire a trigger input |
| **Set Boolean** | Set boolean to true/false/toggle |
| **Set Number** | Set number to value |
| **Fire Event** | Fire a Rive Event |

### Multiple Actions

One listener can perform multiple actions:

```
Pointer Down on Button:
├── Fire Trigger "onClick"
├── Set Boolean "isPressed" = true
└── Fire Event "ButtonClicked"
```

## Layers

### What are Layers?

Layers are **parallel state machines** that run simultaneously:

```
State Machine "Character"
├── Layer 1: "Body" (walk, run, jump)
├── Layer 2: "Face" (happy, sad, angry)
└── Layer 3: "Effects" (glow, particles)
```

### Why Use Layers?

- **Independent control**: Face can change while body walks
- **Additive animations**: Layers blend together
- **Complexity management**: Separate concerns

### Creating Layers

1. In State Machine editor
2. Click **+** on Layers panel
3. Name the layer
4. Build states/transitions for that layer

### Layer Order

- Layers blend from bottom to top
- Higher layers can override lower layers
- Use **Mix** property to control blend weight

### Layer Mixing

| Mix Value | Effect |
|-----------|--------|
| 0% | Layer has no effect |
| 50% | Half-blended with layers below |
| 100% | Full effect (can override) |

## Runtime Control

### JavaScript/Web

```javascript
import { Rive } from '@rive-app/canvas';

const rive = new Rive({
  src: 'file.riv',
  canvas: document.getElementById('canvas'),
  stateMachines: 'State Machine 1',
  autoplay: true,
  onLoad: () => {
    const inputs = rive.stateMachineInputs('State Machine 1');
    
    // Get specific input
    const isHovered = inputs.find(i => i.name === 'isHovered');
    const progress = inputs.find(i => i.name === 'progress');
    const onClick = inputs.find(i => i.name === 'onClick');
    
    // Set boolean
    isHovered.value = true;
    
    // Set number
    progress.value = 0.75;
    
    // Fire trigger
    onClick.fire();
  }
});
```

### React

```tsx
import { useRive, useStateMachineInput } from '@rive-app/react-canvas';

function Button() {
  const { rive, RiveComponent } = useRive({
    src: 'button.riv',
    stateMachines: 'Button State Machine',
    autoplay: true,
  });
  
  const isHovered = useStateMachineInput(rive, 'Button State Machine', 'isHovered');
  const isPressed = useStateMachineInput(rive, 'Button State Machine', 'isPressed');
  const onClick = useStateMachineInput(rive, 'Button State Machine', 'onClick');
  
  return (
    <RiveComponent
      onMouseEnter={() => isHovered && (isHovered.value = true)}
      onMouseLeave={() => isHovered && (isHovered.value = false)}
      onMouseDown={() => isPressed && (isPressed.value = true)}
      onMouseUp={() => {
        isPressed && (isPressed.value = false);
        onClick?.fire();
      }}
    />
  );
}
```

### Flutter

```dart
import 'package:rive/rive.dart';

class MyAnimation extends StatefulWidget {
  @override
  _MyAnimationState createState() => _MyAnimationState();
}

class _MyAnimationState extends State<MyAnimation> {
  SMIBool? _isHovered;
  SMINumber? _progress;
  SMITrigger? _onClick;
  
  void _onRiveInit(Artboard artboard) {
    final controller = StateMachineController.fromArtboard(artboard, 'State Machine 1');
    if (controller != null) {
      artboard.addController(controller);
      _isHovered = controller.findInput<bool>('isHovered') as SMIBool?;
      _progress = controller.findInput<double>('progress') as SMINumber?;
      _onClick = controller.findInput<bool>('onClick') as SMITrigger?;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _onClick?.fire(),
      child: RiveAnimation.asset(
        'assets/animation.riv',
        onInit: _onRiveInit,
      ),
    );
  }
}
```

## Common Patterns

### Button States

```
Entry → Idle
       ↓ (isHovered == true)
      Hovered
       ↓ (isPressed == true)
      Pressed
       ↓ (onClick trigger)
      Click Animation → Idle
```

### Character Movement

```
Layer 1 (Movement):
Entry → Idle
       ↙ ↓ ↘
    Walk  Run  Jump
    
Layer 2 (Expression):
Entry → Neutral
       ↙ ↘
    Happy  Sad
```

### Toggle Switch

```
Entry → Off
       ↓ (isOn == true)
      Turning On → On
       ↓ (isOn == false)
      Turning Off → Off
```

### Health Bar

```
Use Blend State with Number input "health" (0-100)
Blend between: Empty (0) → Half (50) → Full (100)
```

## Best Practices

### Naming Conventions

- State: `Idle`, `Walking`, `Jumping` (present participle for actions)
- Input: `isHovered`, `speed`, `onClick` (camelCase, descriptive)
- Layer: `Movement`, `Face`, `Effects` (noun, singular)

### State Machine Organization

1. One state machine per interactive component
2. Use layers for independent animation systems
3. Keep transition logic simple—complex logic in code

### Performance Tips

- Fewer layers = better performance
- Avoid deeply nested blend states
- Use Exit Time to prevent rapid state switching

### Debugging

1. Use Rive's preview to test transitions
2. Check condition operators carefully
3. Verify input values at runtime with console logs

## Migration: Inputs → Data Binding

Modern Rive recommends **Data Binding** over traditional inputs:

| Traditional | Data Binding |
|-------------|--------------|
| Inputs panel | View Model properties |
| `input.value = x` | `viewModel.property = x` |
| Limited types | Rich types (List, nested VM) |
| One-way | Two-way binding |

See [Data Binding Reference](./rive-data-binding.md) for the modern approach.

## See Also

- [Rive Events](./rive-events.md)
- [Rive Data Binding](./rive-data-binding.md)
- [Rive Animation Mode](./rive-animation-mode.md)
- [Rive React Runtime](./rive-react-runtime.md)

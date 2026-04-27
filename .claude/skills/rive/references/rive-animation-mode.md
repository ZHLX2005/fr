# Rive Animation Mode Reference

> Official docs: https://rive.app/docs/editor/animate-mode/

## Overview

**Animate Mode** is where you create timeline-based animations in Rive. You keyframe property changes over time to create motion, transitions, and effects.

## Accessing Animate Mode

1. Click **Animate** tab (top of editor)
2. Or press **A** keyboard shortcut
3. Timeline panel appears at bottom

## Timeline Fundamentals

### Timeline Structure

```
┌─────────────────────────────────────────────────────────┐
│ Animation Name                    │ 0:00  0:15  0:30   │
├─────────────────────────────────────────────────────────┤
│ ▼ Object Name                     │ ●─────●─────●      │
│   └─ Position X                   │ ●─────────●        │
│   └─ Position Y                   │ ●────●────●        │
│   └─ Opacity                      │ ●──────────●       │
└─────────────────────────────────────────────────────────┘
        ↑                                   ↑
    Hierarchy                          Keyframes
```

### Timeline Controls

| Control | Function |
|---------|----------|
| **Play/Pause** | Preview animation |
| **Playhead** | Current time position |
| **Work Area** | Loop/preview range |
| **Zoom** | Timeline scale |

### Timeline Properties

| Property | Description |
|----------|-------------|
| **Duration** | Total length in seconds |
| **FPS** | Frames per second (default: 60) |
| **Loop** | One-shot, Loop, Ping-Pong |

## Creating Animations

### New Animation

1. In Animate mode, click **+** next to Animations
2. Select **Timeline** (not State Machine)
3. Name it descriptively (e.g., "Idle", "ButtonHover")

### Animation Settings

| Setting | Options | Description |
|---------|---------|-------------|
| **Duration** | Seconds | How long the animation runs |
| **FPS** | 24, 30, 60, 120 | Keyframe precision |
| **Loop** | One-shot, Loop, Ping-Pong | Playback behavior |
| **Work Area** | Start/End | Preview range |

## Keyframes

### What is a Keyframe?

A **keyframe** records a property value at a specific time. Rive interpolates between keyframes to create smooth animation.

### Adding Keyframes

**Method 1: Auto-Key**
1. Enable Auto-Key (circle icon in timeline)
2. Move playhead to desired time
3. Change any property → Keyframe added automatically

**Method 2: Manual**
1. Move playhead to time
2. Select object
3. Right-click property → **Add Key**
4. Or press **K** with property selected

**Method 3: Inspector**
1. Click diamond icon next to property in Inspector
2. Keyframe added at current playhead position

### Keyframe Types

| Type | Icon | Properties |
|------|------|------------|
| **Transform** | ◆ | Position, Rotation, Scale |
| **Style** | ◆ | Fill, Stroke, Opacity |
| **Constraint** | ◆ | Constraint strength, offset |
| **Path** | ◆ | Vertex positions (shapes) |

### Selecting Keyframes

| Action | Method |
|--------|--------|
| Select one | Click keyframe |
| Select multiple | Shift+Click or drag box |
| Select all on track | Double-click track |
| Select all for object | Click object row |

### Moving Keyframes

- **Drag**: Move in time
- **Shift+Drag**: Constrain to timeline
- **Alt+Drag**: Duplicate keyframes

### Deleting Keyframes

- Select keyframe(s) → **Delete** key
- Right-click → **Delete Key**

## Interpolation & Easing

### Interpolation Types

| Type | Behavior | Use Case |
|------|----------|----------|
| **Linear** | Constant speed | Mechanical motion |
| **Hold** | Instant jump | On/Off states |
| **Cubic** | Bezier curve | Natural motion |

### Setting Interpolation

1. Select keyframe(s)
2. Right-click → **Interpolation**
3. Choose type

### Cubic Bezier Easing

For cubic interpolation, adjust bezier handles:

1. Select keyframe
2. Open **Graph Editor** (icon in timeline)
3. Drag handles to shape curve

### Common Easing Presets

| Preset | Feel |
|--------|------|
| **Ease In** | Slow start, fast end |
| **Ease Out** | Fast start, slow end |
| **Ease In-Out** | Slow start and end |
| **Ease Out-Back** | Overshoot at end |

### Graph Editor

The **Graph Editor** shows property values over time as curves:

```
Value
  │    ╭──────╮
  │   ╱        ╲
  │  ╱          ╲
  │ ╱            ╲
  └─────────────────→ Time
```

- **Drag points**: Change values
- **Drag handles**: Change easing
- **Hold Ctrl**: Fine adjustment

## Animation Mixing

### What is Mixing?

**Mixing** blends multiple animations together. Useful for:
- Layering animations (walk + wave)
- Smooth transitions between states
- Additive effects

### Mix Property

Every animation has a **Mix** value (0-1):
- `0`: Animation has no effect
- `0.5`: Half-blended
- `1`: Full effect

### Mixing in State Machine

Layers in a State Machine automatically mix:

```
Layer 1: Walk (Mix: 1.0)
Layer 2: Wave (Mix: 1.0)
→ Character walks AND waves
```

### Additive vs Override

| Mode | Behavior |
|------|----------|
| **Additive** | Values add to base |
| **Override** | Values replace base |

## Animating Specific Properties

### Transform Animation

| Property | What It Does |
|----------|--------------|
| **Position X/Y** | Move object |
| **Rotation** | Spin object |
| **Scale X/Y** | Resize object |
| **Origin** | Pivot point |

### Style Animation

| Property | What It Does |
|----------|--------------|
| **Fill Color** | Animate color |
| **Fill Opacity** | Fade fill |
| **Stroke Color** | Animate stroke |
| **Stroke Width** | Animate thickness |

### Path Animation

Animate shape vertices directly:
1. Select shape
2. Switch to vertex edit mode
3. Keyframe vertex positions

### Constraint Animation

| Property | Effect |
|----------|--------|
| **Strength** | Animate constraint influence (0-100%) |
| **Offset** | Animate constraint offset |

## Draw Order Animation

Animate which objects appear in front:

1. Find **Draw Order** track in timeline
2. Add keyframe
3. Reorder objects in hierarchy at that frame

```
Frame 0: A in front of B
Frame 30: B in front of A
→ Objects swap depth mid-animation
```

## Solos

**Solos** toggle visibility within a group:

1. Create group with multiple children
2. Set group as **Solo Group**
3. Keyframe which child is visible

```
Solo Group "Expressions"
├── Happy (visible frame 0-29)
├── Sad (visible frame 30-59)
└── Angry (visible frame 60-89)
```

## Animation Best Practices

### Timing Guidelines

| Animation Type | Typical Duration |
|----------------|------------------|
| Button hover | 150-200ms |
| Modal open | 200-300ms |
| Page transition | 300-500ms |
| Loading loop | 1-2s |
| Character idle | 2-4s |

### Easing Guidelines

| Motion Type | Recommended Easing |
|-------------|-------------------|
| Enter screen | Ease Out |
| Exit screen | Ease In |
| User feedback | Ease Out |
| Bounce | Ease Out Back |
| Loop point | Ease In-Out |

### Performance Tips

1. **Minimize keyframes**: Only key what changes
2. **Avoid path animation** on complex shapes: Use bones instead
3. **Use symbols**: Animate once, reuse everywhere
4. **Optimize for target FPS**: Mobile may need simpler animations

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **A** | Toggle Animate mode |
| **Space** | Play/Pause |
| **K** | Add keyframe |
| **← →** | Previous/Next frame |
| **Shift + ← →** | Previous/Next keyframe |
| **Home** | Go to start |
| **End** | Go to end |
| **[ ]** | Set work area |

## Common Patterns

### Fade In

```
Frame 0: Opacity = 0
Frame 15: Opacity = 1
Easing: Ease Out
```

### Slide In

```
Frame 0: Position X = -100
Frame 20: Position X = 0
Easing: Ease Out
```

### Bounce

```
Frame 0: Scale = 1.0
Frame 10: Scale = 1.2
Frame 20: Scale = 0.95
Frame 25: Scale = 1.0
Easing: Ease Out on each
```

### Pulse/Heartbeat

```
Frame 0: Scale = 1.0
Frame 10: Scale = 1.1
Frame 20: Scale = 1.0
Loop: Yes
```

### Rotation Loop

```
Frame 0: Rotation = 0°
Frame 60: Rotation = 360°
Interpolation: Linear
Loop: Yes
```

## Troubleshooting

### Animation Not Playing

1. Check animation is selected in State Machine
2. Verify Loop setting
3. Check Mix value > 0

### Jerky Animation

1. Add more keyframes
2. Adjust easing curves
3. Check FPS matches export target

### Unexpected Movement

1. Check parent object transforms
2. Verify origin point position
3. Look for conflicting constraints

### Timeline Performance

1. Reduce keyframe density
2. Simplify complex paths
3. Use bones instead of path morphing

## See Also

- [Rive State Machine](./rive-state-machine.md)
- [Rive Constraints](./rive-constraints.md)
- [Rive Manipulating Shapes](./rive-manipulating-shapes.md)

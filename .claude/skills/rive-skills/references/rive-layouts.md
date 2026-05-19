# Rive Layouts Reference

> Official docs: https://rive.app/docs/editor/layouts/

## Overview

Rive Layouts provide a **Flexbox-like system** for creating responsive, adaptive interfaces. Layouts automatically manage the positioning and sizing of their children based on configurable parameters.

## Core Concepts

### Layout Container
A **Layout** is a special container that:
- Automatically arranges children based on Flexbox rules
- Supports nested layouts for complex UI structures
- Can be animated and bound to data
- Works across all Rive runtimes

### Creating Layouts

1. **From menu**: Insert → Layout
2. **From artboard**: Right-click → Add Layout
3. **Convert existing**: Select objects → Right-click → Wrap in Layout

## Layout Parameters

### Position Type

| Type | Description |
|------|-------------|
| **Relative** | Participates in parent's layout flow (default) |
| **Absolute** | Positioned relative to parent, outside normal flow |

### Flex Direction

| Direction | Children Flow |
|-----------|---------------|
| **Row** | Left to right (horizontal) |
| **Row Reverse** | Right to left |
| **Column** | Top to bottom (vertical) |
| **Column Reverse** | Bottom to top |

### Alignment (Main Axis)

Controls distribution along the **flex direction**:

| Value | Behavior |
|-------|----------|
| **Start** | Pack at start |
| **Center** | Pack at center |
| **End** | Pack at end |
| **Space Between** | Evenly distribute, no edge space |
| **Space Around** | Evenly distribute with edge space |
| **Space Evenly** | Equal space between all items |

### Cross-Axis Alignment

Controls alignment **perpendicular** to flex direction:

| Value | Behavior |
|-------|----------|
| **Start** | Align to start |
| **Center** | Align to center |
| **End** | Align to end |
| **Stretch** | Stretch to fill (default) |

### Gap

Space between children:
- **Row Gap**: Vertical space between rows
- **Column Gap**: Horizontal space between columns

### Padding

Internal spacing from layout edges:
- **Padding Top/Right/Bottom/Left**
- Can be set uniformly or per-side

## Size Parameters

### Width & Height Scale Types

| Scale Type | Behavior |
|------------|----------|
| **Fixed** | Explicit pixel value |
| **Hug** | Shrink to fit content |
| **Fill** | Expand to fill available space |
| **Fill Portion** | Relative sizing (e.g., 2:1 ratio) |

### Min/Max Constraints

- **Min Width/Height**: Minimum dimensions
- **Max Width/Height**: Maximum dimensions

### Intrinsic Sizing

When children have intrinsic sizes (like text), layouts respect these unless overridden.

## Layout Styles

Reusable configurations that can be applied to multiple layouts:

```
1. Create a Layout Style in the Assets panel
2. Configure all parameters
3. Apply to any layout via the Inspector
4. Changes to style update all linked layouts
```

### Creating Layout Styles

1. Assets panel → + → Layout Style
2. Configure parameters
3. Name descriptively (e.g., "Card", "Button Row")

### Applying Styles

- Drag style onto layout
- Or: Select layout → Inspector → Style dropdown

## N-Slicing

**N-Slicing** (9-slice scaling) allows layouts to scale while preserving corners and edges.

### How It Works

```
┌───┬───────┬───┐
│ 1 │   2   │ 3 │  ← Corners don't stretch
├───┼───────┼───┤
│ 4 │   5   │ 6 │  ← Edges stretch in one direction
├───┼───────┼───┤
│ 7 │   8   │ 9 │  ← Center stretches both directions
└───┴───────┴───┘
```

### Setting Up N-Slicing

1. Select layout with background shape
2. Enable N-Slice in Inspector
3. Adjust slice guides (top, right, bottom, left insets)

### Best Practices

- Use for buttons, cards, panels
- Keep corners outside slice boundaries
- Test at various sizes

## Scrolling

Layouts can enable scrolling when content exceeds bounds.

### Scroll Properties

| Property | Description |
|----------|-------------|
| **Overflow** | `Visible`, `Hidden`, `Scroll` |
| **Scroll Direction** | `Horizontal`, `Vertical`, `Both` |
| **Clip Content** | Hide content outside bounds |

### Scroll Behavior

```
Overflow: Scroll + Direction: Vertical
→ Enables vertical scrolling when content exceeds height
```

### Scroll Position (Runtime)

Access scroll position via Data Binding or Scripting:

```lua
-- Rive Script: Read scroll position
local scrollY = self.scrollY

-- Set scroll position
self.scrollY = 100
```

### Scroll Events

Listen for scroll changes at runtime:

```javascript
// JavaScript runtime
stateMachine.addEventListener('scroll', (event) => {
  console.log('Scroll position:', event.scrollY);
});
```

## Animating Layouts

Layout parameters can be animated:

### Animatable Properties

- Width, Height
- Padding (all sides)
- Gap
- Alignment
- Position (for absolute layouts)

### Animation Tips

1. Animate `Fill Portion` for smooth resizing
2. Use layout transitions for state changes
3. Combine with opacity for reveal effects

## Nested Layouts

Complex UIs often require nested layouts:

```
Root Layout (Column)
├── Header Layout (Row)
│   ├── Logo
│   └── Nav Layout (Row)
│       ├── Link 1
│       ├── Link 2
│       └── Link 3
├── Content Layout (Row)
│   ├── Sidebar Layout (Column)
│   └── Main Layout (Column)
└── Footer Layout (Row)
```

### Nesting Best Practices

- Keep hierarchy shallow when possible
- Use layout styles for consistency
- Name layouts descriptively

## Layout vs Groups

| Feature | Layout | Group |
|---------|--------|-------|
| Auto-positioning | ✅ Yes | ❌ No |
| Responsive sizing | ✅ Yes | ❌ No |
| Manual child placement | ❌ No | ✅ Yes |
| Flexbox properties | ✅ Yes | ❌ No |
| Performance | Slightly heavier | Lighter |

**Use Layouts when**: You need responsive, auto-arranged content
**Use Groups when**: You need precise manual positioning

## Runtime Access

### JavaScript/Web

```javascript
const layout = artboard.layout('MyLayout');

// Read properties
const width = layout.width;
const height = layout.height;

// Modify (if bindable)
layout.width = 300;
```

### React

```tsx
import { useRive } from '@rive-app/react-canvas';

function App() {
  const { rive, RiveComponent } = useRive({
    src: 'file.riv',
    stateMachines: 'State Machine 1',
    autoplay: true,
    onLoad: () => {
      // Access layouts via artboard
    }
  });

  return <RiveComponent />;
}
```

### Data Binding with Layouts

Layouts work with View Models:

```
1. Create View Model with Number properties (width, height)
2. Bind layout dimensions to View Model properties
3. Update View Model at runtime → Layout updates
```

## Common Patterns

### Responsive Card

```
Layout (Column, Hug Width, Hug Height)
├── Image (Fill Width, Fixed Height)
├── Title Text (Fill Width, Hug Height)
└── Button Layout (Row, Space Between)
    ├── Secondary Button (Hug)
    └── Primary Button (Hug)
```

### Navigation Bar

```
Layout (Row, Fill Width, Fixed Height: 60)
├── Logo (Fixed Width, Hug Height)
├── Spacer Layout (Fill)
└── Nav Items Layout (Row, Gap: 16)
    ├── Item 1
    ├── Item 2
    └── Item 3
```

### Centered Content

```
Layout (Row, Fill, Align: Center, Cross: Center)
└── Content Layout (Hug Width, Hug Height)
    └── Your content here
```

## Troubleshooting

### Layout Not Responding

1. Check Position Type (Relative vs Absolute)
2. Verify parent layout settings
3. Check for conflicting constraints

### Children Overlapping

1. Ensure Flex Direction is correct
2. Check Gap values
3. Verify children don't have Absolute positioning

### Scroll Not Working

1. Set Overflow to Scroll
2. Ensure content exceeds container bounds
3. Check Clip Content is enabled

### Performance Issues

1. Reduce nesting depth
2. Use simpler layouts where possible
3. Avoid animating many layout properties simultaneously

## See Also

- [Rive Editor Fundamentals](./rive-editor-fundamentals.md)
- [Rive Data Binding](./rive-data-binding.md)
- [Rive State Machine](./rive-state-machine.md)

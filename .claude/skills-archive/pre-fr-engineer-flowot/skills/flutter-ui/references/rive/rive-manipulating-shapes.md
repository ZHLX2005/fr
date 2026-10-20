# Rive Manipulating Shapes Reference

> Official docs: https://rive.app/docs/editor/manipulating-shapes/

## Overview

Rive provides powerful tools for manipulating shapes beyond basic transforms. This includes **Bones**, **Meshes**, **Clipping**, **Joysticks**, **Solos**, and **Trim Paths** for creating organic animations and complex visual effects.

## Bones

### What are Bones?

**Bones** create skeletal rigs for animating shapes. They provide:
- Hierarchical deformation
- Smooth bending of shapes
- Efficient character animation

### Creating Bones

1. Select **Bone Tool** (B key)
2. Click to place first bone (root)
3. Continue clicking to chain bones
4. Press **Escape** to finish

### Bone Hierarchy

```
Root Bone (e.g., spine)
├── Child Bone (e.g., chest)
│   ├── Arm L
│   │   └── Forearm L
│   │       └── Hand L
│   └── Arm R
│       └── Forearm R
│           └── Hand R
└── Pelvis
    ├── Leg L
    │   └── Lower Leg L
    │       └── Foot L
    └── Leg R
        └── Lower Leg R
            └── Foot R
```

### Bone Properties

| Property | Description |
|----------|-------------|
| **Length** | Distance to child joint |
| **Rotation** | Local rotation angle |
| **Scale** | Bone scale factor |

### Binding Shapes to Bones

1. Select shape(s) to bind
2. Select bone(s) to bind to
3. Right-click → **Bind**
4. Or use menu: Object → Bind

### Bone Tips

**Bone Tips** are optional end effectors:
- Show the end of the last bone in a chain
- Can be targeted by IK constraints
- Toggle visibility in View menu

## Meshes

### What is a Mesh?

A **Mesh** subdivides a shape into triangles with vertices that can be:
- Weighted to multiple bones
- Individually positioned
- Animated for deformation

### Converting to Mesh

1. Select shape
2. Right-click → **Convert to Mesh**
3. Or: Object → Convert to Mesh

### Mesh Editing

**Vertex Mode:**
- Click vertex to select
- Drag to move
- **Shift+Click**: Add to selection
- **Alt+Click**: Remove from selection

**Edge Mode:**
- Select edges between vertices
- Drag to move connected vertices

**Face Mode:**
- Select triangular faces
- Operations affect all face vertices

### Adding Vertices

1. Enter mesh edit mode
2. Click on edge to add vertex
3. Or use **Add Vertex** tool

### Automatic Meshing

Rive can auto-generate mesh:
1. Select shape
2. Convert to Mesh
3. Adjust **Subdivision** level

## Vertex Weights

### What are Weights?

**Weights** determine how much each bone influences each vertex:
- Weight of 1.0 = full influence
- Weight of 0.0 = no influence
- Weights from multiple bones blend

### Weight Painting

1. Select mesh
2. Select bone to paint for
3. Use **Weight Brush** tool
4. Paint on mesh vertices

### Weight Brush Settings

| Setting | Description |
|---------|-------------|
| **Radius** | Brush size |
| **Strength** | Paint intensity |
| **Mode** | Add / Subtract / Smooth |

### Auto Weights

Rive can calculate weights automatically:
1. Select mesh
2. Select bound bones
3. Right-click → **Auto Weight**

### Weight Table

View exact weights per vertex:
1. Select mesh
2. Open **Weights** panel
3. See/edit numeric values

## Clipping

### What is Clipping?

**Clipping** uses one shape to mask another:
- Only the intersecting area is visible
- The clip shape is invisible
- Useful for reveal effects, viewports

### Creating a Clip

1. Select shape to be clipped
2. Select clipping shape
3. Right-click → **Use as Clipping Source**
4. Or: Object → Clip → Set Clipping Source

### Clip Structure

```
Clipping Shape (invisible, defines mask)
└── Clipped Content (only visible inside clip)
    ├── Shape A
    ├── Shape B
    └── Group C
```

### Animated Clips

Animate the clip shape to create reveals:

```
Frame 0: Clip shape small/offscreen
Frame 30: Clip shape covers content
→ Content "wipes" into view
```

### Clip vs Opacity Mask

| Feature | Clipping | Opacity Mask |
|---------|----------|--------------|
| Edge | Hard | Can be soft |
| Based on | Shape | Alpha channel |
| Performance | Better | Heavier |

## Joysticks

### What is a Joystick?

A **Joystick** provides 2D input control (X/Y) that can drive:
- Bone rotations
- Property values
- Blend states

### Creating a Joystick

1. Insert → Joystick
2. Position the joystick control
3. Set handle bounds

### Joystick Properties

| Property | Description |
|----------|-------------|
| **X Range** | Min/Max X values |
| **Y Range** | Min/Max Y values |
| **Handle** | Draggable control point |
| **Bounds** | Movement limits |

### Connecting Joysticks

**To Bones:**
1. Select joystick
2. Select target bone
3. Map X/Y to rotation

**To Properties:**
1. Select joystick
2. In Inspector, add **Driven Property**
3. Map axis to property value

### Joystick Use Cases

| Use Case | X Axis | Y Axis |
|----------|--------|--------|
| **Eye look** | Left/Right | Up/Down |
| **Head turn** | Rotation | Tilt |
| **Character lean** | Side | Forward/Back |

## Solos

### What are Solos?

**Solos** allow only one child in a group to be visible at a time. Perfect for:
- Expression swapping
- State indicators
- Frame-by-frame animation

### Creating a Solo Group

1. Create a group
2. Add children (different states)
3. Select group → Enable **Solo** in Inspector

### Solo Behavior

```
Solo Group "Faces"
├── Happy 😊 (Solo Value: 0)
├── Sad 😢 (Solo Value: 1)
├── Angry 😠 (Solo Value: 2)
└── Surprised 😮 (Solo Value: 3)

Solo Value = 1 → Only "Sad" visible
```

### Animating Solos

1. Keyframe the **Solo** property on the group
2. Change Solo value to show different child
3. Instant switch (no blend)

## Trim Path

### What is Trim Path?

**Trim Path** animates the stroke of a path:
- Start/End points of visible stroke
- Offset (rotates the trim)
- Creates "drawing" effects

### Trim Path Properties

| Property | Range | Description |
|----------|-------|-------------|
| **Start** | 0-100% | Where stroke begins |
| **End** | 0-100% | Where stroke ends |
| **Offset** | 0-100% | Rotates trim position |

### Drawing Effect

```
Frame 0: Start=0%, End=0%
Frame 30: Start=0%, End=100%
→ Path "draws" itself
```

### Erasing Effect

```
Frame 0: Start=0%, End=100%
Frame 30: Start=100%, End=100%
→ Path "erases" from start
```

### Animated Dashes

Combine Trim Path with stroke dashes:
```
Stroke: Dashed
Trim Offset: Animated 0% → 100%
→ Dashes march along path
```

## Common Workflows

### Character Rigging

1. **Import/Create artwork**
   - Separate limbs into shapes
   - Organize hierarchy

2. **Create bone structure**
   - Root at hips/center
   - Chain for each limb
   - Consider IK needs

3. **Convert to meshes**
   - Convert deformable parts
   - Add subdivision where needed

4. **Bind and weight**
   - Bind meshes to bones
   - Paint weights for smooth bends

5. **Add constraints**
   - IK for legs/arms
   - Rotation limits

### Morphing Shapes

1. Create source shape
2. Convert to mesh
3. Keyframe vertex positions
4. Animate between positions

### Liquid/Organic Effects

1. Create base shape
2. Add dense mesh
3. Bind to multiple bones
4. Animate bones with overlap/follow-through

## Performance Considerations

| Feature | Performance Impact |
|---------|-------------------|
| Bones (simple) | Low |
| Bones (many) | Medium |
| Meshes (low poly) | Low |
| Meshes (high poly) | High |
| Clipping | Low |
| Nested clipping | Medium |

### Optimization Tips

1. **Meshes**: Use minimum vertices needed
2. **Bones**: Limit chain depth
3. **Weights**: Use auto-weights, refine manually
4. **Clipping**: Avoid deep nesting

## Troubleshooting

### Mesh Deformation Issues

- **Problem**: Pinching at joints
- **Solution**: Add more vertices at bend points, adjust weights

### Bone Binding Not Working

- **Problem**: Shape doesn't move with bone
- **Solution**: Verify binding, check weight values

### Clip Not Masking

- **Problem**: Content visible outside clip
- **Solution**: Verify clip parent-child relationship

### Joystick Not Responding

- **Problem**: Handle doesn't drive properties
- **Solution**: Check axis mapping, verify property connection

## See Also

- [Rive Constraints](./rive-constraints.md)
- [Rive Animation Mode](./rive-animation-mode.md)
- [Rive Editor Fundamentals](./rive-editor-fundamentals.md)

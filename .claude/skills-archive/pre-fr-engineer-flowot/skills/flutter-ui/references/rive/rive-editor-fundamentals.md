# Rive Editor Fundamentals Reference

Complete reference for the Rive Editor interface and core design concepts.

## Table of Contents

1. [Interface Overview](#interface-overview)
2. [Artboards](#artboards)
3. [Shapes and Paths](#shapes-and-paths)
4. [Fill and Stroke](#fill-and-stroke)
5. [Groups](#groups)
6. [Components](#components)
7. [Edit Vertices](#edit-vertices)
8. [Freeze and Origin](#freeze-and-origin)
9. [Importing Assets](#importing-assets)
10. [Revision History](#revision-history)
11. [Keyboard Shortcuts](#keyboard-shortcuts)

---

## Interface Overview

The Rive Editor consists of several key panels that work together:

### Hierarchy Panel (Left Side)

The Hierarchy shows the structure of your artboard:
- **Artboards**: Top-level containers for your designs
- **Objects**: All shapes, groups, bones, and other elements
- **Nesting**: Drag objects to reorder or nest them
- **Visibility**: Toggle eye icon to hide/show objects
- **Lock**: Toggle lock icon to prevent selection

### Stage (Center)

The main canvas where you design and animate:
- **Zoom**: Scroll wheel or `+`/`-` keys
- **Pan**: Hold `Space` and drag, or middle mouse button
- **Selection**: Click objects or drag to select multiple
- **Transform**: Use handles to move, scale, rotate

### Inspector Panel (Right Side)

Context-sensitive properties panel:
- **Transform**: Position, scale, rotation
- **Fill/Stroke**: Colors, gradients, stroke options
- **Object-Specific**: Properties unique to each object type

### Toolbar (Top)

- **Selection Tool** (`V`): Select and transform objects
- **Pen Tool** (`P`): Draw vector paths
- **Shape Tools**: Rectangle (`R`), Ellipse (`O`), Polygon, Star, Triangle
- **Text Tool** (`T`): Add text
- **Bone Tool** (`B`): Create skeletal rigs
- **Layout Tool** (`L`): Create responsive layouts

### Animations Panel (Bottom)

- **Timelines**: Listed animations
- **State Machines**: Interactive state graphs
- **Timeline View**: Keyframe editor when animation selected

---

## Artboards

Artboards are the top-level containers for your designs. Each artboard is an independent canvas that can be exported separately.

### Creating Artboards

1. **New Artboard**: Click `+` in Hierarchy or use toolbar
2. **Duplicate**: Right-click artboard → Duplicate
3. **From Selection**: Select objects → Create Artboard from Selection

### Artboard Properties

| Property | Description |
|----------|-------------|
| **Name** | Identifier used at runtime |
| **Width/Height** | Canvas dimensions in pixels |
| **Origin** | Coordinate system origin point |
| **Background** | Fill color (or transparent) |
| **Clip Contents** | Hide overflow content |

### Multiple Artboards

- Use multiple artboards for different screens, components, or variations
- Each artboard can have its own animations and state machines
- At runtime, select which artboard to display

### Artboard Origin

The origin determines where `(0, 0)` is located:
- **Center**: Origin at artboard center (default for most use cases)
- **Top-Left**: Origin at top-left corner (common for UI)

---

## Shapes and Paths

### Procedural Shapes

Built-in parametric shapes that remain editable:

| Shape | Shortcut | Properties |
|-------|----------|------------|
| **Rectangle** | `R` | Width, Height, Corner Radius |
| **Ellipse** | `O` | Width, Height |
| **Polygon** | - | Sides, Corner Radius |
| **Star** | - | Points, Inner Radius, Outer Radius |
| **Triangle** | - | Width, Height |

### Pen Tool Paths

Create custom vector paths with the Pen Tool (`P`):

1. **Click** to create corner points
2. **Click + Drag** to create curved points with handles
3. **Close Path**: Click on first point
4. **Open Path**: Press `Enter` or `Escape`

### Path Operations

| Operation | Description |
|-----------|-------------|
| **Add Points** | Click on path segment |
| **Delete Points** | Select point → `Delete` |
| **Convert Point** | Double-click to toggle corner/smooth |
| **Break Path** | Select point → Break Path |
| **Join Paths** | Select two endpoints → Join |

### Edit Vertices Mode

Enter edit mode to modify path points:
- Double-click a shape to enter vertex editing
- `Escape` to exit vertex editing
- Drag points to move them
- Drag handles to adjust curves

---

## Fill and Stroke

### Fill Types

| Type | Description |
|------|-------------|
| **Solid** | Single color with opacity |
| **Linear Gradient** | Gradient along a line |
| **Radial Gradient** | Gradient from center outward |
| **None** | Transparent fill |

### Gradient Controls

- **Add Stops**: Click on gradient bar
- **Move Stops**: Drag stops along bar
- **Delete Stops**: Drag stop off bar
- **Reposition**: Drag gradient handles on stage

### Stroke Properties

| Property | Description |
|----------|-------------|
| **Color** | Stroke color |
| **Thickness** | Line width in pixels |
| **Cap** | Butt, Round, Square |
| **Join** | Miter, Round, Bevel |
| **Dash** | Dash pattern and offset |

### Multiple Fills/Strokes

Objects can have multiple fills and strokes stacked:
- Click `+` to add additional fills/strokes
- Drag to reorder (top is rendered last)
- Each can have independent colors, gradients, blend modes

### Blend Modes

Available blend modes for fills and strokes:
- Normal, Multiply, Screen, Overlay
- Darken, Lighten, Color Dodge, Color Burn
- Hard Light, Soft Light, Difference, Exclusion
- Hue, Saturation, Color, Luminosity

---

## Groups

Groups organize objects and affect transform hierarchy.

### Creating Groups

1. Select objects
2. Press `Cmd/Ctrl + G` or right-click → Group

### Group Properties

| Property | Description |
|----------|-------------|
| **Name** | Group identifier |
| **Transform** | Position, scale, rotation |
| **Opacity** | Group-level opacity |
| **Clip** | Clip children to group bounds |

### Selecting and Navigating

- **Select Group**: Click any child
- **Enter Group**: Double-click or press `Enter`
- **Exit Group**: Click outside or press `Escape`
- **Direct Select**: `Cmd/Ctrl + Click` to select child directly

### Transform Spaces

Groups can use different transform spaces:
- **Local**: Transform relative to parent
- **World**: Transform relative to artboard

---

## Components

Components are reusable objects that can be instantiated multiple times.

### Creating Components

1. Select objects to include
2. Right-click → Create Component
3. Or use `Cmd/Ctrl + Shift + K`

### Component Instances

- **Create Instance**: Drag component from Assets or duplicate
- **Overrides**: Instances can override specific properties
- **Update All**: Editing source updates all instances

### Nested Components

Components can contain other component instances:
- Build complex designs from simple building blocks
- Changes propagate through the hierarchy
- Override nesting depth is preserved

### Component Best Practices

1. Name components clearly
2. Set up default state before creating
3. Use components for repeated elements
4. Consider runtime performance (fewer unique components = smaller file)

---

## Edit Vertices

### Entering Vertex Edit Mode

- Double-click any path or shape
- Or select and press `Enter`

### Vertex Operations

| Action | Method |
|--------|--------|
| **Move Point** | Drag the point |
| **Add Point** | Click on path segment |
| **Delete Point** | Select → `Delete` |
| **Corner ↔ Smooth** | Double-click point |
| **Adjust Handles** | Drag bezier handles |
| **Break Handles** | `Alt/Option` + drag handle |

### Path Types

- **Straight**: Point with no handles
- **Mirrored**: Handles move together symmetrically
- **Disconnected**: Handles move independently
- **Asymmetric**: One handle only

---

## Freeze and Origin

### Freeze Transform

"Freezing" resets an object's transform while keeping its visual position:
- Useful after rotating/scaling to reset local axes
- Right-click → Freeze Transform
- Or use Inspector → Freeze button

### Object Origin

Each object has an origin point for transforms:
- **Set Origin**: Select object → drag origin handle
- **Center Origin**: Right-click → Center Origin
- **Origin affects rotation and scale pivot point**

### Transform Order

Transforms apply in order:
1. Scale
2. Rotation
3. Translation

---

## Importing Assets

### Supported Formats

| Format | Type | Notes |
|--------|------|-------|
| **PNG** | Image | Supports transparency |
| **JPEG** | Image | Smaller file size |
| **WebP** | Image | Modern format |
| **SVG** | Vector | Converted to Rive paths |
| **Lottie** | Animation | Limited support |
| **Fonts** | Text | TTF, OTF, WOFF |

### Image Import

1. Drag image file onto stage
2. Or File → Import → Images
3. Images become embedded assets

### Image Properties

| Property | Description |
|----------|-------------|
| **Name** | Asset identifier |
| **Fit** | How image fits its bounds |
| **Mesh** | Enable mesh deformation |
| **Blend Mode** | Compositing mode |

### SVG Import

- Complex SVGs are converted to Rive paths
- Gradients and strokes are preserved when possible
- Groups become Rive groups
- Some effects may not convert perfectly

### Out-of-Band Assets

Assets can be loaded at runtime instead of embedded:
- Smaller `.riv` file size
- Dynamic asset swapping
- Set in Export settings

---

## Revision History

Rive automatically saves revision history:

### Accessing History

1. File → Revision History
2. Or click clock icon in toolbar

### History Features

| Feature | Description |
|---------|-------------|
| **Auto-Save** | Changes saved automatically |
| **Named Versions** | Create named snapshots |
| **Restore** | Revert to any previous version |
| **Compare** | View differences between versions |

### Best Practices

- Create named versions before major changes
- Use descriptive version names
- History is preserved in Rive's cloud

---

## Keyboard Shortcuts

### General

| Action | Mac | Windows |
|--------|-----|---------|
| Undo | `Cmd + Z` | `Ctrl + Z` |
| Redo | `Cmd + Shift + Z` | `Ctrl + Y` |
| Cut | `Cmd + X` | `Ctrl + X` |
| Copy | `Cmd + C` | `Ctrl + C` |
| Paste | `Cmd + V` | `Ctrl + V` |
| Delete | `Delete` | `Delete` |
| Select All | `Cmd + A` | `Ctrl + A` |
| Deselect | `Cmd + D` | `Ctrl + D` |

### Tools

| Tool | Shortcut |
|------|----------|
| Selection | `V` |
| Pen | `P` |
| Rectangle | `R` |
| Ellipse | `O` |
| Text | `T` |
| Bone | `B` |
| Layout | `L` |

### View

| Action | Mac | Windows |
|--------|-----|---------|
| Zoom In | `Cmd + +` | `Ctrl + +` |
| Zoom Out | `Cmd + -` | `Ctrl + -` |
| Fit to Screen | `Cmd + 1` | `Ctrl + 1` |
| 100% Zoom | `Cmd + 0` | `Ctrl + 0` |
| Pan | `Space + Drag` | `Space + Drag` |

### Objects

| Action | Mac | Windows |
|--------|-----|---------|
| Group | `Cmd + G` | `Ctrl + G` |
| Ungroup | `Cmd + Shift + G` | `Ctrl + Shift + G` |
| Bring Forward | `Cmd + ]` | `Ctrl + ]` |
| Send Backward | `Cmd + [` | `Ctrl + [` |
| Bring to Front | `Cmd + Shift + ]` | `Ctrl + Shift + ]` |
| Send to Back | `Cmd + Shift + [` | `Ctrl + Shift + [` |

### Animation

| Action | Mac | Windows |
|--------|-----|---------|
| Play/Pause | `Space` | `Space` |
| Go to Start | `Home` | `Home` |
| Go to End | `End` | `End` |
| Add Key | `K` | `K` |
| Previous Key | `,` | `,` |
| Next Key | `.` | `.` |

---

## Additional Resources

- Official Docs: https://rive.app/docs/editor/fundamentals/overview
- Community: https://community.rive.app
- YouTube: https://www.youtube.com/@Rive_app

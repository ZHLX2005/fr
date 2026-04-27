# Rive Scripting API Reference

Complete API documentation for Rive scripting in Luau.

## Table of Contents

1. [Animation](#animation)
2. [Artboard](#artboard)
3. [BlendMode](#blendmode)
4. [Color](#color)
5. [Context](#context)
6. [ContourMeasure](#contourmeasure)
7. [DataValue Types](#datavalue-types)
8. [Gradient](#gradient)
9. [Image](#image)
10. [Input](#input)
11. [Mat2D](#mat2d)
12. [Node](#node)
13. [Paint](#paint)
14. [Path](#path)
15. [PathCommand](#pathcommand)
16. [PathData](#pathdata)
17. [PathEffect](#patheffect)
18. [PathMeasure](#pathmeasure)
19. [PointerEvent](#pointerevent)
20. [Property Types](#property-types)
21. [Renderer](#renderer)
22. [StrokeCap](#strokecap)
23. [StrokeJoin](#strokejoin)
24. [Trigger](#trigger)
25. [Vector/Vec2D](#vectorvec2d)
26. [ViewModel](#viewmodel)

---

## Animation

Represents a Rive animation instance.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `duration` | `number` | Duration of the animation in seconds |

### Methods

#### `advance(seconds: number): boolean`
Advances the animation by given time. Returns `true` if animation hasn't ended (or loops).

#### `setTime(seconds: number)`
Sets animation time in seconds.

#### `setTimeFrames(frames: number)`
Sets animation time in frames.

#### `setTimePercentage(percentage: number)`
Sets animation time as percentage (0-1) of duration.

### Example

```lua
local anim = artboard:animation('Idle')
anim:setTime(0)

function advance(self: MyNode, seconds: number): boolean
  local playing = anim:advance(seconds)
  return playing
end
```

---

## Artboard

Represents a Rive artboard instance.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `frameOrigin` | `boolean` | If true, origin is at frame origin |
| `data` | `T` | Typed data (View Model) associated |
| `width` | `number` | Artboard width (read/write) |
| `height` | `number` | Artboard height (read/write) |

### Methods

#### `draw(renderer: Renderer)`
Draws the artboard using the provided renderer.

#### `advance(seconds: number): boolean`
Advances the artboard by time. Returns true to continue.

#### `instance(): Artboard<T>`
Creates a new independent instance.

#### `animation(name: string): Animation`
Gets animation by name.

#### `bounds(): (Vec2D, Vec2D)`
Returns min and max points of bounding box.

```lua
local minPt, maxPt = artboard:bounds()
local width = maxPt.x - minPt.x
local height = maxPt.y - minPt.y
```

#### `node(name: string): Node?`
Returns node by name, or nil.

#### `pointerDown(event: PointerEvent): number`
#### `pointerUp(event: PointerEvent): number`
#### `pointerMove(event: PointerEvent): number`
#### `pointerExit(event: PointerEvent): number`
Handle pointer events. Returns 0 if no hit.

#### `addToPath(path: Path, transform?: Mat2D)`
Adds artboard geometry to path.

---

## BlendMode

Enum for compositing modes.

| Value | Description |
|-------|-------------|
| `'srcOver'` | Source over destination (default) |
| `'screen'` | Screen blend |
| `'overlay'` | Overlay blend |
| `'darken'` | Darken blend |
| `'lighten'` | Lighten blend |
| `'colorDodge'` | Color dodge |
| `'colorBurn'` | Color burn |
| `'hardLight'` | Hard light |
| `'softLight'` | Soft light |
| `'difference'` | Difference |
| `'exclusion'` | Exclusion |
| `'multiply'` | Multiply |
| `'hue'` | Hue blend |
| `'saturation'` | Saturation blend |
| `'color'` | Color blend |
| `'luminosity'` | Luminosity blend |

---

## Color

Color representation (RGBA).

### Constructors

#### `Color.rgba(r: number, g: number, b: number, a: number): Color`
Creates color from RGBA values (0-255).

```lua
local red = Color.rgba(255, 0, 0, 255)
local semiTransparent = Color.rgba(255, 255, 255, 128)
```

#### `Color.rgb(r: number, g: number, b: number): Color`
Creates opaque color from RGB values.

```lua
local blue = Color.rgb(0, 0, 255)
```

#### `Color.hex(hexString: string): Color`
Creates color from hex string.

```lua
local purple = Color.hex('#FF00FF')
local withAlpha = Color.hex('#FF00FF80')
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `r` | `number` | Red component (0-255) |
| `g` | `number` | Green component (0-255) |
| `b` | `number` | Blue component (0-255) |
| `a` | `number` | Alpha component (0-255) |

---

## Context

Provides access to update scheduling and view model.

### Methods

#### `markNeedsUpdate()`
Marks the object as needing update on next frame.

#### `viewModel(): ViewModel`
Returns the context's view model for data binding.

```lua
function init(self: MyNode, context: Context): boolean
  self.context = context
  local vm = context:viewModel()
  local score = vm:getNumber('score')
  return true
end
```

---

## ContourMeasure

Measures a single path contour.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `length` | `number` | Total length of contour |
| `isClosed` | `boolean` | Whether contour is closed |
| `next` | `ContourMeasure?` | Next contour, or nil |

### Methods

#### `getPosition(distance: number): Vec2D`
Gets position at distance along contour.

#### `getTangent(distance: number): Vec2D`
Gets tangent direction at distance.

#### `getSegment(start: number, end: number): Path`
Extracts path segment between distances.

---

## DataValue Types

### DataValue

Base factory for creating data values.

#### `DataValue.number(): DataValueNumber`
#### `DataValue.string(): DataValueString`
#### `DataValue.boolean(): DataValueBoolean`
#### `DataValue.color(): DataValueColor`

### DataValueNumber

| Field | Type | Description |
|-------|------|-------------|
| `value` | `number` | The numeric value |

#### `isNumber(): boolean` - Returns true

### DataValueString

| Field | Type | Description |
|-------|------|-------------|
| `value` | `string` | The string value |

#### `isString(): boolean` - Returns true

### DataValueBoolean

| Field | Type | Description |
|-------|------|-------------|
| `value` | `boolean` | The boolean value |

#### `isBoolean(): boolean` - Returns true

### DataValueColor

| Field | Type | Description |
|-------|------|-------------|
| `value` | `Color` | The color value |

#### `isColor(): boolean` - Returns true

---

## Gradient

Gradient fill definitions.

### Constructors

#### `Gradient.linear(start: Vec2D, end: Vec2D, stops: {GradientStop}): Gradient`

```lua
local gradient = Gradient.linear(
  Vec2D.xy(0, 0),
  Vec2D.xy(100, 0),
  {
    GradientStop.new(0, Color.hex('#FF0000')),
    GradientStop.new(0.5, Color.hex('#00FF00')),
    GradientStop.new(1, Color.hex('#0000FF')),
  }
)
```

#### `Gradient.radial(center: Vec2D, radius: number, stops: {GradientStop}): Gradient`

```lua
local gradient = Gradient.radial(
  Vec2D.xy(50, 50),
  50,
  {
    GradientStop.new(0, Color.hex('#FFFFFF')),
    GradientStop.new(1, Color.hex('#000000')),
  }
)
```

### GradientStop

#### `GradientStop.new(position: number, color: Color): GradientStop`

| Field | Type | Description |
|-------|------|-------------|
| `position` | `number` | Position along gradient (0-1) |
| `color` | `Color` | Color at this stop |

---

## Image

Represents an image asset.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `width` | `number` | Image width in pixels |
| `height` | `number` | Image height in pixels |

---

## ImageSampler

Enum for image sampling modes.

| Value | Description |
|-------|-------------|
| `'nearest'` | Nearest neighbor (pixelated) |
| `'linear'` | Bilinear interpolation (smooth) |

---

## ImageFilter

Image filtering options.

| Value | Description |
|-------|-------------|
| `'none'` | No filtering |
| `'blur'` | Blur filter |

---

## Input

Wrapper for reactive input values.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `value` | `T` | Current value |

### Methods

#### `addListener(callback: () -> void)`
#### `addListener(value: T, callback: (T) -> void)`
Registers callback for value changes.

```lua
function init(self: MyNode): boolean
  self.speed:addListener(function()
    print("Speed changed!")
  end)
  
  self.position:addListener(self.position.value, function(pos)
    print("Position:", pos.x, pos.y)
  end)
  
  return true
end
```

#### `instance(): Artboard<T>` (For Artboard inputs)
Creates new artboard instance from template.

---

## Mat2D

2D transformation matrix (3x2).

### Constructors

#### `Mat2D.new(): Mat2D`
Creates identity matrix.

#### `Mat2D.fromTranslate(x: number, y: number): Mat2D`
```lua
local translate = Mat2D.fromTranslate(100, 50)
```

#### `Mat2D.fromScale(sx: number, sy: number): Mat2D`
```lua
local scale = Mat2D.fromScale(2, 2)
```

#### `Mat2D.fromRotation(radians: number): Mat2D`
```lua
local rotate = Mat2D.fromRotation(math.pi / 4)  -- 45 degrees
```

### Methods

#### `multiply(other: Mat2D): Mat2D`
Returns combined transformation.

#### `invert(): Mat2D?`
Returns inverse matrix, or nil if not invertible.

#### `transformPoint(point: Vec2D): Vec2D`
Applies transformation to point.

### Example

```lua
function draw(self: MyNode, renderer: Renderer)
  renderer:save()
  
  -- Combine transformations
  local transform = Mat2D.fromTranslate(100, 100)
  transform = transform:multiply(Mat2D.fromRotation(self.angle))
  transform = transform:multiply(Mat2D.fromScale(self.scale, self.scale))
  
  renderer:transform(transform)
  renderer:drawPath(self.path, self.paint)
  
  renderer:restore()
end
```

---

## Node

Protocol definition for Node scripts.

### Type Definition

```lua
type Node<T> = {
  init: (self: T) -> boolean,
  advance: ((self: T, seconds: number) -> boolean)?,
  update: ((self: T) -> void)?,
  draw: (self: T, renderer: Renderer) -> void,
  pointerDown: ((self: T, event: PointerEvent) -> void)?,
  pointerUp: ((self: T, event: PointerEvent) -> void)?,
  pointerMove: ((self: T, event: PointerEvent) -> void)?,
  pointerExit: ((self: T, event: PointerEvent) -> void)?,
  [string]: any,  -- Input defaults
}
```

### Lifecycle Functions

| Function | When Called | Purpose |
|----------|-------------|---------|
| `init` | Once at start | Setup, return true to proceed |
| `advance` | Every frame | Animation logic, return true to continue |
| `update` | When inputs change | Respond to input changes |
| `draw` | Every frame after advance | Render content |

---

## Paint

Describes how shapes are drawn.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `style` | `'fill' \| 'stroke'` | Paint style |
| `color` | `Color` | Solid color |
| `gradient` | `Gradient?` | Gradient fill |
| `thickness` | `number` | Stroke thickness |
| `cap` | `StrokeCap` | Line end style |
| `join` | `StrokeJoin` | Corner style |
| `blendMode` | `BlendMode` | Compositing mode |
| `feather` | `number` | Feathering amount |

### Constructors

#### `Paint.new(): Paint`
Creates default paint (black fill).

#### `Paint.with(definition: PaintDefinition): Paint`
Creates paint from definition table.

```lua
local stroke = Paint.with({
  style = 'stroke',
  color = Color.hex('#FF0000'),
  thickness = 3,
  cap = 'round',
  join = 'round',
})
```

### Methods

#### `copy(overrides?: PaintDefinition): Paint`
Copies paint with optional overrides.

```lua
local filled = stroke:copy({ style = 'fill' })
```

---

## Path

Vector path for drawing shapes.

### Constructors

#### `Path.new(): Path`
Creates empty path.

### Methods

#### `moveTo(point: Vec2D)`
Starts new contour at point.

#### `lineTo(point: Vec2D)`
Draws line to point.

#### `quadTo(control: Vec2D, end: Vec2D)`
Draws quadratic Bezier curve.

#### `cubicTo(controlOut: Vec2D, controlIn: Vec2D, end: Vec2D)`
Draws cubic Bezier curve.

#### `close()`
Closes current contour.

#### `reset()`
Clears all path data. **Only reset after drawPath has been called.**

#### `add(other: Path, transform?: Mat2D)`
Adds another path.

#### `contours(): ContourMeasure?`
Returns measure for first contour.

#### `measure(): PathMeasure`
Returns measure for entire path.

#### `#path` (length operator)
Returns number of commands.

### Example: Drawing a Star

```lua
function drawStar(cx: number, cy: number, outerRadius: number, innerRadius: number, points: number): Path
  local path = Path.new()
  local angleStep = math.pi / points
  
  for i = 0, points * 2 - 1 do
    local radius = (i % 2 == 0) and outerRadius or innerRadius
    local angle = i * angleStep - math.pi / 2
    local x = cx + math.cos(angle) * radius
    local y = cy + math.sin(angle) * radius
    
    if i == 0 then
      path:moveTo(Vec2D.xy(x, y))
    else
      path:lineTo(Vec2D.xy(x, y))
    end
  end
  
  path:close()
  return path
end
```

---

## PathCommand

Represents a single path drawing command.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | `CommandType` | Command type |
| `point` | `Vec2D` | End point |
| `control1` | `Vec2D?` | First control point |
| `control2` | `Vec2D?` | Second control point |

### CommandType

| Value | Description |
|-------|-------------|
| `'move'` | Move to point |
| `'line'` | Line to point |
| `'quad'` | Quadratic curve |
| `'cubic'` | Cubic curve |
| `'close'` | Close contour |

---

## PathData

Read-only path data for PathEffect scripts.

### Indexing

```lua
for i = 1, #pathData do
  local cmd = pathData[i]
  -- cmd is PathCommand
end
```

---

## PathEffect

Protocol for PathEffect scripts.

### Type Definition

```lua
type PathEffect<T> = {
  init: ((self: T, context: Context) -> boolean)?,
  update: (self: T, pathData: PathData) -> PathData,
  advance: ((self: T, seconds: number) -> boolean)?,
  [string]: any,
}
```

---

## PathMeasure

Measures entire path across all contours.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `length` | `number` | Total path length |

### Methods

#### `getPosition(distance: number): Vec2D`
#### `getTangent(distance: number): Vec2D`
#### `getSegment(start: number, end: number): Path`

---

## PointerEvent

Mouse/touch event data.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | `number` | Pointer identifier (for multi-touch) |
| `position` | `Vec2D` | Position in local coordinates |

### Methods

#### `hit(passthrough?: boolean)`
Marks event as handled. If `passthrough` is true, allows event to continue to translucent elements.

### Constructors

#### `PointerEvent.new(id: number, position: Vec2D): PointerEvent`
For forwarding events to nested artboards.

---

## Property Types

For View Model data binding.

### Property<T>

| Field | Type | Description |
|-------|------|-------------|
| `value` | `T` | Property value |

#### `addListener(callback: () -> void)`

### PropertyEnum

| Field | Type | Description |
|-------|------|-------------|
| `value` | `EnumValue` | Current enum value |
| `values` | `EnumValues` | All possible values |

### PropertyList<T>

For list data.

#### `count(): number`
#### `get(index: number): T`
#### `add(): T`
#### `remove(index: number)`

### PropertyTrigger

#### `fire()`
Fires the trigger.

#### `addListener(callback: () -> void)`

### PropertyViewModel

Reference to nested view model.

---

## Renderer

Provides drawing functions.

### Methods

#### `drawPath(path: Path, paint: Paint)`
Draws path with paint.

#### `drawImage(image: Image, sampler: ImageSampler, blendMode: BlendMode, opacity: number)`
Draws image.

#### `drawImageMesh(image: Image, vertices: {Vec2D}, uvs: {Vec2D}, indices: {number}, sampler: ImageSampler, blendMode: BlendMode, opacity: number)`
Draws image with mesh deformation.

#### `clipPath(path: Path)`
Restricts drawing to path area until restore.

#### `save()`
Saves current state (transform, clip).

#### `restore()`
Restores last saved state.

#### `transform(matrix: Mat2D)`
Applies transformation matrix.

---

## StrokeCap

Line ending styles.

| Value | Description |
|-------|-------------|
| `'butt'` | Flat end at point |
| `'round'` | Rounded end |
| `'square'` | Square end extending past point |

---

## StrokeJoin

Corner join styles.

| Value | Description |
|-------|-------------|
| `'miter'` | Sharp corner |
| `'round'` | Rounded corner |
| `'bevel'` | Flat corner |

---

## Trigger

For triggering events/actions.

#### `fire()`
Fires the trigger.

---

## Vector/Vec2D

2D vector.

### Constructors

#### `Vec2D.xy(x: number, y: number): Vec2D`
#### `Vector.xy(x: number, y: number): Vec2D`

```lua
local pos = Vec2D.xy(100, 50)
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `x` | `number` | X component |
| `y` | `number` | Y component |

### Operations

Vectors support arithmetic operations:

```lua
local a = Vec2D.xy(10, 20)
local b = Vec2D.xy(5, 10)

local sum = a + b        -- Vec2D(15, 30)
local diff = a - b       -- Vec2D(5, 10)
local scaled = a * 2     -- Vec2D(20, 40)
local divided = a / 2    -- Vec2D(5, 10)
```

---

## ViewModel

Access to View Model data.

### Methods

#### `getNumber(name: string): Property<number>?`
#### `getString(name: string): Property<string>?`
#### `getBoolean(name: string): Property<boolean>?`
#### `getColor(name: string): Property<Color>?`
#### `getEnum(name: string): PropertyEnum?`
#### `getList(name: string): PropertyList?`
#### `getTrigger(name: string): PropertyTrigger?`
#### `getViewModel(name: string): PropertyViewModel?`

```lua
function init(self: MyNode, context: Context): boolean
  local vm = context:viewModel()
  
  local health = vm:getNumber('health')
  if health then
    health.value = 100
    health:addListener(function()
      print("Health changed to:", health.value)
    end)
  end
  
  local onClick = vm:getTrigger('onClick')
  if onClick then
    onClick:addListener(function()
      print("Clicked!")
    end)
  end
  
  return true
end
```

---

## Layout Protocol

Extension of Node for layout scripts.

### Type Definition

```lua
type Layout<T> = Node<T> & {
  measure: ((self: T) -> Vec2D)?,
  resize: (self: T, size: Vec2D) -> void,
}
```

### Functions

#### `measure(self: T): Vec2D`
Returns desired size. Used when Fit is Hug.

#### `resize(self: T, size: Vec2D)`
Called when layout receives new size.

---

## Converter Protocol

For data transformation scripts.

### Type Definition

```lua
type Converter<T, TInput, TOutput> = {
  init: ((self: T) -> boolean)?,
  convert: (self: T, input: TInput) -> TOutput,
  reverseConvert: ((self: T, input: TOutput) -> TInput)?,
}
```

---

## Utility Functions

### `late<T>(): T`
Marks input as assigned at runtime.

```lua
return function(): Node<MyNode>
  return {
    myArtboard = late(),  -- Will be set in Editor
  }
end
```

### `print(...)`
Debug output to console.

```lua
print("Debug:", value, "at position:", x, y)
```

### `table` functions

Standard Lua table functions are available:

```lua
table.insert(array, value)
table.remove(array, index)
-- etc.
```

### `math` functions

Standard Lua math functions:

```lua
math.sin(x)
math.cos(x)
math.tan(x)
math.sqrt(x)
math.abs(x)
math.floor(x)
math.ceil(x)
math.min(a, b)
math.max(a, b)
math.random()
math.pi
-- etc.
```

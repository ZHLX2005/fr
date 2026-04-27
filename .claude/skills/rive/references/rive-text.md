# Rive Text Reference

> Official docs: https://rive.app/docs/editor/text/

## Overview

Rive provides comprehensive text support including:
- Multiple font embedding options
- Text Runs for runtime text updates
- Text Styles for reusable formatting
- Text Modifiers for dynamic effects

## Creating Text

### Adding Text

1. Select **Text Tool** (T key)
2. Click on artboard to place text
3. Type your content
4. Press **Escape** to finish editing

### Text Properties

| Property | Description |
|----------|-------------|
| **Content** | The text string |
| **Font** | Selected typeface |
| **Size** | Font size in pixels |
| **Line Height** | Vertical spacing |
| **Letter Spacing** | Horizontal spacing |
| **Alignment** | Left, Center, Right, Justify |
| **Paragraph Spacing** | Space between paragraphs |

## Fonts

### Adding Fonts

**Method 1: Drag & Drop**
1. Drag font file (.ttf, .otf, .woff) into Rive
2. Font appears in Assets panel

**Method 2: Assets Panel**
1. Open Assets panel
2. Click **+** → Import Font
3. Select font file

### Supported Font Formats

| Format | Support |
|--------|---------|
| **TTF** | ✅ Full |
| **OTF** | ✅ Full |
| **WOFF** | ✅ Full |
| **WOFF2** | ✅ Full |
| **Variable Fonts** | ✅ Supported |

### Font Embedding Options

| Option | File Size | Use Case |
|--------|-----------|----------|
| **Embedded** | Larger | Offline, guaranteed |
| **Referenced** | Smaller | Web, CDN fonts |

### Setting Up Referenced Fonts

1. Don't embed font in Rive file
2. Load font at runtime before Rive
3. Rive will use system/loaded font

```javascript
// Load font before Rive
await document.fonts.load('16px "Custom Font"');

// Then initialize Rive
const rive = new Rive({
  src: 'animation.riv',
  // ...
});
```

### Font Fallbacks

Rive supports fallback fonts:
1. Primary font attempts to render
2. If glyph missing, fallback font used
3. Configure in Assets panel

## Text Runs

### What are Text Runs?

**Text Runs** mark sections of text that can be updated at runtime:
- Change text content dynamically
- Update specific portions of text
- Bind to View Model properties

### Creating Text Runs

1. Select text object
2. Highlight text portion
3. Click **Create Run** in Inspector
4. Name the run (e.g., "username", "score")

### Text Run Structure

```
"Hello, [username]! Your score is [score]."
         ↑                        ↑
      Run: username            Run: score
```

### Runtime Text Updates

**JavaScript:**
```javascript
const rive = new Rive({
  src: 'greeting.riv',
  canvas: document.getElementById('canvas'),
  autoplay: true,
  onLoad: () => {
    // Get text run
    const artboard = rive.artboard;
    const textRun = artboard.textRun('username');
    
    // Update text
    textRun.text = 'John';
  }
});
```

**React:**
```tsx
import { useRive } from '@rive-app/react-canvas';
import { useEffect } from 'react';

function Greeting({ username }: { username: string }) {
  const { rive, RiveComponent } = useRive({
    src: 'greeting.riv',
    autoplay: true,
  });

  useEffect(() => {
    if (!rive) return;
    const textRun = rive.artboard.textRun('username');
    if (textRun) {
      textRun.text = username;
    }
  }, [rive, username]);

  return <RiveComponent />;
}
```

**Flutter:**
```dart
class DynamicText extends StatefulWidget {
  final String username;
  
  const DynamicText({required this.username});
  
  @override
  _DynamicTextState createState() => _DynamicTextState();
}

class _DynamicTextState extends State<DynamicText> {
  Artboard? _artboard;

  void _onRiveInit(Artboard artboard) {
    _artboard = artboard;
    _updateText();
  }

  void _updateText() {
    final textRun = _artboard?.textRun('username');
    textRun?.text = widget.username;
  }

  @override
  void didUpdateWidget(DynamicText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateText();
  }

  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/greeting.riv',
      onInit: _onRiveInit,
    );
  }
}
```

## Text Styles

### What are Text Styles?

**Text Styles** are reusable formatting presets:
- Apply consistent formatting
- Change multiple text objects at once
- Organize typography

### Creating Text Styles

1. Open **Assets** panel
2. Click **+** → Text Style
3. Configure properties
4. Name it (e.g., "Heading", "Body", "Caption")

### Text Style Properties

| Property | Description |
|----------|-------------|
| **Font** | Typeface |
| **Size** | Font size |
| **Weight** | Light, Regular, Bold, etc. |
| **Color** | Text fill color |
| **Line Height** | Vertical spacing |
| **Letter Spacing** | Character spacing |

### Applying Text Styles

1. Select text object
2. In Inspector, find **Style** dropdown
3. Select style to apply

### Style Overrides

After applying a style, you can override specific properties:
- Override appears as modified in Inspector
- Reset to style by clicking reset icon

## Text Modifiers

### What are Text Modifiers?

**Text Modifiers** apply dynamic effects to text:
- Character-by-character animation
- Procedural effects
- Custom transformations

### Built-in Modifiers

| Modifier | Effect |
|----------|--------|
| **Range** | Affect subset of characters |
| **Wave** | Sinusoidal motion |
| **Shake** | Random jitter |
| **Typewriter** | Reveal characters over time |

### Applying Modifiers

1. Select text object
2. In Inspector, find **Modifiers**
3. Click **+** to add modifier
4. Configure parameters

### Modifier Parameters (Wave Example)

| Parameter | Description |
|-----------|-------------|
| **Amplitude** | Wave height |
| **Frequency** | Wave speed |
| **Offset** | Phase shift per character |
| **Axis** | X, Y, or both |

### Stacking Modifiers

Multiple modifiers can stack:
```
Text "Hello World"
├── Modifier: Wave (Y axis)
├── Modifier: Rotation wobble
└── Modifier: Opacity fade
```

## Animating Text

### Animatable Properties

| Property | How to Animate |
|----------|----------------|
| **Content** | Via Text Runs + runtime |
| **Color** | Keyframe fill color |
| **Size** | Keyframe font size |
| **Position** | Keyframe transform |
| **Opacity** | Keyframe opacity |
| **Modifier params** | Keyframe modifier values |

### Text Animation Patterns

**Fade In:**
```
Frame 0: Opacity = 0
Frame 20: Opacity = 1
```

**Scale Pop:**
```
Frame 0: Scale = 0
Frame 15: Scale = 1.1
Frame 20: Scale = 1.0
```

**Typewriter Effect:**
```
Modifier: Range (0 to N)
Animate Range end from 0 → text length
```

## Text with Data Binding

### Binding Text to View Model

1. Create View Model with String property
2. Select text object
3. Bind content to property
4. Update View Model at runtime

```javascript
// View Model: MessageVM { message: String }

const viewModel = rive.viewModelInstance('MessageVM');
viewModel.setString('message', 'New notification!');
// Text automatically updates
```

### Binding Text Runs to View Model

Text Runs can also bind to View Model properties for more granular control.

## Text Alignment

### Horizontal Alignment

| Value | Behavior |
|-------|----------|
| **Left** | Align to left edge |
| **Center** | Center horizontally |
| **Right** | Align to right edge |
| **Justify** | Stretch to fill width |

### Vertical Alignment

| Value | Behavior |
|-------|----------|
| **Top** | Align to top |
| **Middle** | Center vertically |
| **Bottom** | Align to bottom |

### Text Box Sizing

| Mode | Behavior |
|------|----------|
| **Auto Width** | Box fits content |
| **Fixed Width** | Text wraps at width |
| **Fixed Size** | Both width and height fixed |

## Multi-language Support

### Unicode Support

Rive fully supports Unicode:
- Latin, Cyrillic, Greek
- CJK (Chinese, Japanese, Korean)
- Arabic, Hebrew (RTL)
- Emoji

### Right-to-Left (RTL)

For RTL languages:
1. Select text object
2. Enable **RTL** in Inspector
3. Text flows right-to-left

### Font Requirements

Ensure fonts include glyphs for target languages:
- Embedded fonts must include all needed glyphs
- Missing glyphs show as □ or fallback

## Performance Tips

### Font Optimization

1. **Subset fonts**: Only embed used characters
2. **Share fonts**: Reuse across text objects
3. **System fonts**: Use referenced fonts when possible

### Animation Performance

1. **Limit modifiers**: Each adds computation
2. **Reduce text changes**: Batch runtime updates
3. **Cache text runs**: Don't query repeatedly

## Troubleshooting

### Text Not Displaying

1. Check font is embedded/loaded
2. Verify text color isn't transparent
3. Check text isn't clipped by bounds

### Wrong Font Rendering

1. Verify font file is correct format
2. Check font weight matches
3. Ensure font is loaded before Rive init

### Text Run Not Updating

1. Verify run name matches exactly
2. Check text object exists on artboard
3. Ensure Rive instance is loaded

### Alignment Issues

1. Check text box sizing mode
2. Verify alignment settings
3. Consider container/layout constraints

## See Also

- [Rive Data Binding](./rive-data-binding.md)
- [Rive Animation Mode](./rive-animation-mode.md)
- [Rive React Runtime](./rive-react-runtime.md)

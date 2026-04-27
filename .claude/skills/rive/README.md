# Rive Skills for Claude

Comprehensive Claude Code skills for working with the [Rive](https://rive.app) interactive animation platform.

## Overview

This skill package provides Claude with deep knowledge of the entire Rive platform:

- **Rive Editor** - Artboards, shapes, constraints, layouts, text, animation mode
- **Rive Scripting (Luau)** - All protocol types (Node, Layout, Converter, PathEffect, Test)
- **State Machines** - States, inputs, transitions, listeners, layers
- **Data Binding** - View Models, lists, converters, runtime data binding
- **Events** - Rive events, audio events, runtime event handling
- **Web Runtimes** - React/Next.js, vanilla JS, Canvas, WebGL
- **Mobile Runtimes** - Flutter, iOS (Swift), Android (Kotlin), React Native
- **Game Runtimes** - Unity, Unreal Engine, Defold

## Installation

### Option 1: Using npx (Recommended)

Install via [skills.sh](https://skills.sh) - the skills package manager by Vercel:

```bash
npx skills add bowtiedswan/rive-skills
```

### Option 2: Clone and Install Locally

```bash
# Clone the repository
git clone https://github.com/bowtiedswan/rive-skills.git

# Copy to Claude skills directory
cp -r rive-skills ~/.claude/skills/
```

### Option 3: Manual Installation

1. Download the repository
2. Copy the `rive-skills` folder to `~/.claude/skills/`

## Skill Contents

```
rive-skills/
├── SKILL.md                                    # Main skill file
├── README.md                                   # This file
└── references/
    ├── rive-scripting-api.md                   # Complete Luau scripting API
    ├── rive-react-runtime.md                   # React/Next.js runtime
    ├── rive-editor-fundamentals.md             # Editor interface & basics
    ├── rive-animation-mode.md                  # Timeline, keys, easing
    ├── rive-state-machine.md                   # States, inputs, transitions
    ├── rive-constraints.md                     # All constraint types
    ├── rive-layouts.md                         # Flexbox layouts, N-Slicing
    ├── rive-manipulating-shapes.md             # Bones, meshes, clipping
    ├── rive-text.md                            # Fonts, text runs, modifiers
    ├── rive-events.md                          # Rive & audio events
    ├── rive-data-binding.md                    # View Models & data binding
    ├── rive-web-runtime.md                     # Vanilla JS, WASM, Canvas/WebGL
    ├── rive-flutter-runtime.md                 # Flutter widgets & controllers
    ├── rive-mobile-runtimes.md                 # iOS, Android, React Native
    └── rive-game-runtimes.md                   # Unity, Unreal, Defold
```

## Reference Guides

### Editor Features

| Reference | Topics Covered |
|-----------|----------------|
| **Editor Fundamentals** | Interface, artboards, shapes, fills, groups, components, keyboard shortcuts |
| **Animation Mode** | Timeline, playhead, keyframes, interpolation, easing, animation mixing |
| **State Machine** | States, inputs (boolean/number/trigger), transitions, listeners, layers |
| **Constraints** | IK, Distance, Scale, Rotation, Transform, Translation, Follow Path, Scroll |
| **Layouts** | Flexbox system, alignment, padding, gap, N-Slicing, scrolling |
| **Manipulating Shapes** | Bones, meshes, vertex weights, clipping, joysticks, solos, trim path |
| **Text** | Fonts, text runs, text styles, text modifiers, runtime text updates |
| **Events** | Rive events, audio events, custom properties, runtime listening |
| **Data Binding** | View Models, property types, instances, lists, converters, runtime access |

### Runtimes

| Reference | Platforms |
|-----------|-----------|
| **Scripting API** | Luau scripting (Node, Layout, Converter, PathEffect protocols) |
| **React Runtime** | React, Next.js, `@rive-app/react-canvas` hooks |
| **Web Runtime** | Vanilla JS, Canvas 2D, WebGL, WASM optimization |
| **Flutter Runtime** | `RiveAnimation`, `StateMachineController`, widgets |
| **Mobile Runtimes** | iOS (Swift/SwiftUI), Android (Kotlin), React Native |
| **Game Runtimes** | Unity (C#), Unreal Engine (C++/Blueprint), Defold (Lua) |

## What This Skill Enables

When loaded, Claude can help you with:

### Rive Editor
- Navigate the Rive interface and tools
- Create and organize artboards, shapes, and components
- Set up constraints (IK, Follow Path, etc.)
- Build responsive layouts with Flexbox-like system
- Work with bones, meshes, and deformations
- Configure text with fonts, runs, and modifiers

### Animation Design
- Create timeline animations with keyframes and easing
- Build state machines with complex transition logic
- Set up data binding with View Models
- Implement events for app communication
- Design scroll-based and interactive animations

### Runtime Integration
- Integrate Rive into React/Next.js applications
- Use vanilla JavaScript with Canvas or WebGL
- Build Flutter apps with Rive animations
- Develop iOS and Android native apps
- Create games with Unity, Unreal, or Defold

### Scripting
- Write Node scripts for custom rendering
- Create Layout scripts for custom positioning
- Build Converter scripts for data transformation
- Implement PathEffect scripts for procedural paths
- Handle pointer events and user interactions

## Usage Examples

Once installed, Claude will automatically use this skill when you ask about Rive:

```
"Help me create a scroll-based animation with Rive in Next.js"

"Write a Rive Node script that draws a custom particle system"

"How do I set up IK constraints for a character rig?"

"Implement data binding with View Models in Flutter"

"Create a state machine with hover and click states"

"How do I handle Rive events in Unity?"
```

## Documentation Sources

This skill is based on official Rive documentation:

- [Rive Editor Docs](https://rive.app/docs/editor)
- [Rive Scripting Docs](https://rive.app/docs/scripting)
- [Rive Runtime Docs](https://rive.app/docs/runtimes)
- [Rive Game Runtime Docs](https://rive.app/docs/game-runtimes)

## Contributing

Contributions are welcome! If you find missing API methods or have improvements:

1. Fork the repository
2. Make your changes
3. Submit a pull request

## License

MIT License - Feel free to use and modify.

## Author

Created by [@bowtiedswan](https://github.com/bowtiedswan)

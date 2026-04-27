# Rive Data Binding Reference

> Official docs: https://rive.app/docs/editor/data-binding/

## Overview

**Data Binding** is Rive's modern approach to connecting runtime data with animations. It uses **View Models** to define data structures that can be bound to any property in your Rive file and updated at runtime.

> 💡 **Recommendation**: Data Binding with View Models is preferred over traditional State Machine Inputs for most use cases.

## Core Concepts

### View Model

A **View Model** is a data schema that defines:
- Properties (name + type)
- Nested View Models
- Lists of items

### View Model Instance

An **Instance** is a concrete set of values conforming to a View Model schema. Think of View Models as classes and Instances as objects.

### Binding

A **Binding** connects a View Model property to an element property (text content, color, position, visibility, etc.)

## Creating View Models

### In the Editor

1. Open **Data Binding** panel (bottom of hierarchy)
2. Click **+** to create View Model
3. Name it (e.g., "UserProfile", "ButtonState")
4. Add properties

### Property Types

| Type | Description | Example |
|------|-------------|---------|
| **Number** | Float value | `progress: 0.75` |
| **String** | Text value | `username: "John"` |
| **Boolean** | True/False | `isActive: true` |
| **Color** | RGBA color | `accentColor: #FF5500` |
| **Enum** | Predefined options | `status: ["active", "inactive"]` |
| **Trigger** | One-shot signal | `onClick` |
| **List** | Array of items | `menuItems: [...]` |
| **View Model** | Nested data | `user: UserVM` |

### Example View Model Structure

```
UserCardVM
├── username (String)
├── avatarUrl (String)  
├── isOnline (Boolean)
├── statusColor (Color)
├── level (Number)
├── badges (List<BadgeVM>)
└── settings (SettingsVM)

BadgeVM
├── name (String)
├── icon (String)
└── rarity (Enum: common, rare, epic)

SettingsVM
├── darkMode (Boolean)
└── notifications (Boolean)
```

## Creating Instances

### Default Instance

Every View Model has a **default instance** with initial values:

1. Select View Model in Data Binding panel
2. Set default values in Inspector
3. These values are used when no runtime data provided

### Multiple Instances

Create named instances for different states:

```
ButtonVM (View Model)
├── Instance: "default" (normal state)
├── Instance: "hovered" (hover state)  
├── Instance: "pressed" (pressed state)
└── Instance: "disabled" (disabled state)
```

## Binding Properties

### How to Bind

1. Select element in hierarchy
2. Find property in Inspector
3. Click **bind icon** (chain link)
4. Select View Model property

### Bindable Properties

| Element | Bindable Properties |
|---------|---------------------|
| **Text** | Content, Color, Size |
| **Shape** | Fill, Stroke, Opacity, Position |
| **Layout** | Width, Height, Padding, Gap |
| **Group** | Visibility, Opacity |
| **Any** | Transform (X, Y, Rotation, Scale) |

### Bind Expression

Some bindings support expressions:

```
// Simple binding
text.content = viewModel.username

// Expression binding
text.content = viewModel.firstName + " " + viewModel.lastName

// Conditional
shape.opacity = viewModel.isActive ? 1.0 : 0.5
```

## Converters

**Converters** transform data between View Model and bound property.

### Built-in Converters

| Converter | Input | Output | Use Case |
|-----------|-------|--------|----------|
| **Number to String** | 42 | "42" | Display numbers as text |
| **Boolean to Number** | true | 1.0 | Animate based on bool |
| **Enum to Number** | "active" | 0 | Drive blend states |

### Custom Converters (Scripting)

```lua
-- In Rive Script
@Converter
function healthToColor(health)
  if health > 70 then
    return Color.green
  elseif health > 30 then
    return Color.yellow
  else
    return Color.red
  end
end
```

## Lists

### Creating List Properties

1. Add property with type **List**
2. Specify item View Model type
3. Items will be instances of that View Model

### List Binding

Bind lists to repeating content:

```
MenuVM
└── items (List<MenuItemVM>)

MenuItemVM
├── label (String)
├── icon (String)
└── isSelected (Boolean)
```

### List Rendering

In Rive, lists populate **layout containers**:
1. Create layout to hold list items
2. Create template for single item
3. Bind layout's children to list property
4. Runtime replicates template for each item

## Runtime Access

### JavaScript/Web

```javascript
import { Rive } from '@rive-app/canvas';

const rive = new Rive({
  src: 'dashboard.riv',
  canvas: document.getElementById('canvas'),
  stateMachines: 'Main',
  autoplay: true,
  onLoad: () => {
    // Get View Model instance
    const viewModel = rive.viewModelInstance('UserCard');
    
    // Set string property
    viewModel.setString('username', 'John Doe');
    
    // Set number property
    viewModel.setNumber('level', 42);
    
    // Set boolean property
    viewModel.setBoolean('isOnline', true);
    
    // Set color property (hex string or RGBA)
    viewModel.setColor('statusColor', '#00FF00');
    
    // Fire trigger
    viewModel.fireTrigger('refresh');
    
    // Get current values
    const username = viewModel.getString('username');
    const level = viewModel.getNumber('level');
    const isOnline = viewModel.getBoolean('isOnline');
  }
});
```

### React

```tsx
import { useRive, useViewModel } from '@rive-app/react-canvas';
import { useEffect } from 'react';

function UserCard({ user }: { user: User }) {
  const { rive, RiveComponent } = useRive({
    src: 'user-card.riv',
    stateMachines: 'Card State Machine',
    autoplay: true,
  });

  // Get View Model instance
  const viewModel = useViewModel(rive, 'UserCardVM');

  // Sync React state → Rive View Model
  useEffect(() => {
    if (!viewModel) return;
    
    viewModel.setString('username', user.name);
    viewModel.setNumber('level', user.level);
    viewModel.setBoolean('isOnline', user.isOnline);
    viewModel.setString('avatarUrl', user.avatar);
  }, [viewModel, user]);

  return <RiveComponent />;
}
```

### React - Two-Way Binding

```tsx
function Counter() {
  const [count, setCount] = useState(0);
  const { rive, RiveComponent } = useRive({
    src: 'counter.riv',
    stateMachines: 'Counter',
    autoplay: true,
  });

  const viewModel = useViewModel(rive, 'CounterVM');

  // Sync to Rive
  useEffect(() => {
    viewModel?.setNumber('count', count);
  }, [viewModel, count]);

  // Listen for Rive changes
  useEffect(() => {
    if (!viewModel) return;
    
    const unsubscribe = viewModel.onPropertyChange('count', (newValue) => {
      setCount(newValue);
    });
    
    return unsubscribe;
  }, [viewModel]);

  return (
    <div>
      <RiveComponent />
      <button onClick={() => setCount(c => c + 1)}>Increment</button>
    </div>
  );
}
```

### Flutter

```dart
import 'package:rive/rive.dart';

class DataBoundWidget extends StatefulWidget {
  final UserData userData;
  
  const DataBoundWidget({required this.userData});
  
  @override
  _DataBoundWidgetState createState() => _DataBoundWidgetState();
}

class _DataBoundWidgetState extends State<DataBoundWidget> {
  RiveViewModel? _viewModel;

  void _onRiveInit(Artboard artboard) {
    final controller = StateMachineController.fromArtboard(artboard, 'Main');
    if (controller != null) {
      artboard.addController(controller);
      
      // Get View Model instance
      _viewModel = controller.viewModelInstance('UserCardVM');
      _updateViewModel();
    }
  }

  void _updateViewModel() {
    if (_viewModel == null) return;
    
    _viewModel!.setString('username', widget.userData.name);
    _viewModel!.setNumber('level', widget.userData.level.toDouble());
    _viewModel!.setBoolean('isOnline', widget.userData.isOnline);
  }

  @override
  void didUpdateWidget(DataBoundWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateViewModel();
  }

  @override
  Widget build(BuildContext context) {
    return RiveAnimation.asset(
      'assets/user_card.riv',
      stateMachines: ['Main'],
      onInit: _onRiveInit,
    );
  }
}
```

### Unity (C#)

```csharp
using Rive;
using UnityEngine;

public class DataBoundAnimation : MonoBehaviour
{
    private RiveWidget riveWidget;
    private RiveViewModel viewModel;

    [SerializeField] private string username = "Player";
    [SerializeField] private int score = 0;
    [SerializeField] private bool isAlive = true;

    void Start()
    {
        riveWidget = GetComponent<RiveWidget>();
        riveWidget.OnLoad += OnRiveLoad;
    }

    void OnRiveLoad()
    {
        viewModel = riveWidget.GetViewModelInstance("PlayerVM");
        UpdateViewModel();
    }

    void UpdateViewModel()
    {
        if (viewModel == null) return;
        
        viewModel.SetString("username", username);
        viewModel.SetNumber("score", score);
        viewModel.SetBoolean("isAlive", isAlive);
    }

    // Call from game logic
    public void UpdateScore(int newScore)
    {
        score = newScore;
        viewModel?.SetNumber("score", score);
    }

    public void SetPlayerDead()
    {
        isAlive = false;
        viewModel?.SetBoolean("isAlive", false);
        viewModel?.FireTrigger("onDeath");
    }
}
```

## Enum Handling

### Defining Enums

```
StatusEnum: ["idle", "loading", "success", "error"]
```

### Runtime Enum Access

```javascript
// Set by string value
viewModel.setEnum('status', 'loading');

// Get current value
const status = viewModel.getEnum('status'); // "loading"

// Set by index
viewModel.setEnumIndex('status', 2); // "success"
```

### Enum to Animation State

Use Converters to map enum values to state machine states or blend values.

## Nested View Models

### Accessing Nested Data

```javascript
// Flat access (if supported)
viewModel.setString('settings.theme', 'dark');

// Or get nested instance
const settings = viewModel.getViewModelInstance('settings');
settings.setString('theme', 'dark');
```

### Updating Nested Data

```javascript
// Update entire nested object
viewModel.setViewModelInstance('user', {
  name: 'John',
  email: 'john@example.com',
  preferences: {
    darkMode: true
  }
});
```

## List Manipulation

### Setting List Data

```javascript
const menuItems = [
  { label: 'Home', icon: 'home', isSelected: true },
  { label: 'Profile', icon: 'user', isSelected: false },
  { label: 'Settings', icon: 'gear', isSelected: false },
];

viewModel.setList('items', menuItems);
```

### Updating List Items

```javascript
// Update single item
viewModel.setListItem('items', 1, { 
  label: 'Profile', 
  icon: 'user', 
  isSelected: true 
});

// Add item
viewModel.addListItem('items', { 
  label: 'New Item', 
  icon: 'plus' 
});

// Remove item
viewModel.removeListItem('items', 2);
```

## State Machine Integration

### Triggering Transitions

View Model properties can drive state machine transitions:

```
Transition Condition: viewModel.isEnabled == true
→ Transition fires when property changes to true
```

### Blend States

Number properties can drive blend states:

```
Blend State Input: viewModel.progress (0.0 - 1.0)
→ Blends between animations based on property value
```

## Best Practices

### View Model Design

```
✅ Good:
- One View Model per component
- Flat structure when possible
- Meaningful property names

❌ Avoid:
- Deeply nested structures (>3 levels)
- Too many properties (>20 per VM)
- Generic names (data, value, item)
```

### Performance

- Batch property updates when possible
- Avoid updating every frame unless necessary
- Use triggers for one-shot actions

### Type Safety

```typescript
// Define TypeScript interface matching View Model
interface UserCardVM {
  username: string;
  level: number;
  isOnline: boolean;
  statusColor: string;
}

// Type-safe updates
function updateUserCard(vm: RiveViewModel, data: UserCardVM) {
  vm.setString('username', data.username);
  vm.setNumber('level', data.level);
  vm.setBoolean('isOnline', data.isOnline);
  vm.setColor('statusColor', data.statusColor);
}
```

## Migration from Inputs

### Before (State Machine Inputs)

```javascript
const inputs = rive.stateMachineInputs('Main');
const isHovered = inputs.find(i => i.name === 'isHovered');
isHovered.value = true;
```

### After (Data Binding)

```javascript
const viewModel = rive.viewModelInstance('ButtonVM');
viewModel.setBoolean('isHovered', true);
```

### Why Migrate?

| Feature | Inputs | Data Binding |
|---------|--------|--------------|
| Type variety | 3 types | 8+ types |
| Nested data | ❌ | ✅ |
| Lists | ❌ | ✅ |
| Two-way binding | ❌ | ✅ |
| Reusability | Per SM | Across file |

## See Also

- [Rive State Machine](./rive-state-machine.md)
- [Rive Scripting API](./rive-scripting-api.md)
- [Rive React Runtime](./rive-react-runtime.md)

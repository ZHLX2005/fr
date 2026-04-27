# Rive Game Runtimes Reference

> Official docs:
> - Unity: https://rive.app/docs/game-runtimes/unity/
> - Unreal: https://rive.app/docs/game-runtimes/unreal/
> - Defold: https://rive.app/docs/game-runtimes/defold/

## Overview

Rive provides native game engine integrations for Unity, Unreal Engine, and Defold with high-performance rendering and engine-specific APIs.

---

# Unity

## Installation

### Via Unity Package Manager

1. Window → Package Manager
2. Click **+** → Add package from git URL
3. Enter: `https://github.com/rive-app/rive-unity.git`

### Via OpenUPM

```bash
openupm add app.rive.rive-unity
```

### Requirements

- Unity 2021.3 LTS or later
- Render pipelines: Built-in, URP, or HDRP

## Basic Setup

### RiveWidget Component

1. Create UI Canvas (if using UI)
2. Add Empty GameObject
3. Add **RiveWidget** component
4. Assign .riv asset

```csharp
using Rive;
using UnityEngine;

public class SimpleRive : MonoBehaviour
{
    public RiveWidget riveWidget;
    
    void Start()
    {
        riveWidget.Load("animation.riv");
    }
}
```

### RiveTexture (Render to Texture)

For 3D/world-space rendering:

```csharp
using Rive;
using UnityEngine;

public class RiveTexture : MonoBehaviour
{
    public RiveWidget riveWidget;
    public Material targetMaterial;
    
    void Start()
    {
        // RiveWidget renders to RenderTexture
        // Assign to material for 3D display
        targetMaterial.mainTexture = riveWidget.RenderTexture;
    }
}
```

## State Machine Control

### Getting the Controller

```csharp
using Rive;
using UnityEngine;

public class InteractiveRive : MonoBehaviour
{
    public RiveWidget riveWidget;
    private StateMachine stateMachine;
    
    void Start()
    {
        riveWidget.OnLoad += OnRiveLoad;
    }
    
    void OnRiveLoad()
    {
        stateMachine = riveWidget.StateMachine;
    }
}
```

### Input Types

```csharp
// Get inputs
var boolInput = stateMachine.GetBool("isActive");
var numberInput = stateMachine.GetNumber("progress");
var triggerInput = stateMachine.GetTrigger("onClick");

// Set values
boolInput.Value = true;
numberInput.Value = 0.75f;
triggerInput.Fire();
```

### Full Example

```csharp
using Rive;
using UnityEngine;

public class RiveButton : MonoBehaviour
{
    public RiveWidget riveWidget;
    
    private SMIBool isHovered;
    private SMIBool isPressed;
    private SMITrigger onClick;
    
    void Start()
    {
        riveWidget.OnLoad += OnRiveLoad;
    }
    
    void OnRiveLoad()
    {
        var sm = riveWidget.StateMachine;
        isHovered = sm.GetBool("isHovered");
        isPressed = sm.GetBool("isPressed");
        onClick = sm.GetTrigger("onClick");
    }
    
    public void OnPointerEnter()
    {
        isHovered.Value = true;
    }
    
    public void OnPointerExit()
    {
        isHovered.Value = false;
    }
    
    public void OnPointerDown()
    {
        isPressed.Value = true;
    }
    
    public void OnPointerUp()
    {
        isPressed.Value = false;
        onClick.Fire();
    }
}
```

## Rive Events

```csharp
using Rive;
using UnityEngine;

public class RiveEventHandler : MonoBehaviour
{
    public RiveWidget riveWidget;
    
    void Start()
    {
        riveWidget.OnRiveEvent += HandleRiveEvent;
    }
    
    void HandleRiveEvent(RiveEvent riveEvent)
    {
        Debug.Log($"Event: {riveEvent.Name}");
        
        switch (riveEvent.Name)
        {
            case "playSound":
                var soundId = riveEvent.GetString("soundId");
                AudioManager.Play(soundId);
                break;
                
            case "dealDamage":
                var damage = riveEvent.GetNumber("amount");
                GameManager.DealDamage(damage);
                break;
                
            case "spawnParticles":
                var x = riveEvent.GetNumber("x");
                var y = riveEvent.GetNumber("y");
                ParticleManager.Spawn(x, y);
                break;
        }
    }
    
    void OnDestroy()
    {
        riveWidget.OnRiveEvent -= HandleRiveEvent;
    }
}
```

## Data Binding / View Models

```csharp
using Rive;
using UnityEngine;

public class DataBoundRive : MonoBehaviour
{
    public RiveWidget riveWidget;
    private RiveViewModel viewModel;
    
    [SerializeField] private string playerName = "Player";
    [SerializeField] private int score = 0;
    [SerializeField] private float health = 100f;
    
    void Start()
    {
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
        
        viewModel.SetString("name", playerName);
        viewModel.SetNumber("score", score);
        viewModel.SetNumber("health", health);
    }
    
    public void AddScore(int points)
    {
        score += points;
        viewModel?.SetNumber("score", score);
    }
    
    public void TakeDamage(float amount)
    {
        health = Mathf.Max(0, health - amount);
        viewModel?.SetNumber("health", health);
        
        if (health <= 0)
        {
            viewModel?.FireTrigger("onDeath");
        }
    }
}
```

## Text Runs

```csharp
// Update text at runtime
riveWidget.SetTextRunValue("scoreText", $"Score: {score}");
riveWidget.SetTextRunValue("healthText", $"{health:F0}%");
```

## Rendering Modes

### UI Canvas

Best for HUD elements, menus, overlays:

```csharp
// RiveWidget on UI Canvas automatically uses UI rendering
// Ensure Canvas is set up correctly
```

### World Space

For 3D integration:

```csharp
// 1. Create RenderTexture
var renderTexture = new RenderTexture(512, 512, 0);

// 2. Assign to RiveWidget
riveWidget.TargetTexture = renderTexture;

// 3. Apply to 3D material
meshRenderer.material.mainTexture = renderTexture;
```

### Screen Space

Direct screen rendering:

```csharp
// RiveWidget with RiveScreen component
// Renders directly to camera
```

## Procedural Rendering

Access low-level rendering API:

```csharp
using Rive;

public class ProceduralRive : MonoBehaviour
{
    public RiveWidget riveWidget;
    
    void Update()
    {
        var artboard = riveWidget.Artboard;
        
        // Modify artboard properties
        artboard.Width = Screen.width;
        artboard.Height = Screen.height;
        
        // Advance state machine manually
        riveWidget.StateMachine?.Advance(Time.deltaTime);
    }
}
```

## Performance Tips

### Object Pooling

```csharp
// Reuse RiveWidget instances instead of creating/destroying
public class RivePool : MonoBehaviour
{
    private Queue<RiveWidget> pool = new Queue<RiveWidget>();
    
    public RiveWidget Get()
    {
        return pool.Count > 0 ? pool.Dequeue() : CreateNew();
    }
    
    public void Return(RiveWidget widget)
    {
        widget.Stop();
        pool.Enqueue(widget);
    }
}
```

### Batch Updates

```csharp
// Batch property updates
void UpdateUI(PlayerData data)
{
    // Update all at once, not in separate frames
    viewModel.SetString("name", data.Name);
    viewModel.SetNumber("level", data.Level);
    viewModel.SetNumber("health", data.Health);
    viewModel.SetNumber("mana", data.Mana);
}
```

---

# Unreal Engine

## Installation

1. Download plugin from Rive website
2. Extract to `YourProject/Plugins/`
3. Enable in Edit → Plugins → Rive

### Requirements

- Unreal Engine 5.0 or later
- Windows, macOS, Linux

## Basic Usage

### Blueprint

1. Add **RiveWidget** component to Actor
2. Set Rive File asset
3. Configure state machine name

### C++

```cpp
#include "Rive/RiveWidget.h"

void AMyActor::BeginPlay()
{
    Super::BeginPlay();
    
    RiveWidget = CreateDefaultSubobject<URiveWidget>(TEXT("RiveWidget"));
    RiveWidget->SetRiveFile(RiveFileAsset);
    RiveWidget->SetStateMachine(TEXT("Main"));
}
```

## State Machine Inputs

### Blueprint

1. Get State Machine Input node
2. Connect to Set Bool/Number or Fire Trigger

### C++

```cpp
// Boolean
RiveWidget->SetBoolInput(TEXT("isActive"), true);

// Number
RiveWidget->SetNumberInput(TEXT("progress"), 0.75f);

// Trigger
RiveWidget->FireTrigger(TEXT("onClick"));
```

## Events

```cpp
void AMyActor::BeginPlay()
{
    Super::BeginPlay();
    
    RiveWidget->OnRiveEvent.AddDynamic(this, &AMyActor::HandleRiveEvent);
}

void AMyActor::HandleRiveEvent(const FRiveEvent& Event)
{
    UE_LOG(LogTemp, Log, TEXT("Rive Event: %s"), *Event.Name);
    
    if (Event.Name == TEXT("playSound"))
    {
        FString SoundId = Event.GetString(TEXT("soundId"));
        // Play sound
    }
}
```

## Rendering

### UMG Widget

For UI/HUD:

```cpp
// Create UMG widget with Rive
URiveUMGWidget* Widget = CreateWidget<URiveUMGWidget>(this);
Widget->SetRiveFile(RiveFileAsset);
Widget->AddToViewport();
```

### Material

For 3D surfaces:

```cpp
// RiveWidget renders to texture
UTexture* RiveTexture = RiveWidget->GetRenderTexture();
Material->SetTextureParameterValue(TEXT("RiveTexture"), RiveTexture);
```

---

# Defold

## Installation

Add to `game.project`:

```ini
[project]
dependencies = https://github.com/defold/extension-rive/archive/main.zip
```

## Basic Usage

### Add to Game Object

1. Create new game object
2. Add Rive Model component
3. Set .riv file reference

### Lua Script

```lua
function init(self)
    -- Play state machine
    rive.play_state_machine("#rivemodel", "Main")
end

function update(self, dt)
    -- State machine advances automatically
end
```

## State Machine Inputs

```lua
-- Boolean
rive.set_bool("#rivemodel", "Main", "isActive", true)

-- Number  
rive.set_number("#rivemodel", "Main", "progress", 0.75)

-- Trigger
rive.fire("#rivemodel", "Main", "onClick")
```

## Events

```lua
function init(self)
    rive.play_state_machine("#rivemodel", "Main")
end

function on_message(self, message_id, message, sender)
    if message_id == hash("rive_event") then
        print("Rive event:", message.name)
        
        if message.name == "playSound" then
            local sound_id = message.properties.soundId
            -- Play sound
        end
    end
end
```

## Animation Control

```lua
-- Play specific animation
rive.play_animation("#rivemodel", "Idle", rive.PLAYBACK_LOOP)

-- Stop animation
rive.stop_animation("#rivemodel", "Idle")

-- Cancel all
rive.cancel("#rivemodel")
```

## Text Runs

```lua
rive.set_text_run("#rivemodel", "scoreText", "Score: 100")
```

---

## Common Patterns (All Platforms)

### Health Bar

```
// View Model: HealthBarVM { health: Number (0-100) }

// Update when health changes
viewModel.SetNumber("health", currentHealth / maxHealth * 100);
```

### Character Expression

```
// View Model: CharacterVM { expression: Enum ["happy", "sad", "angry"] }

// Change expression
viewModel.SetEnum("expression", "happy");
```

### Interactive Button

```
// Inputs: isHovered (Bool), isPressed (Bool), onClick (Trigger)

OnPointerEnter → isHovered = true
OnPointerExit → isHovered = false
OnPointerDown → isPressed = true
OnPointerUp → isPressed = false, onClick.Fire()
```

### Loading Progress

```
// Input: progress (Number, 0-1)
// Animate loading bar fill based on progress value

viewModel.SetNumber("progress", loadedBytes / totalBytes);
```

## See Also

- [Rive State Machine](./rive-state-machine.md)
- [Rive Events](./rive-events.md)
- [Rive Data Binding](./rive-data-binding.md)

# Rive Constraints Reference

Complete reference for all constraint types in the Rive Editor.

## Table of Contents

1. [Constraints Overview](#constraints-overview)
2. [IK Constraint](#ik-constraint)
3. [Distance Constraint](#distance-constraint)
4. [Scale Constraint](#scale-constraint)
5. [Rotation Constraint](#rotation-constraint)
6. [Transform Constraint](#transform-constraint)
7. [Translation Constraint](#translation-constraint)
8. [Follow Path Constraint](#follow-path-constraint)
9. [Scroll Constraint](#scroll-constraint)

---

## Constraints Overview

Constraints are rules that control object properties based on other objects. They enable complex behaviors without manual keyframing.

### Common Use Cases

- Eyes following a target
- Character limbs bending naturally (IK)
- Wheels rotating together
- Objects maintaining distance
- Motion along paths

### Adding Constraints

1. Select the object to constrain
2. In Inspector, scroll to Constraints section
3. Click `+` to add a constraint
4. Select constraint type
5. Configure target and properties

### Constraint Properties (Common)

| Property | Description |
|----------|-------------|
| **Target** | Object to constrain to |
| **Strength** | 0-100%, how much constraint affects object |
| **Enabled** | Toggle constraint on/off |

---

## IK Constraint

Inverse Kinematics (IK) automatically calculates bone rotations to reach a target.

### Use Cases

- Character arms reaching for objects
- Legs bending at knees
- Tentacles/tails following targets
- Mechanical arms and pistons

### Setup

1. Create a bone chain (parent → child → grandchild, etc.)
2. Select the END bone of the chain
3. Add IK Constraint
4. Set Target (the object to reach toward)
5. Set Bone Count (number of bones in chain)

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Object the chain reaches toward |
| **Bone Count** | Number of bones affected (from selected bone up) |
| **Invert Direction** | Flip the bend direction |
| **Strength** | Blend between FK and IK |

### Example: Character Arm

```
Hierarchy:
  Shoulder (Bone)
    └── Upper Arm (Bone)
          └── Forearm (Bone)
                └── Hand (Bone) ← Add IK here

IK Settings:
  Target: Hand_Target (Group/Shape)
  Bone Count: 2 (Forearm + Upper Arm)
  Invert: false (elbow bends naturally)
```

### Tips

- Create a separate target object to animate
- Use Bone Count = 2 for typical limbs
- Adjust Invert Direction if joint bends wrong way
- Animate target position, not individual bones

---

## Distance Constraint

Keeps an object within a specified distance from a target.

### Use Cases

- Rubber band effect
- Keeping objects together
- Pushing objects apart
- Elastic connections

### Modes

| Mode | Behavior |
|------|----------|
| **Closer** | Push away if too close (minimum distance) |
| **Further** | Pull closer if too far (maximum distance) |
| **Exact** | Maintain exact distance |

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Object to measure distance from |
| **Distance** | Target distance in pixels |
| **Mode** | Closer, Further, or Exact |
| **Strength** | How strongly to enforce |

### Example: Orbiting Object

```
Settings:
  Target: Center_Point
  Distance: 100
  Mode: Exact
  Strength: 100%
  
Result: Object stays exactly 100px from center
```

---

## Scale Constraint

Copies scale from a target object.

### Use Cases

- Synchronized scaling between objects
- Scale inheritance without parenting
- Scale-based effects

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Object to copy scale from |
| **Copy X** | Copy horizontal scale |
| **Copy Y** | Copy vertical scale |
| **Offset** | Scale offset (multiplier) |
| **Strength** | Blend amount |
| **Source Space** | Local or World space of target |
| **Dest Space** | Local or World space of constrained object |

### Example: Mirrored Scale

```
Settings:
  Target: Main_Object
  Copy X: true
  Copy Y: true
  Offset: 1.0
  Strength: 100%
  
Result: Object scales identically to target
```

---

## Rotation Constraint

Copies rotation from a target object.

### Use Cases

- Gears rotating together
- Eyes following a target
- Synchronized spinning objects
- Dial indicators

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Object to copy rotation from |
| **Copy** | Enable rotation copying |
| **Offset** | Rotation offset in degrees |
| **Strength** | Blend amount (0-100%) |
| **Source Space** | Local or World space of target |
| **Dest Space** | Local or World space of constrained object |

### Example: Gear System

```
Large Gear:
  Rotation: (animated manually)

Small Gear:
  Rotation Constraint:
    Target: Large_Gear
    Offset: 0
    Strength: 100%
    
Result: Small gear rotates with large gear
```

### Example: Counter-Rotating Gears

Use negative offset or source/dest space manipulation for opposite rotation:

```
Gear B:
  Rotation Constraint:
    Target: Gear_A
    Offset: 180° (or flip via spaces)
```

---

## Transform Constraint

Copies full transform (position, rotation, scale) from a target.

### Use Cases

- Complete object mirroring
- Transform inheritance without hierarchy
- Complex transform relationships

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Object to copy transform from |
| **Source Space** | Local or World |
| **Dest Space** | Local or World |
| **Strength** | Blend amount |

### Space Combinations

| Source | Dest | Result |
|--------|------|--------|
| World | World | Exact position match in world |
| Local | Local | Match relative to respective parents |
| World | Local | World position affects local transform |
| Local | World | Local changes affect world position |

---

## Translation Constraint

Copies position from a target object.

### Use Cases

- Objects following movement
- Offset following
- Position-based triggers

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Object to copy position from |
| **Copy X** | Copy horizontal position |
| **Copy Y** | Copy vertical position |
| **Offset X** | Horizontal offset |
| **Offset Y** | Vertical offset |
| **Strength** | Blend amount |
| **Source Space** | Local or World space of target |
| **Dest Space** | Local or World space of constrained object |

### Example: Shadow Following

```
Shadow:
  Translation Constraint:
    Target: Character
    Copy X: true
    Copy Y: true
    Offset X: 10
    Offset Y: 10
    Strength: 100%
    
Result: Shadow follows character with offset
```

---

## Follow Path Constraint

Attaches an object to a path, following its contour.

### Use Cases

- Motion along curves
- Conveyor belts
- Roller coasters
- Text on path effects

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Path to follow |
| **Distance** | Position along path (0-100% or pixels) |
| **Distance Units** | Percent or Pixels |
| **Orient** | Rotate to follow path tangent |
| **Offset** | Rotation offset when oriented |

### Distance Animation

Animate the Distance property to move object along path:

```
Timeline:
  Frame 0: Distance = 0%
  Frame 60: Distance = 100%
  
Result: Object travels entire path over 60 frames
```

### Orient Options

| Orient | Behavior |
|--------|----------|
| **None** | Object maintains original rotation |
| **Auto** | Object rotates to follow path direction |
| **Auto + Offset** | Follow path with additional rotation offset |

### Example: Car on Road

```
Car:
  Follow Path Constraint:
    Target: Road_Path
    Distance: (animated 0-100%)
    Orient: Auto
    Offset: -90° (if car graphic faces wrong way)
```

---

## Scroll Constraint

Binds object position to scroll position within a layout scroll container.

### Use Cases

- Parallax scrolling effects
- Scroll-triggered animations
- Sticky elements
- Scroll indicators

### Properties

| Property | Description |
|----------|-------------|
| **Target** | Scroll container layout |
| **Source X/Y** | Which scroll axis to use |
| **Dest X/Y** | Which position axis to affect |
| **Multiplier** | Scale factor for scroll amount |
| **Offset** | Starting offset |

### Example: Parallax Background

```
Background Layer:
  Scroll Constraint:
    Target: Main_Scroll_Container
    Source Y: Scroll Y position
    Dest Y: Position Y
    Multiplier: 0.5 (moves at half scroll speed)
```

### Multiplier Values

| Multiplier | Effect |
|------------|--------|
| 1.0 | Moves at same speed as scroll |
| 0.5 | Moves at half speed (parallax back) |
| 2.0 | Moves at double speed |
| -1.0 | Moves opposite direction |
| 0 | Stationary (sticky) |

---

## Constraint Stacking

Objects can have multiple constraints that work together:

### Order Matters

Constraints are evaluated in order from top to bottom:
1. First constraint applies
2. Second constraint modifies result
3. And so on...

### Example: Eye Following with Limits

```
Eye:
  1. Rotation Constraint (Target: Look_Target, Strength: 100%)
  2. Distance Constraint (Mode: Closer, Distance: 30px)
  
Result: Eye rotates toward target but doesn't move too far
```

### Blending Constraints

Use Strength < 100% to blend between constraints:

```
Object:
  1. Translation Constraint (Target: A, Strength: 50%)
  2. Translation Constraint (Target: B, Strength: 50%)
  
Result: Object positioned between A and B
```

---

## Animating Constraints

### Animatable Properties

Most constraint properties can be keyframed:
- Strength (smooth enable/disable)
- Distance
- Offset values
- Target (via Data Binding)

### Common Patterns

**Gradual Enable:**
```
Frame 0: Strength = 0%
Frame 30: Strength = 100%
```

**IK to FK Blend:**
```
Reach Phase: IK Strength = 100%
Grab Phase: IK Strength = 0% (switch to FK animation)
```

---

## Best Practices

1. **Name targets clearly** - Use descriptive names like "Hand_IK_Target"
2. **Group targets** - Keep constraint targets organized
3. **Test at runtime** - Some constraints behave differently in game engines
4. **Use minimal constraints** - Each constraint has performance cost
5. **Document complex setups** - Use artboard comments for team reference

---

## Additional Resources

- Official Docs: https://rive.app/docs/editor/constraints/constraints-overview
- IK Deep Dive: https://rive.app/docs/editor/constraints/ik-constraint
- Community Examples: https://community.rive.app

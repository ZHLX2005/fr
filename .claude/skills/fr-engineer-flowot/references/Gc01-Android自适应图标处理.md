---
name: Gc01-Android自适应图标处理
description: Android自适应图标前景图处理工作流。当用户提到图标处理、应用图标、自适应图标、安卓图标、app icon、adaptive icon、foreground icon时使用此技能。完成从原始图片到Android自适应图标前景图的完整处理流程，包括：边缘色块分析、洪泛法去色、岛屿算法提取中心内容、HLS饱和度过滤、图标居中缩放、以及Android adaptive icon XML配置。
---

# Android Adaptive Icon Foreground Processing Skill

## Overview

This skill handles the complete workflow of converting a raw image into an Android adaptive icon foreground. It addresses common issues like removing background colors, eliminating edge artifacts (dark/light borders), extracting the main content region, centering and scaling, and configuring the Android adaptive icon XML.

## Processing Pipeline

```
原始图片 → 边缘色块分析(flood_fill_cli) → 用户选择去色
     ↓
HSL饱和度过滤 → 岛屿算法提取中心内容 → 去边距
     ↓
正方形裁剪 → 居中缩放（1024 画布 × 40% ≈ 409px，与 generate_android_icon.py 的 int(1024*0.4) 一致） → 输出PNG
     ↓
Android XML配置 → 移除inset属性
```

## Step 1: Analyze and Remove Edge Colors

Use the bundled `flood_fill_cli.py` tool to interactively analyze and remove edge color blocks.

```bash
python .claude/skills/fr-engineer-flowot/scripts/flood_fill_cli.py input.png output.png
```

**What it does:**
1. Scans all color regions connected to image edges using BFS flood fill
2. Displays numbered list with human-readable color descriptions (红色系、白色、黑色等)
3. User selects which colors to convert to transparent
4. Applies the mask and saves the result

**Typical edge colors to remove:**
- White background (RGB around 255,255,255)
- Black/dark edges (anti-aliasing artifacts)
- Light gray edges (JPEG compression artifacts)

## Step 2: Extract Main Content (Island Algorithm)

After removing background, if edge artifacts remain, use HSL saturation + connected components to extract the colorful content:

```python
import numpy as np
from PIL import Image

def rgb_to_hsl(r, g, b):
    r, g, b = r/255, g/255, b/255
    max_c, min_c = max(r,g,b), min(r,g,b)
    l = (max_c + min_c) / 2
    if max_c == min_c:
        return 0, 0, l
    d = max_c - min_c
    s = d / (2 - max_c - min_c) if l > 0.5 else d / (max_c + min_c)
    h = (r - g) / d + (6 if g < b else 0)
    h /= 6
    return h, s, l

def keep_colorful_content(input_path, output_path, saturation_threshold=0.25):
    """Keep only colorful pixels (saturation >= threshold), remove grays."""
    img = Image.open(input_path).convert("RGBA")
    pixels = np.array(img)
    h, w = pixels.shape[:2]

    mask = np.zeros((h, w), dtype=bool)
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[y, x]
            if a > 0:
                _, s, _ = rgb_to_hsl(r, g, b)
                if s >= saturation_threshold:
                    mask[y, x] = True

    # Connected component - find largest central region
    visited = np.zeros((h, w), dtype=bool)
    def bfs(sy, sx):
        q = [(sy, sx)]
        visited[sy, sx] = True
        pts = [(sy, sx)]
        while q:
            y, x = q.pop(0)
            for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny, nx = y+dy, x+dx
                if 0<=ny<h and 0<=nx<w and not visited[ny,nx] and mask[ny,nx]:
                    visited[ny,nx] = True
                    q.append((ny, nx))
                    pts.append((ny, nx))
        return pts

    regions = []
    for y in range(h):
        for x in range(w):
            if mask[y,x] and not visited[y,x]:
                regions.append(bfs(y, x))

    if not regions:
        return

    # Keep largest region, prefer central regions
    def center_score(pts):
        cy = sum(p[0] for p in pts) / len(pts)
        cx = sum(p[1] for p in pts) / len(pts)
        return -abs(cy - h/2) - abs(cx - w/2)

    regions.sort(key=center_score, reverse=True)
    largest = regions[0]

    # Create output
    result = np.zeros((h, w, 4), dtype=np.uint8)
    for y, x in largest:
        result[y, x] = pixels[y, x]

    Image.fromarray(result, "RGBA").save(output_path)
```

## Step 3: Center and Scale Content

After content extraction, center the content in a square canvas and scale it appropriately:

```python
def center_and_scale_content(input_path, output_path, target_size=1024, scale=0.4):
    """Center content and scale to fit in target canvas."""
    img = Image.open(input_path).convert("RGBA")
    pixels = np.array(img)
    h, w = pixels.shape[:2]

    # Find content bounds
    mask = pixels[:,:,3] > 0
    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    y_min, y_max = np.where(rows)[0][[0, -1]]
    x_min, x_max = np.where(cols)[0][[0, -1]]

    content_h = y_max - y_min + 1
    content_w = x_max - x_min + 1

    # Crop to content
    content = img.crop((x_min, y_min, x_max+1, y_max+1))

    # Scale to fit at target scale
    scaled_size = int(target_size * scale)
    scale_factor = scaled_size / max(content_h, content_w)
    new_h = int(content_h * scale_factor)
    new_w = int(content_w * scale_factor)
    content = content.resize((new_w, new_h), Image.LANCZOS)

    # Create output canvas
    result = Image.new("RGBA", (target_size, target_size), (0,0,0,0))
    paste_x = (target_size - new_w) // 2
    paste_y = (target_size - new_h) // 2
    result.paste(content, (paste_x, paste_y))

    result.save(output_path)
```

## Step 4: Configure Android Adaptive Icon

### 4a. Update flutter_launcher_icons in pubspec.yaml

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  remove_alpha_ios: false
  image_path: "res/your_icon.png"
  adaptive_icon_background: "#FFFFFF"  # or "#00000000" for transparent
  adaptive_icon_foreground: "res/your_icon.png"
```

Run the plugin:
```bash
flutter pub run flutter_launcher_icons
```

### 4b. Remove inset from Android XML

After running flutter_launcher_icons, the plugin regenerates `ic_launcher.xml` with `inset="16%"` which causes the icon to align to edges. **You must remove this inset**.

Edit: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
```

**Remove the `inset="16%"` attribute from the foreground drawable.** The inset shrinks the foreground and offsets the composition, making the artwork look off-center.

### 4c. Set background color (for transparent icons)

Edit: `android/app/src/main/res/values/colors.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
```

For fully transparent icons, use white background (the icon foreground itself should have transparency).

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Icon fills entire screen | `inset="16%"` in XML | Remove inset attribute |
| White edges remain | White background not removed | Run flood_fill_cli, select white |
| Dark edges remain | Anti-aliasing artifacts | Use island algorithm with saturation filter |
| Gray edges remain | JPEG compression artifacts | Use saturation threshold (s>=0.25) |
| Content too large | No scaling applied | Scale to 40% of canvas |
| All pixels connected | Background + content merged | Use HSL saturation first, then island algorithm |

## Key Parameters

- **HSL saturation threshold**: 0.25 (keeps colorful content, removes gray)
- **Icon scale**: 0.4 (40% of 1024px canvas = 约 409px)
- **Edge width for flood fill**: 3 pixels
- **Target canvas size**: 1024x1024

## Bundled Scripts

- `.claude/skills/fr-engineer-flowot/scripts/flood_fill_cli.py` - Interactive edge color removal tool
- `.claude/skills/fr-engineer-flowot/scripts/generate_android_icon.py` - Icon scaling and XML fixer

`generate_android_icon.py` 用法（**必须从项目根执行**）：

```bash
python .claude/skills/fr-engineer-flowot/scripts/generate_android_icon.py <源图.png> <输出图标.png> [scale=0.4]
```

脚本里 `fix_adaptive_icon_xml` 写入的 `ic_launcher.xml` 路径硬编码为相对路径 `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`，只有在项目根执行该路径才存在；非项目根执行 `fix_adaptive_icon_xml` 会因 `os.path.exists(xml_path)` 为 false 而**静默跳过 XML 修改**，仅生成缩放后的 PNG，故务必从项目根调用。

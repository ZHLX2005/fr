# -*- coding: utf-8 -*-
"""
生成安卓自适应图标
用法:
    python generate_android_icon.py <源图.png> <输出图标.png> [scale=0.4]
"""
import sys
from PIL import Image
import numpy as np
import re
import os

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

def process_icon(input_path, output_path, target_size=1024, scale=0.4):
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
    content = img.crop((x_min, y_min, x_max+1, y_max+1))

    scaled_size = int(target_size * scale)
    scale_factor = scaled_size / max(content_h, content_w)
    new_h = int(content_h * scale_factor)
    new_w = int(content_w * scale_factor)
    content = content.resize((new_w, new_h), Image.LANCZOS)

    result = Image.new("RGBA", (target_size, target_size), (0,0,0,0))
    paste_x = (target_size - new_w) // 2
    paste_y = (target_size - new_h) // 2
    result.paste(content, (paste_x, paste_y))
    result.save(output_path)
    print(f"Content: {content_w}x{content_h}, Scaled: {new_w}x{new_h}, Scale: {scale}")
    return output_path

def fix_adaptive_icon_xml(xml_path):
    """移除 adaptive-icon XML 中的 inset 属性"""
    if not os.path.exists(xml_path):
        print(f"XML不存在: {xml_path}")
        return

    with open(xml_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 移除 inset="16%" 属性
    fixed = re.sub(r'\s+android:inset="[^"]*"', '', content)

    if fixed != content:
        with open(xml_path, 'w', encoding='utf-8') as f:
            f.write(fixed)
        print(f"已修复: {xml_path}")
    else:
        print(f"无需修复: {xml_path}")

def main():
    if len(sys.argv) < 3:
        print("用法: python generate_android_icon.py <源图> <输出图标> [scale]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    scale = float(sys.argv[3]) if len(sys.argv) > 3 else 0.4

    # 1. 处理图标
    process_icon(input_path, output_path, scale=scale)

    # 2. 修复 Android XML (如果存在)
    xml_path = "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
    fix_adaptive_icon_xml(xml_path)

    print("完成!")

if __name__ == "__main__":
    main()

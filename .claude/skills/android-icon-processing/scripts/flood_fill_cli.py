# -*- coding: utf-8 -*-
"""
洪泛法边缘去色 CLI 工具
用法:
    python flood_fill_cli.py input.png output.png
"""
from PIL import Image
import numpy as np
from collections import deque
import sys


def find_edge_regions(pixels, h, w, edge_width=3):
    """
    找到所有从边缘出发连通的色块区域
    返回: dict { (r,g,b,a): [(y,x), ...], ... }
    """
    is_edge = lambda y,x: y < edge_width or y >= h-edge_width or x < edge_width or x >= w-edge_width

    visited = np.zeros((h,w),dtype=bool)
    regions = {}  # color -> list of positions

    def bfs(sy,sx):
        q=deque([(sy,sx)]); visited[sy,sx]=True; pts=[]
        while q:
            y,x=q.popleft(); pts.append((y,x))
            for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                ny,nx=y+dy,x+dx
                if 0<=ny<h and 0<=nx<w and not visited[ny,nx] and is_edge(ny,nx):
                    if pixels[ny,nx,3] > 0:
                        visited[ny,nx]=True; q.append((ny,nx))
        return pts

    for y in range(h):
        for x in range(w):
            if is_edge(y,x) and not visited[y,x] and pixels[y,x,3] > 0:
                pts = bfs(y,x)
                color = tuple(pixels[y,x])
                if color not in regions:
                    regions[color] = []
                regions[color].extend(pts)

    return regions


def color_description(r,g,b,a):
    """给颜色一个文字描述"""
    max_c = max(r,g,b)
    min_c = min(r,g,b)
    l = (max_c+min_c)/2

    if a < 10:
        return "透明"
    if l > 0.9:
        return "白色"
    if l < 0.1:
        return "黑色"
    if r > g and r > b:
        return f"红色系(R={r})"
    if g > r and g > b:
        return f"绿色系(G={g})"
    if b > r and b > g:
        return f"蓝色系(B={b})"
    return f"灰色(R={r},G={g},B={b})"


def main():
    if len(sys.argv) < 3:
        print("用法: python flood_fill_cli.py <输入图片> <输出图片>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    img = Image.open(input_path).convert("RGBA")
    pixels = np.array(img)
    h, w = pixels.shape[:2]
    print(f"\n图片尺寸: {w}x{h}\n")

    print("正在分析边缘色块...")
    regions = find_edge_regions(pixels, h, w)

    if not regions:
        print("未找到边缘色块")
        img.save(output_path)
        sys.exit(0)

    print(f"找到 {len(regions)} 个边缘色块:\n")
    print("-" * 60)

    colors = list(regions.keys())
    for i, color in enumerate(colors):
        r,g,b,a = color
        desc = color_description(r,g,b,a)
        pixel_count = len(regions[color])
        print(f"  [{i}] {desc}")
        print(f"       颜色: RGB({r},{g},{b}) A={a}  像素: {pixel_count}")
        print()

    print("-" * 60)
    print("输入要清除的颜色编号，多个用逗号分隔（如 0,2,3）")
    print("输入 'a' 清除所有")
    print("输入 'q' 退出不保存")
    print()

    choice = input("你的选择: ").strip()

    if choice.lower() == 'q':
        print("取消")
        sys.exit(0)

    to_remove = set()
    if choice.lower() == 'a':
        to_remove = set(range(len(colors)))
    else:
        for part in choice.split(','):
            part = part.strip()
            if part.isdigit():
                idx = int(part)
                if 0 <= idx < len(colors):
                    to_remove.add(idx)

    if not to_remove:
        print("没有选择任何颜色，保存原图")
        img.save(output_path)
        sys.exit(0)

    print(f"\n将清除 {len(to_remove)} 个色块")

    # 构建要移除的遮罩
    mask = np.zeros((h,w),dtype=bool)
    for idx in to_remove:
        color = colors[idx]
        for y,x in regions[color]:
            mask[y,x] = True

    # 应用遮罩
    removed = 0
    for y in range(h):
        for x in range(w):
            if mask[y,x]:
                pixels[y,x] = [0,0,0,0]
                removed += 1

    print(f"移除 {removed} 像素")

    result = Image.fromarray(pixels, "RGBA")
    result.save(output_path)
    print(f"已保存: {output_path}")


if __name__ == "__main__":
    main()

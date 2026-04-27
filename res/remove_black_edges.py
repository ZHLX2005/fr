# -*- coding: utf-8 -*-
"""
使用洪涌法（Flood Fill）移除图片黑色边缘并转为透明
"""
from PIL import Image
import numpy as np


def flood_fill_transparent(img: Image.Image, tolerance: int = 30) -> Image.Image:
    """
    洪涌法：将边缘连接的黑色像素转为透明

    Args:
        img: 输入图片
        tolerance: 黑色判定容差 (0-255)
    """
    # 转换为RGBA模式
    img = img.convert("RGBA")
    pixels = np.array(img)
    height, width = pixels.shape[:2]

    # 创建遮罩画布
    mask = np.zeros((height, width), dtype=bool)

    # 判定是否为黑色像素
    def is_black(pixel, tol=tolerance):
        r, g, b, a = pixel
        return r <= tol and g <= tol and b <= tol

    # 四个边缘的所有黑色像素入队
    from collections import deque
    queue = deque()

    # 检查四边
    for y in range(height):
        for x in [0, width - 1]:
            if is_black(pixels[y, x]) and not mask[y, x]:
                mask[y, x] = True
                queue.append((y, x))
    for x in range(width):
        for y in [0, height - 1]:
            if is_black(pixels[y, x]) and not mask[y, x]:
                mask[y, x] = True
                queue.append((y, x))

    # 4邻域扩散
    directions = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    while queue:
        y, x = queue.popleft()
        for dy, dx in directions:
            ny, nx = y + dy, x + dx
            if 0 <= ny < height and 0 <= nx < width:
                if not mask[ny, nx] and is_black(pixels[ny, nx]):
                    mask[ny, nx] = True
                    queue.append((ny, nx))

    # 将标记的黑色像素设为透明
    for y in range(height):
        for x in range(width):
            if mask[y, x]:
                pixels[y, x] = [0, 0, 0, 0]

    return Image.fromarray(pixels, "RGBA")


if __name__ == "__main__":
    import sys

    input_path = sys.argv[1] if len(sys.argv) > 1 else "image.png"
    output_path = sys.argv[2] if len(sys.argv) > 2 else "image_transparent.png"

    print(f"读取图片: {input_path}")
    img = Image.open(input_path)
    print(f"图片尺寸: {img.size}")

    result = flood_fill_transparent(img, tolerance=30)

    result.save(output_path)
    print(f"已保存透明图片: {output_path}")

# 乐谱生成脚本

## 安装

```bash
pip install -r requirements.txt
```

需要安装 ffmpeg 并添加到 PATH。

## 使用方法

```bash
# 基本用法
python generate_chart.py audio.m4a

# 指定输出和元数据
python generate_chart.py audio.m4a -o song.json --name "My Song" --artist "Artist Name" --intro "这是一首..."
```

## 输出

生成 `assets/charts/[song_name].json` 文件，包含完整的乐谱数据。

## 注意事项

- 此脚本仅供本地使用，不加入 git 提交
- 生成的乐谱需要人工校准节奏和判定
- Hold 音符duration可能需要根据实际音乐调整

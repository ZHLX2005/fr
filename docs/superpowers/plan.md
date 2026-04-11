## 调用示例

基础与流式

* cURL
* Python
* Java
* Python(旧)

**基础调用**

```
curl -X POST \
  https://open.bigmodel.cn/api/paas/v4/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5v-turbo",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image_url",
            "image_url": {
              "url": "https://cloudcovert-1305175928.cos.ap-guangzhou.myqcloud.com/%E5%9B%BE%E7%89%87grounding.PNG"
            }
          },
          {
            "type": "text",
            "text": "Where is the second bottle of beer from the right on the table?  Provide coordinates in [[xmin,ymin,xmax,ymax]] format"
          }
        ]
      }
    ],
    "thinking": {
      "type":"enabled"
    }
  }'
```

**流式调用**

```
curl -X POST \
  https://open.bigmodel.cn/api/paas/v4/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5v-turbo",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image_url",
            "image_url": {
              "url": "https://cloudcovert-1305175928.cos.ap-guangzhou.myqcloud.com/%E5%9B%BE%E7%89%87grounding.PNG"
            }
          },
          {
            "type": "text",
            "text": "Where is the second bottle of beer from the right on the table?  Provide coordinates in [[xmin,ymin,xmax,ymax]] format"
          }
        ]
      }
    ],
    "thinking": {
      "type":"enabled"
    },
    "stream": true
  }'
```

多模态理解

> 不支持同时理解文件、视频和图像。

* cURL
* Python
* Java

**图片理解**

```
curl -X POST \
  https://open.bigmodel.cn/api/paas/v4/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5v-turbo",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image_url",
            "image_url": {
              "url": "https://cdn.bigmodel.cn/static/logo/register.png"
            }
          },
          {
            "type": "image_url",
            "image_url": {
              "url": "https://cdn.bigmodel.cn/static/logo/api-key.png"
            }
          },
          {
            "type": "text",
            "text": "What are the pics talk about?"
          }
        ]
      }
    ],
    "thinking": {
      "type": "enabled"
    }
  }'
```

**视频理解**

```
curl -X POST \
  https://open.bigmodel.cn/api/paas/v4/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5v-turbo",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "video_url",
            "video_url": {
              "url": "https://cdn.bigmodel.cn/agent-demos/lark/113123.mov"
            }
          },
          {
            "type": "text",
            "text": "What are the video show about?"
          }
        ]
      }
    ],
    "thinking": {
      "type": "enabled"
    }
  }'
```

**文件理解**

```
curl -X POST \
  https://open.bigmodel.cn/api/paas/v4/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5v-turbo",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "file_url",
            "file_url": {
              "url": "https://cdn.bigmodel.cn/static/demo/demo2.txt"
            }
          },
          {
            "type": "file_url",
            "file_url": {
              "url": "https://cdn.bigmodel.cn/static/demo/demo1.pdf"
            }
          },
          {
            "type": "text",
            "text": "What are the files show about?"
          }
        ]
      }
    ],
    "thinking": {
      "type": "enabled"
    }
  }'
```




### 视觉模型

视觉模型是一类能处理图像或视频等视觉信息的模型，广泛应用于识别、分析与决策任务。其中，视觉理解模型侧重于看懂图像内容，如识别物体、场景和关系；而视觉推理模型进一步具备看图思考的能力，能结合视觉与语言信息完成逻辑判断、因果分析和多步推理，常用于图文问答、图像描述生成、多模态对齐等复杂任务。| 模型                                                                                          | 定位               | 特点                                                                                   | 上下文                                               | 最大输出 |
| ----------------------------------------------------------------------------------------------- | -------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------ | ---------- |
| [GLM-5V-Turbo](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5v-turbo)                        | 多模态 Coding 基座 | - 兼顾视觉理解与 Coding 能力 `<br/>`- 复杂视觉推理更准确 `<br/>`- 超长上下文 `<br/>`- 深度适配 Agent 工作流 | 200K                                                 | 128K     |
| [GLM-4.6V](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-4.6v)                                | 视觉推理           | - 视觉推理能力 `<br/>`- 原生支持工具调用 `<br/>`- 长上下文 `<br/>`- 前端代码复刻效果提升                    | 128K                                                 | 32K      |
| [GLM-OCR](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-ocr)                                  | 轻量图文解析       | - 性能SOTA `<br/>`- 高精度、高效率 `<br/>`- 支持多种常见复杂文档解析                                 | 输入:`<br/>`- 单图 ≤ 10 MB，PDF ≤ 50 MB `<br/>`- 最大支持100页 `<br/>` | /        |
| [AutoGLM-Phone](https://docs.bigmodel.cn/cn/guide/models/vlm/autoglm-phone)                      | 手机智能助理框架   | - 支持用自然语言自动完成 App 操作任务 `<br/>`- 支持完整操作指令集                             | 20K                                                  | 2048     |
| [GLM-4.1V-Thinking-FlashX](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-4.1v-thinking)       | 轻量视觉推理       | - 视觉推理能力 `<br/>`- 复杂场景理解 `<br/>`- 多步骤分析 `<br/>`- 高并发                                    | 64K                                                  | 16K      |
| [GLM-4.6V-Flash](https://docs.bigmodel.cn/cn/guide/models/free/glm-4.6v-flash)                   | 免费模型           | - 视觉推理能力 `<br/>`- 支持工具调用 `<br/>`- 可灵活开关思考模式                                     | 128K                                                 | 32K      |
| [GLM-4.1V-Thinking-Flash](https://docs.bigmodel.cn/cn/guide/models/free/glm-4.1v-thinking-flash) | 免费模型           | - 视觉推理能力 `<br/>`- 复杂场景理解 `<br/>`- 多步骤分析                                             | 64K                                                  | 16K      |
| [GLM-4V-Flash](https://docs.bigmodel.cn/cn/guide/models/free/glm-4v-flash)                       | 免费模型           | - 图像理解 `<br/>`- 多语言支持                                                                | 16K                                                  | 1K       |

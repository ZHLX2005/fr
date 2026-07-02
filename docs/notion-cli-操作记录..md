# Notion CLI 操作记录

## 目标
在 `me` 数据库中通过原生模板创建页面，并上传图片。

## 操作步骤

### 1. 查看数据库
```bash
notion db list
notion db view <database-id>
```

### 2. 通过数据库模板创建页面
```bash
notion db add <database-id> "名称=2026-06-30T22:50:00.000+08:00"
```
输出：
```
✓ Row added
ID:             38f550be-064e-8196-947e-d17cb3b7f48f
URL:            https://app.notion.com/p/2026-06-30T22-50-00-000-08-00-38f550be064e8196947ed17cb3b7f48f
```

### 3. 上传图片文件
```bash
notion file upload <image-path>
```
示例：
```bash
notion file upload "D:/Temp/PixPin_2026-06-30_22-47-15.png"
```
输出：
```
✓ Uploaded: PixPin_2026-06-30_22-47-15.png
ID:             38f550be-064e-81cf-8cd3-00b20cbac905
Size:           5579 bytes
```

### 4. 将图片添加到页面（使用 Notion API）
由于 `notion block append` 命令不支持直接添加图片，需要通过 API 调用：

```bash
# Windows PowerShell
$headers = @{
    'Authorization' = 'Bearer <your-token>'
    'Content-Type' = 'application/json'
    'Notion-Version' = '2022-06-28'
}
$body = @{
    children = @(@{
        object = 'block'
        type = 'image'
        image = @{
            type = 'file_upload'
            file_upload = @{
                id = '<file-upload-id>'
            }
        }
    })
} | ConvertTo-Json -Depth 10
Invoke-RestMethod -Uri 'https://api.notion.com/v1/blocks/<page-id>/children' -Method PATCH -Headers $headers -Body $body
```

### 5. 验证结果
```bash
notion page view <page-id>
```

## 关键点

1. **`notion db add`** 是通过数据库原生模板创建条目的正确方式
2. **图片上传**需要两个步骤：
   - 先用 `notion file upload` 上传文件获取 file_upload ID
   - 再通过 API 将 file_upload ID 附加到页面
3. **图片格式**：使用 `type: "file_upload"` 和 `file_upload.id`

## 数据库信息
- **数据库名称**: me
- **数据库 ID**: `38b550be-064e-801c-b944-f437c9a65f8a`
- **属性**: 名称 (title), 创建时间 (created_time)

## 文件路径
- **Token 配置**: `~/.config/notion-cli/config.json`

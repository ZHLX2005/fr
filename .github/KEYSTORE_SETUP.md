# 生成 Android 签名密钥并添加到 GitHub Secrets

## 步骤 1: 生成签名密钥

在有 Android SDK 的电脑上运行以下命令生成 debug.keystore：



```bash
keytool -genkey -v -keystore debug.keystore \
  -storepass android -alias androiddebugkey -keypass android \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"
```

## 步骤 2: 转换为 Base64

```bash
# macOS / Linux
base64 -i debug.keystore

# Windows (PowerShell)
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("debug.keystore"))
```

## 步骤 3: 添加到 GitHub Secrets

1. 打开你的 GitHub 仓库
2. 进入 Settings → Secrets and variables → Actions
3. 点击 "New repository secret"
4. 名称: `KEYSTORE_BASE64`
5. 值: 粘贴上一步生成的 Base64 字符串
6. 点击 "Add secret"

## 步骤 4: 提交 CI 配置

```bash
git add .github/workflows/build-apk.yml
git commit -m "feat: 使用固定的签名密钥"
git push
```

这样每次构建都会使用相同的签名，覆盖安装时就不会提示签名不一致了。

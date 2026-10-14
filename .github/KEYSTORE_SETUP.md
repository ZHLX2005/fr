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

---

## 微豆子 keystore（`WEIDOUZI_KEYSTORE_BASE64`）

微豆子（build-apk-v2.yml 的 `app=weidouzi` 链）使用**独立签名**，与小豆子的 `KEYSTORE_BASE64` 互不影响。

本仓库的微豆子 keystore 已按下面命令生成（PKCS12，alias=`weidouzi`，口令=`android`，有效期 30 年），备份在本地 `.tool/weidouzi-keystore/`（不入 git）：

```bash
# 1. 生成自签名证书 + 私钥（Git Bash / Linux / macOS）
MSYS_NO_PATHCONV=1 openssl req -x509 -newkey rsa:2048 \
  -keyout weidouzi.key.pem -out weidouzi.cert.pem \
  -days 10950 -nodes -subj "/CN=weidouzi/O=xiaodouzi"

# 2. 打包为 PKCS12 keystore（口令 android，PKCS12 要求 store/key 同口令）
openssl pkcs12 -export -in weidouzi.cert.pem -inkey weidouzi.key.pem \
  -out weidouzi.keystore -name weidouzi -passout pass:android

# 3. 转 Base64 并写入全新 secret（不覆盖现有 KEYSTORE_BASE64）
base64 -w0 weidouzi.keystore > weidouzi.keystore.b64
gh secret set WEIDOUZI_KEYSTORE_BASE64 --repo ZHLX2005/fr < weidouzi.keystore.b64
```

落点约定：
- CI：`secrets.WEIDOUZI_KEYSTORE_BASE64` → `android/app/weidouzi.keystore`
- 本地：`android/app/weidouzi.keystore`（`android/.gitignore` 的 `**/*.keystore` 已忽略，不会入库）
- Gradle 引用：`android/app/build.gradle.kts` 的 `signingConfigs.create("weidouzi")`（alias `weidouzi`，口令 `android`）

# FGS MediaProjection Debug — 异常分类与排查流程

> 何时读：遇到 SecurityException / IllegalArgumentException / Unable to start service，需要按异常类型分类排查，或怀疑已安装 APK 与源码不匹配时。
>
> 本文档原为独立 `android-fgs-media-projection-debug` skill，合并入 android-media-projection-fix 后归档在此提供"按异常类型分类"的排查 SOP —— 主文档偏"7 轮修复经验"，本文档偏"按异常类型分流"。

---

## Scope

Apply this skill when logs mention any of the following:

- `foregroundServiceType`
- `startForeground`
- `FOREGROUND_SERVICE_MEDIA_PROJECTION`
- `CAPTURE_VIDEO_OUTPUT`
- `MediaProjection`
- `Unable to start service`
- `SecurityException`
- `IllegalArgumentException`
- app behavior that suggests the installed APK does not match the current source

## Files to inspect first

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/io/github/xiaodouzi/fr/MainActivity.kt`
- `android/app/src/main/kotlin/io/github/xiaodouzi/fr/native/pigment/PigmentFloatingManager.kt`
- `android/app/src/main/kotlin/io/github/xiaodouzi/fr/native/overlay/FloatingWindowManager.kt`
- `android/app/src/main/kotlin/io/github/xiaodouzi/fr/native/overlay/FloatingChannel.kt`

## Triage order

Always debug in this order:

1. Classify the crash from the exact exception text.
2. Map the failing stack frame to the current local source.
3. Check manifest service declaration against the `startForeground(...)` call.
4. Check whether the service is promoted to foreground too early.
5. Check whether the installed build is stale and does not match the workspace.

Do not jump straight to changing permissions or constants before classifying the exception.

## Exception classifier

### Case 1: subset mismatch

Example signal:

```text
IllegalArgumentException: foregroundServiceType 0x... is not a subset of foregroundServiceType attribute 0x... in service element of manifest file
```

Meaning:

- The type passed to `startForeground(id, notification, type)` does not match the service's `android:foregroundServiceType` in the manifest.

Actions:

1. Inspect the service entry in `AndroidManifest.xml`.
2. Replace hardcoded bitmasks with `ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` when the manifest says `mediaProjection`.
3. For Android Q and above, use the 3-arg `startForeground(...)`.
4. For pre-Q, fall back to the 2-arg overload.

### Case 2: permission/timing failure for mediaProjection

Example signal:

```text
SecurityException: Starting FGS with type mediaProjection ... requires permissions ...
```

Meaning in this repo:

- The app is trying to promote a service to `mediaProjection` foreground service before the screen-capture permission flow has completed.

Actions:

1. Check `onStartCommand(...)` in the crashing service.
2. If `ACTION_START` immediately calls `promoteToForeground()`, that is suspicious.
3. In this repo, startup should usually be:
   - start service
   - show overlay or bubble only
   - request screen capture permission from `MainActivity`
   - after `onActivityResult(...)` success, call `promoteToForeground()`
   - then obtain or wire `MediaProjection`
4. Verify `MainActivity.handleScreenCaptureResult(...)` is the place that calls `promoteToForeground()`.

### Case 3: runtime log does not match local code

Example signal:

- stack line numbers imply a method call that no longer exists locally
- crash says `onStartCommand` called `promoteToForeground()`, but local source shows `showBubble()`

Meaning:

- The installed APK is stale, or the device is running a build from another directory or variant.

Actions:

1. Print local line-numbered source around the reported line.
2. Compare it with the stack trace.
3. If they do not match, stop changing logic and tell the user to reinstall from the current workspace.
4. Recommend:
   - uninstall `io.github.xiaodouzi.fr.debug`
   - `flutter clean`
   - reinstall with `flutter run`
5. If needed, ask for:
   - fresh logcat
   - `adb shell dumpsys package io.github.xiaodouzi.fr.debug`

## Repo-specific rules

### Rule 1: do not trust hardcoded FGS bitmasks

If you see values like:

- `0x00000040`
- `0x00000020`
- `0x00000004`

verify them against the manifest and replace them with platform constants when possible.

### Rule 2: `PigmentFloatingManager` is easy to break by promoting too early

For pigment flow, `ACTION_START` should not immediately enter mediaProjection foreground mode unless you have already proven permission is granted and the repo intentionally depends on that order.

### Rule 3: stack traces beat assumptions

If the stack says the crash is at `promoteToForeground(...)`, inspect that exact path first. Do not treat nearby `BlockMonitor` noise or unrelated WebView callbacks as root cause.

### Rule 4: merged manifests matter

If source manifest looks correct but behavior does not, inspect the merged manifest output under `build/.../merged_manifest.../AndroidManifest.xml`.

## Minimal debug workflow

Run targeted searches before editing:

```powershell
rg -n "PigmentFloatingManager|FloatingWindowManager|foregroundServiceType|startForeground\(" android/app/src/main -S
```

```powershell
rg -n "createScreenCaptureIntent|getMediaProjection|promoteToForeground|onActivityResult" android/app/src/main/kotlin -S
```

When comparing stack vs source, print line numbers:

```powershell
$i=1; Get-Content android\app\src\main\kotlin\io\github\xiaodouzi\fr\native\pigment\PigmentFloatingManager.kt | ForEach-Object { '{0}:{1}' -f $i, $_; $i++ }
```

## Fix patterns

### Pattern A: align manifest and code

- Manifest: `android:foregroundServiceType="mediaProjection"`
- Code on Android Q+: `ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`

### Pattern B: delay FGS promotion until permission callback

Bad:

```kotlin
ACTION_START -> {
    promoteToForeground()
    showBubble()
}
```

Good:

```kotlin
ACTION_START -> {
    showBubble()
}
```

Then promote later from `MainActivity` after permission success.

### Pattern C: separate source fix from install-state diagnosis

If the local file already contains the expected fix, do not keep patching the same logic. Verify the installed app is current.

## Validation checklist

After edits, verify these points:

1. The crashing service's manifest entry declares the same foreground service type used in code.
2. No stale hardcoded type values remain in the Android app source.
3. `ACTION_START` path does not promote to `mediaProjection` too early.
4. `MainActivity` performs permission-result handling for the service.
5. The newest runtime stack matches the current local source lines.

## What not to do

- Do not assume `targetSdk=35` failures are fixed by adding more manifest permissions alone.
- Do not keep editing logic when logs clearly show the device is running an old APK.
- Do not generalize from unrelated Android services in the repo such as audio playback.
- Do not present Gradle environment failures as proof that the app logic is wrong.

## Expected outputs

When using this skill, produce:

- a short diagnosis naming the exact failure class
- the repo file and line that are responsible
- the smallest safe code change, if source is actually wrong
- or a clear statement that the installed APK is stale, if source and stack do not match
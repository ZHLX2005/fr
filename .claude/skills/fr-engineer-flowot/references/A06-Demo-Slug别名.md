---
name: A06-Demo-Slug别名
description: FR demo slug 兼容与外部 URL 别名注册 SOP。变更 demo URL 或需兼容旧地址时读取。
---

# A06 — Demo slug 别名 SOP

> **适用范围**：FR `DemoPage` / `demoRegistry`。本 ref 只讲 canonical slug 与兼容旧 URL，不包含大型模块合并、拆分或 Tab 容器设计方案。

## 何时使用

- 已发布 widget、通知、外部文档、二维码或用户书签继续使用旧的 `fr://lab/demo/<slug>`。
- demo 的规范 slug 因命名调整而变化，但旧 URL 仍有实际兼容需求。
- 外部跳转须迁移到新 URL，而旧链接需要有期限地过渡。

没有外部持久链接时，不应为了“预防万一”添加 alias；直接更新仍可控的引用即可。

## 注册步骤

1. 在 `DemoPage` 子类声明当前唯一 canonical `slug`；保持 FR 纯 ASCII slug 规范。
2. 搜索旧 slug 的真实来源：widget PendingIntent、MethodChannel、通知/分享链接、项目外文档、测试及本地持久化。
3. 明确哪些来源仍需要兼容，并记录后续移除 alias 的条件。
4. 对需要保留的每个 key 显式注册到同一实例：

```dart
final demo = ExampleDemo();
demoRegistry.register(demo); // canonical key 来自 ExampleDemo.slug
if (needsLegacyCompatibility) {
  demoRegistry.register(demo, key: 'old-example');
}
```

5. 测试 canonical/aliases 返回 `same(demo)`；对 unknown/removed slug 测试预期的 not-found 行为。
6. 同步更新所有仍可控的外部引用到 canonical slug。兼容期限结束并核实持久化链接影响后，再移除 alias。

## 规则与边界

| 项目 | 要求 |
|---|---|
| Canonical slug | 当前 demo 唯一规范 URL key，定义于 `DemoPage.slug` |
| Alias key | 明确为兼容旧 URL 手工注册；注册到同一 `DemoPage` 实例 |
| 字符集 | canonical 和 aliases 均遵循 FR 纯 ASCII slug 规范 |
| 删除 alias | 先核验 widget/外部保存 URL/通知/持久化来源；不能只根据仓库内搜索无引用就删除 |
| 路由机制 | 所有 deep link 均经过 `fr://` route registry；详见 [[A01-fr路由注册与防腐蚀]] 与 [[A02-fr-Router路由机制]] |

## 错误定位

| 症状 | 检查 | 修复与验证 |
|---|---|---|
| 旧 URL 404 | 从完整 URI 提取 slug；核对它是否注册、URI authority 与注册 key 是否字符级一致 | 仍需兼容则注册 alias 并断言 `same()`；不再兼容则更新所有可控来源。用 route/registry test 验证 |
| 新 demo 无法 resolve | 检查 `DemoPage.slug`、bootstrap 注册与 key 冲突 | 修正 canonical slug/注册；用具体 URI 断言目标 demo/handler，不能仅断言非空 |
| alias 打开了错误页面 | 检查同一 key 是否被后注册覆盖、是否注册到正确 demo 实例 | 删除冲突注册、让 canonical/alias 指向预期实例；增加 identity assertion |

## 验收清单

- [ ] 每个 alias 都对应有证据的历史/外部入口；无用途 key 不新增。
- [ ] Canonical slug 唯一且符合项目字符规范。
- [ ] Alias 与 canonical 解析到同一个 demo instance。
- [ ] Widget、通知、MethodChannel、外部文档等 URL 来源已逐项核对。
- [ ] Deep-link/registry 测试覆盖具体 slug、冲突和 unknown key 行为。

## 边界说明

多个 demo 是否应改造成统一 Tab 容器，是模块/产品结构决策，应先读 A00 与 A03 进行评估；本 ref 只负责 slug 别名，不承载合并方案。

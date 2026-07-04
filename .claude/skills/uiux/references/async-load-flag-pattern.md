# Async Load Flag Pattern — 嵌套 sheet 异步加载防 race condition

> 何时读：嵌套 ModalBottomSheet 里"打开下一层 sheet 显示空空如也"/"没有找到任何数据库"/缓存竞态/异步加载没完成用户已点进 picker。

---

## Bug 案例（2026-07-04 小豆子 FR）

### 现象

Notion 图床 → 点 ⚙ 设置 → 点"数据库"行（选数据库）→ 弹 `_DatabasePickerSheet` → **始终显示"没有找到任何数据库"**，即使本地 SharedPreferences 缓存里有数据、即使刚手动刷新过。

### 根因（race condition）

`_SettingsSheetState.initState()` 调 `_loadCachedDatabases()` 是 **fire-and-forget** 异步：

```dart
@override
void initState() {
  super.initState();
  _tokenController = TextEditingController(text: widget.initialToken);
  _dbId = widget.initialDbId;
  _dbName = widget.initialDbName;
  _loadCachedDatabases();   // ❌ 异步，未 await
}

Future<void> _loadCachedDatabases() async {
  final prefs = await SharedPreferences.getInstance();  // IO 延迟
  final cached = prefs.getString(_kDbListPrefsKey(token));
  // ...
  setState(() { _databases = ...; });  // ⚠️ 此时 picker 已经被打开过
}
```

`SharedPreferences.getInstance()` 是 IO 异步，用户从打开设置 → 点"数据库"行（50-200ms 内）→ `_databases` 仍是 `[]` → picker 显示空空如也。

**嵌套 sheet 加重了 race**：`SettingsSheet` 是 ModalBottomSheet，`DatabasePickerSheet` 又是 ModalBottomSheet。用户**不需要先关掉当前 sheet**，直接点"数据库"行就跳进去。留给 IO 的时间极短。

### 修复模式（`_loadingXxx` flag 三件套）

```dart
class _SettingsSheetState extends State<_SettingsSheet> {
  List<_DatabaseInfo> _databases = [];
  bool _loadingCache = true;   // ← 关键：默认 true

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
    _dbId = widget.initialDbId;
    _dbName = widget.initialDbName;
    _loadCachedDatabases();
  }

  /// 三件套要点：
  /// 1. try/finally 保证 _loadingCache 一定置 false（即使异常）
  /// 2. mounted 检查避免 widget 已销毁时 setState
  /// 3. _loadingCache 标志保护 picker 进入
  Future<void> _loadCachedDatabases() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      if (mounted) setState(() => _loadingCache = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kDbListPrefsKey(token));
    try {
      if (cached != null && cached.isNotEmpty) {
        final list = jsonDecode(cached) as List<dynamic>;
        if (mounted) {
          setState(() {
            _databases = list.map((e) {
              final m = e as Map<String, dynamic>;
              return _DatabaseInfo(m['id'] as String, m['title'] as String);
            }).toList();
          });
        }
      }
    } catch (_) {
      await prefs.remove(_kDbListPrefsKey(token));
    } finally {
      // 关键：无论成功/失败/无缓存，都置 false
      if (mounted) setState(() => _loadingCache = false);
    }
  }

  Future<void> _pickDatabase() async {
    // 守卫：缓存还在加载 → 等待 + SnackBar 反馈
    if (_loadingCache) {
      _showSnack('数据库列表加载中，请稍候…');
      for (int i = 0; i < 20 && _loadingCache; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (_loadingCache) {
        _showSnack('缓存加载超时，请刷新重试');
        return;
      }
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<_DatabaseInfo>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DatabasePickerSheet(
        databases: _databases,        // ← 此时一定已就绪
        loading: _loadingDbs,
        error: _dbLoadError,
        currentId: _dbId,
        onRetry: _fetchDatabases,
      ),
    );
    // ...
  }
}
```

## 模式要点（必须同时满足）

1. **`_loadingCache = true` 默认值**：initState 一启动就置位，避免"还没开始加载但 flag 是 false"的窗口期
2. **`try/finally` 一定置 false**：即使缓存损坏、空 token、IO 异常都不能让 flag 卡在 true
3. **`mounted` 检查**：异步 await 之后 widget 可能已销毁（用户关了 sheet），setState 会抛异常
4. **`_pickDatabase` 守卫**：flag 是 true 时不直接打开 picker，先等待（带超时 + SnackBar 反馈）
5. **`_fetchDatabases` 存缓存**：成功后 `prefs.setString(...)`，下次开走 cache 路径（用户主动刷新才刷新）

## 反模式

```dart
// ❌ 反模式 1：fire-and-forget，无 flag 保护
void initState() {
  super.initState();
  _loadData();  // 用户操作比异步 IO 快 → 空状态
}

// ❌ 反模式 2：flag 默认 false
bool _loadingCache = false;   // 初始化到第一次 setState 之间有窗口

// ❌ 反模式 3：try/catch 包裹但不置 false
try { ... } catch (_) {}
// 没有 finally → 异常时 flag 卡在 true，picker 永远打不开

// ❌ 反模式 4：await 后不检查 mounted
Future<void> _load() async {
  await Future.delayed(Duration(seconds: 1));
  setState(() {});   // widget 可能已销毁
}

// ❌ 反模式 5：picker 里用空数组直接显示"没有找到"
// 应该在 picker 也判断 databases.isEmpty && loadingCache 时显示 spinner
```

## 适用场景

任何嵌套 sheet + 异步初始数据的场景：
- 设置抽屉 → 选择器（数据库选择、账户选择、配色选择）
- 详情页 → 子表（关联项列表、评论列表）
- 主页面 → 弹窗（搜索结果、过滤后列表）

## 触发关键词

- "打开选择器显示空的" / "看不到缓存数据" / "每次都要手动刷新"
- "明明有缓存但是显示空" / "为什么选择器里没有数据"
- "fire-and-forget" / "async init" / "race condition"

## 项目内范例

- `lib/lab/demos/notion_image_host_demo.dart:550-560` — `_loadingCache` 标志 + 三件套实现
- `lib/lab/demos/notion_image_host_demo.dart:687-720` — `_pickDatabase` 守卫实现
/// nx-nx（项目生成器）的响应形状。
///
/// nx-nx 的 HTTP 层统一套一层信封（`{ok, data}`），所以这里的每个模型
/// 都是**信封里那一层**。信封本身由 `MnWsAppClient` 统一剥掉。
///
/// 为什么在 fr 里重新写一遍形状、而不是直接用动态 Map：
/// 面板要**按 schema 驱动**渲染（模板加一个选项，页面自动多一个控件），
/// 字段名拼错要能在编译期/单测里发现，而不是界面上少一个输入框。
library;

// ───────────────────────── system ─────────────────────────

/// `GET /api/bootstrap` 的应用信息段。
class NxNxAppInfo {
  final String name;
  final String title;
  final String description;
  final String version;

  const NxNxAppInfo({
    required this.name,
    required this.title,
    required this.description,
    required this.version,
  });

  factory NxNxAppInfo.fromJson(Map<String, dynamic> json) => NxNxAppInfo(
        name: '${json['name'] ?? ''}',
        title: '${json['title'] ?? ''}',
        description: '${json['description'] ?? ''}',
        version: '${json['version'] ?? ''}',
      );
}

/// `GET /api/bootstrap` —— 一次取齐面板启动所需的全部上下文。
class NxNxBootstrap {
  final NxNxAppInfo app;
  final String storePath;
  final String storeEnv;
  final String templatesDir;
  final List<NxNxTemplate> templates;

  /// 不合法的模板（列不出来，但要说出来 —— 静默吞掉会让人以为没有）。
  final List<NxNxTemplateError> templateErrors;

  /// **命令表**：CLI 命令与 HTTP 路由的对照。
  ///
  /// 面板底下的「这个按钮的 CLI 等价是什么」由它派生 —— 不是手写字符串，
  /// 所以命令一改，提示不会悄悄过期。
  final List<NxNxCommand> commands;

  const NxNxBootstrap({
    required this.app,
    required this.storePath,
    required this.storeEnv,
    required this.templatesDir,
    required this.templates,
    required this.templateErrors,
    required this.commands,
  });

  factory NxNxBootstrap.fromJson(Map<String, dynamic> json) {
    final templates = <NxNxTemplate>[];
    final raw = json['templates'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) templates.add(NxNxTemplate.fromJson(e));
      }
    }
    final errors = <NxNxTemplateError>[];
    final rawErr = json['templateErrors'];
    if (rawErr is List) {
      for (final e in rawErr) {
        if (e is Map<String, dynamic>) errors.add(NxNxTemplateError.fromJson(e));
      }
    }
    final commands = <NxNxCommand>[];
    final rawCmds = json['commands'];
    if (rawCmds is List) {
      for (final e in rawCmds) {
        if (e is Map<String, dynamic>) commands.add(NxNxCommand.fromJson(e));
      }
    }
    return NxNxBootstrap(
      app: NxNxAppInfo.fromJson(
        (json['app'] as Map<String, dynamic>?) ?? const {},
      ),
      storePath: '${json['storePath'] ?? ''}',
      storeEnv: '${json['storeEnv'] ?? ''}',
      templatesDir: '${json['templatesDir'] ?? ''}',
      templates: templates,
      templateErrors: errors,
      commands: commands,
    );
  }
}

/// 一条 CLI 命令（bootstrap 的 `commands[]` 里的一项）。
class NxNxCommand {
  final String id;
  final String module;

  /// 命令本身（如 `nx-nx template list`）。
  final String command;

  /// 用法串（如 `nx-nx template describe <id>`）。
  final String usage;

  /// 一句话说明。
  final String summary;

  /// 对应的 HTTP 路由（platform 那几条没有 HTTP 面）。
  final String? http;

  const NxNxCommand({
    required this.id,
    required this.module,
    required this.command,
    required this.usage,
    required this.summary,
    required this.http,
  });

  factory NxNxCommand.fromJson(Map<String, dynamic> json) => NxNxCommand(
        id: '${json['id'] ?? ''}',
        module: '${json['module'] ?? ''}',
        command: '${json['command'] ?? ''}',
        usage: '${json['usage'] ?? ''}',
        summary: '${json['summary'] ?? ''}',
        http: json['http'] == null ? null : '${json['http']}',
      );
}

/// 一条路由（`GET /api/routes`）。
class NxNxRoute {
  final String id;
  final String module;
  final String cli;
  final String? http;
  final String summary;

  const NxNxRoute({
    required this.id,
    required this.module,
    required this.cli,
    required this.http,
    required this.summary,
  });

  factory NxNxRoute.fromJson(Map<String, dynamic> json) => NxNxRoute(
        id: '${json['id'] ?? ''}',
        module: '${json['module'] ?? ''}',
        cli: '${json['cli'] ?? ''}',
        http: json['http'] == null ? null : '${json['http']}',
        summary: '${json['summary'] ?? ''}',
      );
}

/// `GET /api/health`。
class NxNxHealth {
  final String status;
  final String templatesDir;
  final int templates;
  final List<String> broken;
  final String reason;

  const NxNxHealth({
    required this.status,
    required this.templatesDir,
    required this.templates,
    required this.broken,
    required this.reason,
  });

  factory NxNxHealth.fromJson(Map<String, dynamic> json) => NxNxHealth(
        status: '${json['status'] ?? ''}',
        templatesDir: '${json['templatesDir'] ?? ''}',
        templates: _intOf(json['templates']),
        broken: _strListOf(json['broken']),
        reason: '${json['reason'] ?? ''}',
      );
}

/// `GET /api/store`。
class NxNxStore {
  final String status;
  final String path;
  final String env;

  const NxNxStore({required this.status, required this.path, required this.env});

  factory NxNxStore.fromJson(Map<String, dynamic> json) => NxNxStore(
        status: '${json['status'] ?? ''}',
        path: '${json['path'] ?? ''}',
        env: '${json['env'] ?? ''}',
      );
}

// ───────────────────────── template ─────────────────────────

/// 不合法的模板。
class NxNxTemplateError {
  final String id;
  final String message;

  const NxNxTemplateError({required this.id, required this.message});

  factory NxNxTemplateError.fromJson(Map<String, dynamic> json) =>
      NxNxTemplateError(
        id: '${json['id'] ?? ''}',
        message: '${json['message'] ?? ''}',
      );
}

/// 模板的一个**选项**（schema）。
///
/// 面板按它渲染表单：类型决定控件、required 决定分组、pattern/values 决定校验。
class NxNxOption {
  final String name;
  final String type;
  final String label;
  final bool required;
  final String hint;

  /// 默认值（服务端 resolveVars 会用它回落）。
  final Object? defaultValue;

  /// 枚举取值（type=enum 时）。
  final List<String> values;

  /// 模板声明的格式约束（正则源码）。
  final String? pattern;

  const NxNxOption({
    required this.name,
    required this.type,
    required this.label,
    required this.required,
    required this.hint,
    this.defaultValue,
    this.values = const [],
    this.pattern,
  });

  factory NxNxOption.fromJson(Map<String, dynamic> json) => NxNxOption(
        name: '${json['name'] ?? ''}',
        type: '${json['type'] ?? 'string'}',
        label: '${json['label'] ?? ''}',
        required: json['required'] == true,
        hint: '${json['hint'] ?? ''}',
        defaultValue: json['default'],
        values: _strListOf(json['values']),
        pattern: json['pattern'] == null ? null : '${json['pattern']}',
      );
}

/// 一个模板。
class NxNxTemplate {
  final String id;
  final String name;
  final String description;
  final List<String> nextSteps;
  final List<NxNxOption> options;

  /// 项目名前缀（服务端派生变量用）。
  final String namePrefix;

  /// `siblings` 模式的模板需要用户自己填输出目录（不能按项目名猜）。
  final String outputMode;

  /// 模板声明不画 logo（纯目录骨架等）。
  final bool? logo;

  const NxNxTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.nextSteps,
    required this.options,
    this.namePrefix = '',
    this.outputMode = '',
    this.logo,
  });

  factory NxNxTemplate.fromJson(Map<String, dynamic> json) {
    final options = <NxNxOption>[];
    final raw = json['options'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) options.add(NxNxOption.fromJson(e));
      }
    }
    return NxNxTemplate(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      nextSteps: _strListOf(json['nextSteps']),
      options: options,
      namePrefix: '${json['namePrefix'] ?? ''}',
      outputMode: '${json['outputMode'] ?? ''}',
      logo: json['logo'] == null ? null : json['logo'] == true,
    );
  }

  /// `siblings` 模式的模板：输出目录得用户自己填。
  bool get isSiblings => outputMode == 'siblings';
}

/// `GET /api/templates/:id` —— 模板详情（含 README 与目录）。
class NxNxTemplateDetail {
  final NxNxTemplate template;
  final String readme;
  final String dir;

  const NxNxTemplateDetail({
    required this.template,
    required this.readme,
    required this.dir,
  });

  factory NxNxTemplateDetail.fromJson(Map<String, dynamic> json) => NxNxTemplateDetail(
        template: NxNxTemplate.fromJson(
          (json['template'] as Map<String, dynamic>?) ?? const {},
        ),
        readme: '${json['readme'] ?? ''}',
        dir: '${json['dir'] ?? ''}',
      );
}

/// `POST /api/templates/:id/preview` —— 将生成的文件清单（不写盘）。
class NxNxPreview {
  final String template;
  final Map<String, dynamic> vars;
  final List<String> files;

  const NxNxPreview({
    required this.template,
    required this.vars,
    required this.files,
  });

  factory NxNxPreview.fromJson(Map<String, dynamic> json) => NxNxPreview(
        template: '${json['template'] ?? ''}',
        vars: (json['vars'] as Map<String, dynamic>?) ?? const {},
        files: _strListOf(json['files']),
      );

  /// 将创建的文件数。
  int get count => files.length;
}

/// `POST /api/templates/:id/create`。
class NxNxCreateResult {
  final int count;
  final List<String> nextSteps;
  final Map<String, dynamic> extra;

  const NxNxCreateResult({
    required this.count,
    required this.nextSteps,
    required this.extra,
  });

  factory NxNxCreateResult.fromJson(Map<String, dynamic> json) => NxNxCreateResult(
        count: _intOf(json['count']),
        nextSteps: _strListOf(json['nextSteps']),
        extra: (json['extra'] as Map<String, dynamic>?) ?? const {},
      );
}

/// `POST /api/check-dir` —— 目标目录能不能用。
class NxNxDirCheck {
  final bool exists;
  final bool usable;
  final String path;

  /// 非空时的条目数（不可用的原因）。
  final int entries;

  const NxNxDirCheck({
    required this.exists,
    required this.usable,
    required this.path,
    required this.entries,
  });

  factory NxNxDirCheck.fromJson(Map<String, dynamic> json) => NxNxDirCheck(
        exists: json['exists'] == true,
        usable: json['usable'] == true,
        path: '${json['path'] ?? ''}',
        entries: _intOf(json['entries']),
      );
}

// ───────────────────────── skill ─────────────────────────

/// `GET /api/skills`。
class NxNxSkillList {
  final List<String> skills;
  final List<String> groups;
  final String defaultGroup;
  final String source;

  const NxNxSkillList({
    required this.skills,
    required this.groups,
    required this.defaultGroup,
    required this.source,
  });

  factory NxNxSkillList.fromJson(Map<String, dynamic> json) => NxNxSkillList(
        skills: _strListOf(json['skills']),
        groups: _strListOf(json['groups']),
        defaultGroup: '${json['defaultGroup'] ?? ''}',
        source: '${json['source'] ?? ''}',
      );
}

/// 一个 skill 分组。
class NxNxSkillGroup {
  final List<String> skills;
  final String summary;

  const NxNxSkillGroup({required this.skills, required this.summary});

  factory NxNxSkillGroup.fromJson(Map<String, dynamic> json) => NxNxSkillGroup(
        skills: _strListOf(json['skills']),
        summary: '${json['summary'] ?? ''}',
      );
}

/// `GET /api/skill-groups`。
class NxNxSkillGroups {
  final String source;
  final Map<String, NxNxSkillGroup> groups;

  const NxNxSkillGroups({required this.source, required this.groups});

  factory NxNxSkillGroups.fromJson(Map<String, dynamic> json) {
    final groups = <String, NxNxSkillGroup>{};
    final raw = json['groups'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          groups['$k'] = NxNxSkillGroup.fromJson(v);
        }
      });
    }
    return NxNxSkillGroups(
      source: '${json['source'] ?? ''}',
      groups: groups,
    );
  }
}

/// `GET /api/skill-content`。
class NxNxSkillContent {
  final String skillName;
  final String ref;
  final int contentBytes;
  final String prefix;
  final String content;

  const NxNxSkillContent({
    required this.skillName,
    required this.ref,
    required this.contentBytes,
    required this.prefix,
    required this.content,
  });

  factory NxNxSkillContent.fromJson(Map<String, dynamic> json) => NxNxSkillContent(
        skillName: '${json['skillName'] ?? ''}',
        ref: '${json['ref'] ?? ''}',
        contentBytes: _intOf(json['contentBytes']),
        prefix: '${json['prefix'] ?? ''}',
        content: '${json['content'] ?? ''}',
      );
}

// ───────────────────────── script ─────────────────────────

/// 一个脚本。
class NxNxScript {
  final String name;
  final String description;
  final String usage;
  final String notes;
  final String path;

  const NxNxScript({
    required this.name,
    required this.description,
    required this.usage,
    required this.notes,
    required this.path,
  });

  factory NxNxScript.fromJson(Map<String, dynamic> json) => NxNxScript(
        name: '${json['name'] ?? ''}',
        description: '${json['description'] ?? ''}',
        usage: '${json['usage'] ?? ''}',
        notes: '${json['notes'] ?? ''}',
        path: '${json['path'] ?? ''}',
      );
}

/// 脚本里可直接调用的内置全局函数（别名模块）。
class NxNxAlias {
  final String name;
  final String group;
  final String desc;

  const NxNxAlias({
    required this.name,
    required this.group,
    required this.desc,
  });

  factory NxNxAlias.fromJson(Map<String, dynamic> json) => NxNxAlias(
        name: '${json['name'] ?? ''}',
        group: '${json['group'] ?? ''}',
        desc: '${json['desc'] ?? ''}',
      );
}

/// `POST /api/script-run`。
class NxNxRunResult {
  final String script;
  final String path;
  final int code;
  final String stdout;
  final String stderr;

  const NxNxRunResult({
    required this.script,
    required this.path,
    required this.code,
    required this.stdout,
    required this.stderr,
  });

  factory NxNxRunResult.fromJson(Map<String, dynamic> json) => NxNxRunResult(
        script: '${json['script'] ?? ''}',
        path: '${json['path'] ?? ''}',
        code: _intOf(json['code']),
        stdout: '${json['stdout'] ?? ''}',
        stderr: '${json['stderr'] ?? ''}',
      );

  /// 退出码为 0 就算成功。
  bool get ok => code == 0;
}

// ───────────────────────── 内部工具 ─────────────────────────

int _intOf(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

List<String> _strListOf(Object? v) {
  if (v is! List) return const [];
  return v.map((e) => '$e').where((e) => e.isNotEmpty).toList();
}

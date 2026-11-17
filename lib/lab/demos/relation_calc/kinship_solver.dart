// 亲戚关系的**结构推导** —— 规则库没配到时的兜底。
//
// 为什么需要它（fr #14 反馈）：
//   「这个排列组合关系 保证所有关系的组合，三层 十乘十乘十都有对应的值」
// 关系库（可编辑的 entities/terms/rules）是「用户拍的称谓表」，它天生有洞：
// 十个关系词、三层组合共 10×10×10 = 1000 条，手写规则不可能覆盖完
// （现状连「妈妈的爸爸的姐姐」这种都在「无法计算」）。
//
// 所以这一层不查表画画，而是**按结构推**：
//   · 每一步都更新「辈分 / 性别 / 走到这儿的路径」；
//   · 常用组合走称谓合成表（爸爸+哥哥=伯父、爷爷+姐妹=姑婆…），
//     表与预设 `kinship_preset.dart` 的 note 口径一致；
//   · 合成表没有的组合不算失败，降级成**描述式**（「奶奶的爸爸」）——
//     它不是标准称谓，但它是**值**，比「无法计算」有用；
//   · 真不可能的（爸爸的丈夫、妈妈的妻子、哥哥的丈夫…）才判**无此关系**，
//     并且要说清为什么（性别矛盾），而不是笼统的「无匹配规则」。
//
// 它只服务中文亲戚这一个域，且只从「我」出发（三层组合就是以我为原点数的）。
// 换起点（爷爷 / 组长）时仍走关系库 —— 那套是领域无关的通用引擎。

/// 十个基础关系词（与 `kKinshipTerms` 的 id 一一对应）。
enum KinStep {
  father('爸爸', 't_father'),
  mother('妈妈', 't_mother'),
  elderBrother('哥哥', 't_elder_brother'),
  youngerBrother('弟弟', 't_younger_brother'),
  elderSister('姐姐', 't_elder_sister'),
  youngerSister('妹妹', 't_younger_sister'),
  son('儿子', 't_son'),
  daughter('女儿', 't_daughter'),
  husband('丈夫', 't_husband'),
  wife('妻子', 't_wife');

  const KinStep(this.label, this.termId);

  final String label;
  final String termId;

  /// 这一步之后那个人的性别（配偶必然异性，所以丈夫是男、妻子是女）。
  bool get male => switch (this) {
        KinStep.father || KinStep.elderBrother || KinStep.youngerBrother => true,
        KinStep.son || KinStep.husband => true,
        _ => false,
      };

  /// 这一步之后的辈分增量：长辈 +1、晚辈 -1、平辈与配偶 0。
  int get genDelta => switch (this) {
        KinStep.father || KinStep.mother => 1,
        KinStep.son || KinStep.daughter => -1,
        _ => 0,
      };

  static KinStep? byTermId(String id) {
    for (final s in KinStep.values) {
      if (s.termId == id) return s;
    }
    return null;
  }

  static KinStep? byLabel(String name) {
    for (final s in KinStep.values) {
      if (s.label == name) return s;
    }
    return null;
  }
}

/// 推导结果。
class KinAnswer {
  const KinAnswer({
    required this.label,
    this.standard = true,
    this.reason,
  });

  /// 结果显示的答案：称谓（「姑婆」）或描述式（「奶奶的爸爸」）。
  final String label;

  /// 是否常用称谓。false = 描述式（没有通行叫法，只能这么读）。
  final bool standard;

  /// 非空 = 无此关系，值是原因（「爸爸是男性，没有丈夫」）。
  final String? reason;

  bool get impossible => reason != null;
}

/// 从「我」出发推一条链；任一关系词不认识返回 null（交给关系库）。
KinAnswer? solveKinship(List<String> termIds) {
  final steps = <KinStep>[];
  for (final id in termIds) {
    final s = KinStep.byTermId(id);
    if (s == null) return null;
    steps.add(s);
  }

  // 我：性别未知（后面用到时再确定；矛盾就判无此关系）。
  bool? sexMale;
  var label = '我';
  // 原始路径（描述式兜底用）：只记「说了什么」，不化简
  final said = <String>[];
  var standard = true;

  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];

    // ── 配偶：只能在异性身上成立 ──
    if (s == KinStep.husband || s == KinStep.wife) {
      // 「妻子」要求当前这个人是男性，「丈夫」要求是女性 —— 反过来就是矛盾
      final needsMale = s == KinStep.wife;
      if (sexMale != null && sexMale != needsMale) {
        return KinAnswer(
          label: '',
          standard: false,
          reason: '「$label」是${sexMale ? '男' : '女'}性，没有${s.label}',
        );
      }
      // 配偶抵消：妻子的丈夫 = 我、丈夫的妻子 = 我
      if (said.isNotEmpty) {
        final prev = KinStep.byLabel(said.last);
        if ((prev == KinStep.wife && s == KinStep.husband) ||
            (prev == KinStep.husband && s == KinStep.wife)) {
          said.removeLast();
          // 抵消后回到上一层：借「重新推一遍前缀」拿到正确状态
          final prefix = _replay(said);
          sexMale = prefix.$1;
          label = prefix.$2;
          standard = prefix.$3;
          continue;
        }
      }
    }
    // 性别由关系词本身决定：爸爸是男、妈妈是女 —— 与当前是谁无关
    sexMale = s.male;

    final next = _compose(label, s);
    if (next == null) {
      standard = false;
      label = '$label的${s.label}';
    } else {
      label = next;
    }
    said.add(s.label);
  }

  if (steps.isEmpty) {
    return const KinAnswer(label: '我');
  }
  return KinAnswer(label: label, standard: standard);
}

/// 重放一段路径，拿到 (性别, 称谓, 是否标准)。
/// 只在「配偶抵消」后需要回溯时用，路径很短（≤3），成本可忽略。
(bool?, String, bool) _replay(List<String> said) {
  bool? sex;
  var label = '我';
  var standard = true;
  for (final name in said) {
    final s = KinStep.byLabel(name)!;
    sex = s.male;
    final next = _compose(label, s);
    if (next == null) {
      standard = false;
      label = '$label的${s.label}';
    } else {
      label = next;
    }
  }
  return (sex, label, standard);
}

/// 称谓合成表：**已知称谓 + 一步 → 新称谓**；没有就返回 null（降级描述式）。
///
/// 口径与 `kinship_preset.dart` 的 note 对齐（爷爷的哥哥=伯公、奶奶的兄弟=舅公、
/// 外公的姐妹=姑婆…），这样「兜底推出来的」和「预设里写的」不会是两套说法。
String? _compose(String from, KinStep step) => _composeTable[from]?[step];

// 只收「有通行叫法」的组合。收不全是有意的：宁可给描述式（奶奶的爸爸），
// 也不硬编一个可能不对的称谓 —— 这类称谓各地叫法差异极大。
const Map<String, Map<KinStep, String>> _composeTable = {
  '我': {
    KinStep.father: '爸爸',
    KinStep.mother: '妈妈',
    KinStep.elderBrother: '哥哥',
    KinStep.youngerBrother: '弟弟',
    KinStep.elderSister: '姐姐',
    KinStep.youngerSister: '妹妹',
    KinStep.son: '儿子',
    KinStep.daughter: '女儿',
    KinStep.husband: '丈夫',
    KinStep.wife: '妻子',
  },
  '爸爸': {
    KinStep.father: '爷爷',
    KinStep.mother: '奶奶',
    KinStep.elderBrother: '伯父',
    KinStep.youngerBrother: '叔叔',
    KinStep.elderSister: '姑妈',
    KinStep.youngerSister: '姑妈',
    KinStep.son: '兄弟',
    KinStep.daughter: '姐妹',
    KinStep.wife: '妈妈',
  },
  '妈妈': {
    KinStep.father: '外公',
    KinStep.mother: '外婆',
    KinStep.elderBrother: '舅舅',
    KinStep.youngerBrother: '舅舅',
    KinStep.elderSister: '姨妈',
    KinStep.youngerSister: '姨妈',
    KinStep.son: '兄弟',
    KinStep.daughter: '姐妹',
    KinStep.husband: '爸爸',
  },
  '爷爷': {
    KinStep.father: '太爷爷',
    KinStep.mother: '太奶奶',
    KinStep.elderBrother: '伯公',
    KinStep.youngerBrother: '叔公',
    KinStep.elderSister: '姑婆',
    KinStep.youngerSister: '姑婆',
    KinStep.son: '爸爸',
    KinStep.daughter: '姑妈',
    KinStep.wife: '奶奶',
  },
  '奶奶': {
    // 奶奶的父母按预设的口径（`e_great_grandmother` note：奶奶的母亲=太奶奶），
    // 父系这一支统一进「太爷爷/太奶奶」，不拆到外家
    KinStep.father: '太爷爷',
    KinStep.mother: '太奶奶',
    KinStep.elderBrother: '舅公',
    KinStep.youngerBrother: '舅公',
    KinStep.elderSister: '姨婆',
    KinStep.youngerSister: '姨婆',
    KinStep.son: '爸爸',
    KinStep.daughter: '姑妈',
    KinStep.husband: '爷爷',
  },
  '外公': {
    KinStep.father: '太外公',
    KinStep.mother: '太外婆',
    KinStep.elderBrother: '舅公',
    KinStep.youngerBrother: '舅公',
    KinStep.elderSister: '姑婆',
    KinStep.youngerSister: '姑婆',
    KinStep.son: '妈妈',
    KinStep.daughter: '姨妈',
    KinStep.wife: '外婆',
  },
  '外婆': {
    KinStep.father: '太外公',
    KinStep.mother: '太外婆',
    KinStep.elderBrother: '舅公',
    KinStep.youngerBrother: '舅公',
    KinStep.elderSister: '姨婆',
    KinStep.youngerSister: '姨婆',
    KinStep.son: '妈妈',
    KinStep.daughter: '姨妈',
    KinStep.husband: '外公',
  },
  '伯父': {
    KinStep.father: '爷爷',
    KinStep.mother: '奶奶',
    KinStep.elderBrother: '伯父',
    KinStep.youngerBrother: '叔叔',
    KinStep.elderSister: '姑妈',
    KinStep.youngerSister: '姑妈',
    KinStep.son: '堂哥',
    KinStep.daughter: '堂姐',
    KinStep.wife: '伯母',
  },
  '叔叔': {
    KinStep.father: '爷爷',
    KinStep.mother: '奶奶',
    KinStep.elderBrother: '伯父',
    KinStep.youngerBrother: '叔叔',
    KinStep.elderSister: '姑妈',
    KinStep.youngerSister: '姑妈',
    KinStep.son: '堂弟',
    KinStep.daughter: '堂妹',
    KinStep.wife: '婶婶',
  },
  '姑妈': {
    KinStep.father: '爷爷',
    KinStep.mother: '奶奶',
    KinStep.elderBrother: '伯父',
    KinStep.youngerBrother: '叔叔',
    KinStep.elderSister: '姑妈',
    KinStep.youngerSister: '姑妈',
    KinStep.son: '表哥',
    KinStep.daughter: '表姐',
    KinStep.husband: '姑父',
  },
  '舅舅': {
    KinStep.father: '外公',
    KinStep.mother: '外婆',
    KinStep.elderBrother: '舅舅',
    KinStep.youngerBrother: '舅舅',
    KinStep.elderSister: '姨妈',
    KinStep.youngerSister: '姨妈',
    KinStep.son: '表哥',
    KinStep.daughter: '表姐',
    KinStep.wife: '舅妈',
  },
  '姨妈': {
    KinStep.father: '外公',
    KinStep.mother: '外婆',
    KinStep.elderBrother: '舅舅',
    KinStep.youngerBrother: '舅舅',
    KinStep.elderSister: '姨妈',
    KinStep.youngerSister: '姨妈',
    KinStep.son: '表哥',
    KinStep.daughter: '表姐',
    KinStep.husband: '姨父',
  },
  '哥哥': {
    KinStep.father: '爸爸',
    KinStep.mother: '妈妈',
    KinStep.elderBrother: '哥哥',
    KinStep.youngerBrother: '弟弟',
    KinStep.elderSister: '姐姐',
    KinStep.youngerSister: '妹妹',
    KinStep.son: '侄子',
    KinStep.daughter: '侄女',
    KinStep.wife: '嫂子',
  },
  '弟弟': {
    KinStep.father: '爸爸',
    KinStep.mother: '妈妈',
    KinStep.elderBrother: '哥哥',
    KinStep.youngerBrother: '弟弟',
    KinStep.elderSister: '姐姐',
    KinStep.youngerSister: '妹妹',
    KinStep.son: '侄子',
    KinStep.daughter: '侄女',
    KinStep.wife: '弟媳',
  },
  '姐姐': {
    KinStep.father: '爸爸',
    KinStep.mother: '妈妈',
    KinStep.elderBrother: '哥哥',
    KinStep.youngerBrother: '弟弟',
    KinStep.elderSister: '姐姐',
    KinStep.youngerSister: '妹妹',
    KinStep.son: '外甥',
    KinStep.daughter: '外甥女',
    KinStep.husband: '姐夫',
  },
  '妹妹': {
    KinStep.father: '爸爸',
    KinStep.mother: '妈妈',
    KinStep.elderBrother: '哥哥',
    KinStep.youngerBrother: '弟弟',
    KinStep.elderSister: '姐姐',
    KinStep.youngerSister: '妹妹',
    KinStep.son: '外甥',
    KinStep.daughter: '外甥女',
    KinStep.husband: '妹夫',
  },
  '儿子': {
    KinStep.son: '孙子',
    KinStep.daughter: '孙女',
    KinStep.wife: '儿媳',
    // 兄弟姊妹也是我的孩子，只是排行不同
    KinStep.elderBrother: '儿子',
    KinStep.youngerBrother: '儿子',
    KinStep.elderSister: '女儿',
    KinStep.youngerSister: '女儿',
    // 性别未定时两种读法都成立，不装成唯一解
    KinStep.father: '我／丈夫',
    KinStep.mother: '我／妻子',
  },
  '女儿': {
    KinStep.son: '外孙',
    KinStep.daughter: '外孙女',
    KinStep.husband: '女婿',
    KinStep.elderBrother: '儿子',
    KinStep.youngerBrother: '儿子',
    KinStep.elderSister: '女儿',
    KinStep.youngerSister: '女儿',
    KinStep.father: '我／丈夫',
    KinStep.mother: '我／妻子',
  },
  '丈夫': {
    KinStep.father: '公公',
    KinStep.mother: '婆婆',
    KinStep.elderBrother: '大伯子',
    KinStep.youngerBrother: '小叔子',
    KinStep.elderSister: '大姑子',
    KinStep.youngerSister: '小姑子',
    KinStep.son: '儿子',
    KinStep.daughter: '女儿',
  },
  '妻子': {
    KinStep.father: '岳父',
    KinStep.mother: '岳母',
    KinStep.elderBrother: '大舅子',
    KinStep.youngerBrother: '小舅子',
    KinStep.elderSister: '姨姐',
    KinStep.youngerSister: '姨妹',
    KinStep.son: '儿子',
    KinStep.daughter: '女儿',
  },
  '公公': {KinStep.son: '丈夫', KinStep.daughter: '大姑子', KinStep.wife: '婆婆'},
  '婆婆': {KinStep.son: '丈夫', KinStep.daughter: '大姑子', KinStep.husband: '公公'},
  '岳父': {KinStep.son: '妻子', KinStep.daughter: '姨姐', KinStep.wife: '岳母'},
  '岳母': {KinStep.son: '妻子', KinStep.daughter: '姨姐', KinStep.husband: '岳父'},
  '大伯子': {KinStep.wife: '妯娌', KinStep.father: '公公', KinStep.mother: '婆婆', KinStep.son: '侄子', KinStep.daughter: '侄女'},
  '小叔子': {KinStep.wife: '妯娌', KinStep.father: '公公', KinStep.mother: '婆婆', KinStep.son: '侄子', KinStep.daughter: '侄女'},
  '大姑子': {KinStep.son: '外甥', KinStep.daughter: '外甥女', KinStep.father: '公公', KinStep.mother: '婆婆'},
  '小姑子': {KinStep.son: '外甥', KinStep.daughter: '外甥女', KinStep.father: '公公', KinStep.mother: '婆婆'},
  '大舅子': {KinStep.son: '内侄', KinStep.daughter: '内侄女', KinStep.father: '岳父', KinStep.mother: '岳母'},
  '小舅子': {KinStep.son: '内侄', KinStep.daughter: '内侄女', KinStep.father: '岳父', KinStep.mother: '岳母'},
  '姨姐': {KinStep.husband: '连襟', KinStep.father: '岳父', KinStep.mother: '岳母', KinStep.son: '外甥', KinStep.daughter: '外甥女'},
  '姨妹': {KinStep.husband: '连襟', KinStep.father: '岳父', KinStep.mother: '岳母', KinStep.son: '外甥', KinStep.daughter: '外甥女'},
  // 「儿子的爸爸」在不知道我性别时是两个答案，续推也保留这种两读法
  '我／丈夫': {
    KinStep.father: '爸爸／公公',
    KinStep.mother: '妈妈／婆婆',
    KinStep.elderBrother: '哥哥／大伯子',
    KinStep.youngerBrother: '弟弟／小叔子',
    KinStep.elderSister: '姐姐／大姑子',
    KinStep.youngerSister: '妹妹／小姑子',
    KinStep.son: '儿子',
    KinStep.daughter: '女儿',
    KinStep.wife: '我',
  },
  '我／妻子': {
    KinStep.father: '爸爸／岳父',
    KinStep.mother: '妈妈／岳母',
    KinStep.elderBrother: '哥哥／大舅子',
    KinStep.youngerBrother: '弟弟／小舅子',
    KinStep.elderSister: '姐姐／姨姐',
    KinStep.youngerSister: '妹妹／姨妹',
    KinStep.son: '儿子',
    KinStep.daughter: '女儿',
    KinStep.husband: '我',
  },

  // ── 集合称谓的续推（「爸爸的儿子」可能是我也可能是兄弟，统称「兄弟」）──
  // 这一步很关键：不补的话，第二层就开始产「兄弟的妻子」这种读不通的答案。
  '兄弟': {
    KinStep.father: '爸爸',
    KinStep.mother: '妈妈',
    KinStep.elderBrother: '哥哥',
    KinStep.youngerBrother: '弟弟',
    KinStep.elderSister: '姐姐',
    KinStep.youngerSister: '妹妹',
    KinStep.son: '侄子',
    KinStep.daughter: '侄女',
    KinStep.wife: '嫂子／弟媳',
  },
  '姐妹': {
    KinStep.father: '爸爸',
    KinStep.mother: '妈妈',
    KinStep.elderBrother: '哥哥',
    KinStep.youngerBrother: '弟弟',
    KinStep.elderSister: '姐姐',
    KinStep.youngerSister: '妹妹',
    KinStep.son: '外甥',
    KinStep.daughter: '外甥女',
    KinStep.husband: '姐夫／妹夫',
  },

  // ── 子女/孙辈的平辈：同是我的晚辈，只是排行不分 ──
  '孙子': {KinStep.father: '儿子', KinStep.mother: '儿媳', KinStep.wife: '孙媳', KinStep.son: '曾孙', KinStep.daughter: '曾孙女', KinStep.elderBrother: '孙子', KinStep.youngerBrother: '孙子', KinStep.elderSister: '孙女', KinStep.youngerSister: '孙女'},
  '孙女': {KinStep.father: '儿子', KinStep.mother: '儿媳', KinStep.husband: '孙女婿', KinStep.son: '外曾孙', KinStep.daughter: '曾孙女', KinStep.elderBrother: '孙子', KinStep.youngerBrother: '孙子', KinStep.elderSister: '孙女', KinStep.youngerSister: '孙女'},
  '外孙': {KinStep.father: '女婿', KinStep.mother: '女儿', KinStep.wife: '外孙媳', KinStep.son: '曾外孙', KinStep.daughter: '曾外孙女', KinStep.elderBrother: '外孙', KinStep.youngerBrother: '外孙', KinStep.elderSister: '外孙女', KinStep.youngerSister: '外孙女'},
  '外孙女': {KinStep.father: '女婿', KinStep.mother: '女儿', KinStep.husband: '外孙女婿', KinStep.elderBrother: '外孙', KinStep.youngerBrother: '外孙', KinStep.elderSister: '外孙女', KinStep.youngerSister: '外孙女'},

  // ── 侄/甥辈往上找：那一对夫妻就是我的兄弟/姐妹 ──
  '侄子': {
    KinStep.father: '兄弟',
    KinStep.mother: '嫂子／弟媳',
    KinStep.wife: '侄媳',
    KinStep.son: '侄孙',
    KinStep.daughter: '侄孙女',
    KinStep.elderBrother: '侄子',
    KinStep.youngerBrother: '侄子',
    KinStep.elderSister: '侄女',
    KinStep.youngerSister: '侄女',
  },
  '侄女': {
    KinStep.father: '兄弟',
    KinStep.mother: '嫂子／弟媳',
    KinStep.husband: '侄女婿',
    KinStep.elderBrother: '侄子',
    KinStep.youngerBrother: '侄子',
    KinStep.elderSister: '侄女',
    KinStep.youngerSister: '侄女',
  },
  '外甥': {
    KinStep.father: '姐夫／妹夫',
    KinStep.mother: '姐妹',
    KinStep.son: '甥孙',
    KinStep.daughter: '甥孙女',
    KinStep.elderBrother: '外甥',
    KinStep.youngerBrother: '外甥',
    KinStep.elderSister: '外甥女',
    KinStep.youngerSister: '外甥女',
  },
  '外甥女': {
    KinStep.father: '姐夫／妹夫',
    KinStep.mother: '姐妹',
    KinStep.elderBrother: '外甥',
    KinStep.youngerBrother: '外甥',
    KinStep.elderSister: '外甥女',
    KinStep.youngerSister: '外甥女',
  },
  '内侄': {KinStep.father: '大舅子／小舅子', KinStep.mother: '舅嫂'},
  '内侄女': {KinStep.father: '大舅子／小舅子', KinStep.mother: '舅嫂'},

  // 兄嫂/弟媳/姐夫/妹夫：他们的孩子就是我的侄甥，配偶就是我的兄弟姐妹
  '嫂子': {KinStep.son: '侄子', KinStep.daughter: '侄女', KinStep.husband: '哥哥'},
  '弟媳': {KinStep.son: '侄子', KinStep.daughter: '侄女', KinStep.husband: '弟弟'},
  '姐夫': {KinStep.son: '外甥', KinStep.daughter: '外甥女', KinStep.wife: '姐姐'},
  '妹夫': {KinStep.son: '外甥', KinStep.daughter: '外甥女', KinStep.wife: '妹妹'},

  // ── 亲家：儿媳/女婿的父母 ──
  '儿媳': {KinStep.husband: '儿子', KinStep.son: '孙子', KinStep.daughter: '孙女', KinStep.father: '亲家公', KinStep.mother: '亲家母'},
  '女婿': {KinStep.wife: '女儿', KinStep.son: '外孙', KinStep.daughter: '外孙女', KinStep.father: '亲家公', KinStep.mother: '亲家母'},

  // ── 祖辈旁系再往上：那一代的父母就是太爷爷/太奶奶那一档 ──
  '伯公': {KinStep.father: '太爷爷', KinStep.mother: '太奶奶'},
  '叔公': {KinStep.father: '太爷爷', KinStep.mother: '太奶奶'},
  '姑婆': {KinStep.father: '太爷爷', KinStep.mother: '太奶奶'},
  '舅公': {KinStep.father: '太外公', KinStep.mother: '太外婆'},
  '姨婆': {KinStep.father: '太外公', KinStep.mother: '太外婆'},

  // ── 父母辈旁系的配偶与孩子（堂/表那一列）──
  '伯母': {KinStep.son: '堂哥', KinStep.daughter: '堂姐', KinStep.husband: '伯父'},
  '婶婶': {KinStep.son: '堂弟', KinStep.daughter: '堂妹', KinStep.husband: '叔叔'},
  '姑父': {KinStep.son: '表哥', KinStep.daughter: '表姐', KinStep.wife: '姑妈'},
  '舅妈': {KinStep.son: '表哥', KinStep.daughter: '表姐', KinStep.husband: '舅舅'},
  '姨父': {KinStep.son: '表哥', KinStep.daughter: '表姐', KinStep.wife: '姨妈'},

  // ── 堂/表平辈的配偶 ──
  '堂哥': {KinStep.son: '堂侄', KinStep.daughter: '堂侄女', KinStep.wife: '堂嫂'},
  '堂弟': {KinStep.son: '堂侄', KinStep.daughter: '堂侄女', KinStep.wife: '堂弟媳'},
  '堂姐': {KinStep.husband: '堂姐夫'},
  '堂妹': {KinStep.husband: '堂妹夫'},
  '表哥': {KinStep.son: '表侄', KinStep.daughter: '表侄女', KinStep.wife: '表嫂'},
  '表弟': {KinStep.son: '表侄', KinStep.daughter: '表侄女', KinStep.wife: '表弟媳'},
  '表姐': {KinStep.husband: '表姐夫'},
  '表妹': {KinStep.husband: '表妹夫'},
};

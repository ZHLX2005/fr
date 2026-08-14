// 亲戚关系预设 —— 内置数据集（方案 A：只是数据，引擎不感知领域）。
//
// 覆盖：常用直系 + 主要旁系（约 50-80 称谓），用户拍板范围。
// 关系词与称谓在中文里同形（「爸爸」既是实体也是关系词），
// 因此关系词表 = 称谓词子集，规则表用 id 引用，避免歧义。
//
// 注意：模型字段可变（支持 CRUD 改名），不能 const，这里用 final 顶层列表。

import 'relation_calc_models.dart';

// ---------------------------------------------------------------------
// 实体（图的节点）
// ---------------------------------------------------------------------

final List<RelationEntity> kKinshipEntities = [
  // 自我
  RelationEntity(id: 'e_me', name: '我', note: '计算的起点'),
  // 直系长辈
  RelationEntity(id: 'e_father', name: '爸爸', note: '父亲的称呼'),
  RelationEntity(id: 'e_mother', name: '妈妈', note: '母亲的称呼'),
  RelationEntity(id: 'e_grandfather', name: '爷爷', note: '父亲的父亲'),
  RelationEntity(id: 'e_grandmother', name: '奶奶', note: '父亲的母亲'),
  RelationEntity(id: 'e_wai_grandfather', name: '外公', note: '母亲的父亲'),
  RelationEntity(id: 'e_wai_grandmother', name: '外婆', note: '母亲的母亲'),
  RelationEntity(id: 'e_great_grandfather', name: '太爷爷', note: '爷爷的父亲'),
  RelationEntity(id: 'e_great_grandmother', name: '太奶奶', note: '奶奶的母亲'),
  RelationEntity(id: 'e_great_wai_grandfather', name: '太外公', note: '外公的父亲'),
  RelationEntity(id: 'e_great_wai_grandmother', name: '太外婆', note: '外婆的母亲'),
  // 直系平辈
  RelationEntity(id: 'e_elder_brother', name: '哥哥', note: '同辈年长的男性'),
  RelationEntity(id: 'e_younger_brother', name: '弟弟', note: '同辈年幼的男性'),
  RelationEntity(id: 'e_elder_sister', name: '姐姐', note: '同辈年长的女性'),
  RelationEntity(id: 'e_younger_sister', name: '妹妹', note: '同辈年幼的女性'),
  // 直系晚辈
  RelationEntity(id: 'e_son', name: '儿子', note: '男性子女'),
  RelationEntity(id: 'e_daughter', name: '女儿', note: '女性子女'),
  RelationEntity(id: 'e_grandson', name: '孙子', note: '儿子的儿子'),
  RelationEntity(id: 'e_granddaughter', name: '孙女', note: '儿子的女儿'),
  RelationEntity(id: 'e_wai_grandson', name: '外孙', note: '女儿的儿子'),
  RelationEntity(id: 'e_wai_granddaughter', name: '外孙女', note: '女儿的女儿'),
  RelationEntity(id: 'e_great_grandson', name: '曾孙', note: '孙子的儿子'),
  RelationEntity(id: 'e_great_granddaughter', name: '曾孙女', note: '孙子的女儿'),
  // 旁系长辈（父系）
  RelationEntity(id: 'e_uncle_old', name: '伯父', note: '爸爸的哥哥'),
  RelationEntity(id: 'e_aunt_old', name: '伯母', note: '伯父的妻子'),
  RelationEntity(id: 'e_uncle_young', name: '叔叔', note: '爸爸的弟弟'),
  RelationEntity(id: 'e_aunt_young', name: '婶婶', note: '叔叔的妻子'),
  RelationEntity(id: 'e_aunt_paternal', name: '姑妈', note: '爸爸的姐妹'),
  RelationEntity(id: 'e_uncle_paternal', name: '姑父', note: '姑妈的丈夫'),
  // 旁系长辈（母系）
  RelationEntity(id: 'e_uncle_maternal', name: '舅舅', note: '妈妈的兄弟'),
  RelationEntity(id: 'e_aunt_maternal', name: '舅妈', note: '舅舅的妻子'),
  RelationEntity(id: 'e_aunt_maternal_old', name: '姨妈', note: '妈妈的姐妹'),
  RelationEntity(id: 'e_uncle_maternal_old', name: '姨父', note: '姨妈的丈夫'),
  // 旁系平辈（堂/表）
  RelationEntity(id: 'e_cousin_tang_old', name: '堂哥', note: '伯父/叔叔的儿子（年长）'),
  RelationEntity(id: 'e_cousin_tang_young', name: '堂弟', note: '伯父/叔叔的儿子（年幼）'),
  RelationEntity(id: 'e_cousin_tang_sis_old', name: '堂姐', note: '伯父/叔叔的女儿（年长）'),
  RelationEntity(id: 'e_cousin_tang_sis_young', name: '堂妹', note: '伯父/叔叔的女儿（年幼）'),
  RelationEntity(id: 'e_cousin_biao_old', name: '表哥', note: '姑妈/舅舅/姨妈的儿子（年长）'),
  RelationEntity(id: 'e_cousin_biao_young', name: '表弟', note: '姑妈/舅舅/姨妈的儿子（年幼）'),
  RelationEntity(id: 'e_cousin_biao_sis_old', name: '表姐', note: '姑妈/舅舅/姨妈的女儿（年长）'),
  RelationEntity(id: 'e_cousin_biao_sis_young', name: '表妹', note: '姑妈/舅舅/姨妈的女儿（年幼）'),
  // 旁系晚辈
  RelationEntity(id: 'e_nephew_br', name: '侄子', note: '哥哥/弟弟的儿子'),
  RelationEntity(id: 'e_niece_br', name: '侄女', note: '哥哥/弟弟的女儿'),
  RelationEntity(id: 'e_nephew_sis', name: '外甥', note: '姐姐/妹妹的儿子'),
  RelationEntity(id: 'e_niece_sis', name: '外甥女', note: '姐姐/妹妹的女儿'),
  // 姻亲
  RelationEntity(id: 'e_husband', name: '丈夫', note: '配偶（男）'),
  RelationEntity(id: 'e_wife', name: '妻子', note: '配偶（女）'),
  RelationEntity(id: 'e_father_in_law', name: '公公', note: '丈夫的父亲'),
  RelationEntity(id: 'e_mother_in_law', name: '婆婆', note: '丈夫的母亲'),
  RelationEntity(id: 'e_father_in_law_wife', name: '岳父', note: '妻子的父亲'),
  RelationEntity(id: 'e_mother_in_law_wife', name: '岳母', note: '妻子的母亲'),
  RelationEntity(id: 'e_daughter_in_law', name: '儿媳', note: '儿子的妻子'),
  RelationEntity(id: 'e_son_in_law', name: '女婿', note: '女儿的丈夫'),
  RelationEntity(id: 'e_sister_in_law_old', name: '嫂子', note: '哥哥的妻子'),
  RelationEntity(id: 'e_sister_in_law_young', name: '弟媳', note: '弟弟的妻子'),
  RelationEntity(id: 'e_brother_in_law_sis', name: '姐夫', note: '姐姐的丈夫'),
  RelationEntity(id: 'e_brother_in_law_young', name: '妹夫', note: '妹妹的丈夫'),
];

// ---------------------------------------------------------------------
// 关系词（有向边标签）
// ---------------------------------------------------------------------

final List<RelationTerm> kKinshipTerms = [
  RelationTerm(id: 't_father', name: '爸爸'),
  RelationTerm(id: 't_mother', name: '妈妈'),
  RelationTerm(id: 't_elder_brother', name: '哥哥'),
  RelationTerm(id: 't_younger_brother', name: '弟弟'),
  RelationTerm(id: 't_elder_sister', name: '姐姐'),
  RelationTerm(id: 't_younger_sister', name: '妹妹'),
  RelationTerm(id: 't_son', name: '儿子'),
  RelationTerm(id: 't_daughter', name: '女儿'),
  RelationTerm(id: 't_husband', name: '丈夫'),
  RelationTerm(id: 't_wife', name: '妻子'),
];

// ---------------------------------------------------------------------
// 规则（A 的 B = C）
// ---------------------------------------------------------------------

/// 从「我」出发的直接关系。
final List<RelationRule> kKinshipRulesFromMe = [
  RelationRule(id: 'r_me_father', fromId: 'e_me', termId: 't_father', toId: 'e_father'),
  RelationRule(id: 'r_me_mother', fromId: 'e_me', termId: 't_mother', toId: 'e_mother'),
  RelationRule(id: 'r_me_eb', fromId: 'e_me', termId: 't_elder_brother', toId: 'e_elder_brother'),
  RelationRule(id: 'r_me_yb', fromId: 'e_me', termId: 't_younger_brother', toId: 'e_younger_brother'),
  RelationRule(id: 'r_me_es', fromId: 'e_me', termId: 't_elder_sister', toId: 'e_elder_sister'),
  RelationRule(id: 'r_me_ys', fromId: 'e_me', termId: 't_younger_sister', toId: 'e_younger_sister'),
  RelationRule(id: 'r_me_son', fromId: 'e_me', termId: 't_son', toId: 'e_son'),
  RelationRule(id: 'r_me_daughter', fromId: 'e_me', termId: 't_daughter', toId: 'e_daughter'),
  RelationRule(id: 'r_me_husband', fromId: 'e_me', termId: 't_husband', toId: 'e_husband'),
  RelationRule(id: 'r_me_wife', fromId: 'e_me', termId: 't_wife', toId: 'e_wife'),
];

/// 父亲链。
final List<RelationRule> kKinshipRulesFather = [
  RelationRule(id: 'r_father_father', fromId: 'e_father', termId: 't_father', toId: 'e_grandfather'),
  RelationRule(id: 'r_father_mother', fromId: 'e_father', termId: 't_mother', toId: 'e_grandmother'),
  RelationRule(id: 'r_father_eb', fromId: 'e_father', termId: 't_elder_brother', toId: 'e_uncle_old'),
  RelationRule(id: 'r_father_yb', fromId: 'e_father', termId: 't_younger_brother', toId: 'e_uncle_young'),
  RelationRule(id: 'r_father_es', fromId: 'e_father', termId: 't_elder_sister', toId: 'e_aunt_paternal'),
  RelationRule(id: 'r_father_ys', fromId: 'e_father', termId: 't_younger_sister', toId: 'e_aunt_paternal'),
  RelationRule(id: 'r_grandfather_father', fromId: 'e_grandfather', termId: 't_father', toId: 'e_great_grandfather'),
  RelationRule(id: 'r_grandmother_mother', fromId: 'e_grandmother', termId: 't_mother', toId: 'e_great_grandmother'),
];

/// 母亲链。
final List<RelationRule> kKinshipRulesMother = [
  RelationRule(id: 'r_mother_father', fromId: 'e_mother', termId: 't_father', toId: 'e_wai_grandfather'),
  RelationRule(id: 'r_mother_mother', fromId: 'e_mother', termId: 't_mother', toId: 'e_wai_grandmother'),
  RelationRule(id: 'r_mother_eb', fromId: 'e_mother', termId: 't_elder_brother', toId: 'e_uncle_maternal'),
  RelationRule(id: 'r_mother_yb', fromId: 'e_mother', termId: 't_younger_brother', toId: 'e_uncle_maternal'),
  RelationRule(id: 'r_mother_es', fromId: 'e_mother', termId: 't_elder_sister', toId: 'e_aunt_maternal_old'),
  RelationRule(id: 'r_mother_ys', fromId: 'e_mother', termId: 't_younger_sister', toId: 'e_aunt_maternal_old'),
  RelationRule(id: 'r_wai_grandfather_father', fromId: 'e_wai_grandfather', termId: 't_father', toId: 'e_great_wai_grandfather'),
  RelationRule(id: 'r_wai_grandmother_mother', fromId: 'e_wai_grandmother', termId: 't_mother', toId: 'e_great_wai_grandmother'),
];

/// 平辈互链（哥哥/弟弟/姐姐/妹妹 回看父母 → 平辈的「爸爸」「妈妈」）。
final List<RelationRule> kKinshipRulesSibling = [
  RelationRule(id: 'r_eb_father', fromId: 'e_elder_brother', termId: 't_father', toId: 'e_father'),
  RelationRule(id: 'r_eb_mother', fromId: 'e_elder_brother', termId: 't_mother', toId: 'e_mother'),
  RelationRule(id: 'r_yb_father', fromId: 'e_younger_brother', termId: 't_father', toId: 'e_father'),
  RelationRule(id: 'r_yb_mother', fromId: 'e_younger_brother', termId: 't_mother', toId: 'e_mother'),
  RelationRule(id: 'r_es_father', fromId: 'e_elder_sister', termId: 't_father', toId: 'e_father'),
  RelationRule(id: 'r_es_mother', fromId: 'e_elder_sister', termId: 't_mother', toId: 'e_mother'),
  RelationRule(id: 'r_ys_father', fromId: 'e_younger_sister', termId: 't_father', toId: 'e_father'),
  RelationRule(id: 'r_ys_mother', fromId: 'e_younger_sister', termId: 't_mother', toId: 'e_mother'),
];

/// 平辈 → 晚辈。
final List<RelationRule> kKinshipRulesSiblingDown = [
  RelationRule(id: 'r_eb_son', fromId: 'e_elder_brother', termId: 't_son', toId: 'e_nephew_br'),
  RelationRule(id: 'r_eb_daughter', fromId: 'e_elder_brother', termId: 't_daughter', toId: 'e_niece_br'),
  RelationRule(id: 'r_yb_son', fromId: 'e_younger_brother', termId: 't_son', toId: 'e_nephew_br'),
  RelationRule(id: 'r_yb_daughter', fromId: 'e_younger_brother', termId: 't_daughter', toId: 'e_niece_br'),
  RelationRule(id: 'r_es_son', fromId: 'e_elder_sister', termId: 't_son', toId: 'e_nephew_sis'),
  RelationRule(id: 'r_es_daughter', fromId: 'e_elder_sister', termId: 't_daughter', toId: 'e_niece_sis'),
  RelationRule(id: 'r_ys_son', fromId: 'e_younger_sister', termId: 't_son', toId: 'e_nephew_sis'),
  RelationRule(id: 'r_ys_daughter', fromId: 'e_younger_sister', termId: 't_daughter', toId: 'e_niece_sis'),
];

/// 晚辈链。
final List<RelationRule> kKinshipRulesDown = [
  RelationRule(id: 'r_son_son', fromId: 'e_son', termId: 't_son', toId: 'e_grandson'),
  RelationRule(id: 'r_son_daughter', fromId: 'e_son', termId: 't_daughter', toId: 'e_granddaughter'),
  RelationRule(id: 'r_daughter_son', fromId: 'e_daughter', termId: 't_son', toId: 'e_wai_grandson'),
  RelationRule(id: 'r_daughter_daughter', fromId: 'e_daughter', termId: 't_daughter', toId: 'e_wai_granddaughter'),
  RelationRule(id: 'r_grandson_son', fromId: 'e_grandson', termId: 't_son', toId: 'e_great_grandson'),
  RelationRule(id: 'r_granddaughter_daughter', fromId: 'e_granddaughter', termId: 't_daughter', toId: 'e_great_granddaughter'),
];

/// 姻亲。
final List<RelationRule> kKinshipRulesInLaw = [
  RelationRule(id: 'r_husband_father', fromId: 'e_husband', termId: 't_father', toId: 'e_father_in_law'),
  RelationRule(id: 'r_husband_mother', fromId: 'e_husband', termId: 't_mother', toId: 'e_mother_in_law'),
  RelationRule(id: 'r_wife_father', fromId: 'e_wife', termId: 't_father', toId: 'e_father_in_law_wife'),
  RelationRule(id: 'r_wife_mother', fromId: 'e_wife', termId: 't_mother', toId: 'e_mother_in_law_wife'),
  RelationRule(id: 'r_eb_wife', fromId: 'e_elder_brother', termId: 't_wife', toId: 'e_sister_in_law_old'),
  RelationRule(id: 'r_yb_wife', fromId: 'e_younger_brother', termId: 't_wife', toId: 'e_sister_in_law_young'),
  RelationRule(id: 'r_es_husband', fromId: 'e_elder_sister', termId: 't_husband', toId: 'e_brother_in_law_sis'),
  RelationRule(id: 'r_ys_husband', fromId: 'e_younger_sister', termId: 't_husband', toId: 'e_brother_in_law_young'),
  RelationRule(id: 'r_son_wife', fromId: 'e_son', termId: 't_wife', toId: 'e_daughter_in_law'),
  RelationRule(id: 'r_daughter_husband', fromId: 'e_daughter', termId: 't_husband', toId: 'e_son_in_law'),
];

/// 旁系长辈 → 堂/表亲。
final List<RelationRule> kKinshipRulesCousin = [
  RelationRule(id: 'r_uncle_old_son', fromId: 'e_uncle_old', termId: 't_son', toId: 'e_cousin_tang_old'),
  RelationRule(id: 'r_uncle_old_daughter', fromId: 'e_uncle_old', termId: 't_daughter', toId: 'e_cousin_tang_sis_old'),
  RelationRule(id: 'r_uncle_young_son', fromId: 'e_uncle_young', termId: 't_son', toId: 'e_cousin_tang_young'),
  RelationRule(id: 'r_uncle_young_daughter', fromId: 'e_uncle_young', termId: 't_daughter', toId: 'e_cousin_tang_sis_young'),
  RelationRule(id: 'r_aunt_paternal_son', fromId: 'e_aunt_paternal', termId: 't_son', toId: 'e_cousin_biao_old'),
  RelationRule(id: 'r_aunt_paternal_daughter', fromId: 'e_aunt_paternal', termId: 't_daughter', toId: 'e_cousin_biao_sis_old'),
  RelationRule(id: 'r_uncle_maternal_son', fromId: 'e_uncle_maternal', termId: 't_son', toId: 'e_cousin_biao_old'),
  RelationRule(id: 'r_uncle_maternal_daughter', fromId: 'e_uncle_maternal', termId: 't_daughter', toId: 'e_cousin_biao_sis_old'),
  RelationRule(id: 'r_aunt_maternal_son', fromId: 'e_aunt_maternal_old', termId: 't_son', toId: 'e_cousin_biao_young'),
  RelationRule(id: 'r_aunt_maternal_daughter', fromId: 'e_aunt_maternal_old', termId: 't_daughter', toId: 'e_cousin_biao_sis_young'),
];

/// 长辈回看（伯父的爸爸 = 爷爷；舅舅的妈妈 = 外婆）等反向回推。
final List<RelationRule> kKinshipRulesElderBack = [
  RelationRule(id: 'r_uncle_old_father', fromId: 'e_uncle_old', termId: 't_father', toId: 'e_grandfather'),
  RelationRule(id: 'r_uncle_young_father', fromId: 'e_uncle_young', termId: 't_father', toId: 'e_grandfather'),
  RelationRule(id: 'r_aunt_paternal_father', fromId: 'e_aunt_paternal', termId: 't_father', toId: 'e_grandfather'),
  RelationRule(id: 'r_uncle_maternal_mother', fromId: 'e_uncle_maternal', termId: 't_mother', toId: 'e_wai_grandmother'),
  RelationRule(id: 'r_aunt_maternal_mother', fromId: 'e_aunt_maternal_old', termId: 't_mother', toId: 'e_wai_grandmother'),
];

/// 内置亲戚关系预设。
RelationGraphData kinshipPresetData() => RelationGraphData(
      entities: kKinshipEntities,
      terms: kKinshipTerms,
      rules: [
        ...kKinshipRulesFromMe,
        ...kKinshipRulesFather,
        ...kKinshipRulesMother,
        ...kKinshipRulesSibling,
        ...kKinshipRulesSiblingDown,
        ...kKinshipRulesDown,
        ...kKinshipRulesInLaw,
        ...kKinshipRulesCousin,
        ...kKinshipRulesElderBack,
      ],
    );

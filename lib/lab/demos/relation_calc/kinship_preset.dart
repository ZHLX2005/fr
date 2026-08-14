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
  // 祖父辈旁系（伯/叔/姑/舅/姨 公婆辈；同名不同源拆多个 id，note 区分）
  RelationEntity(id: 'e_bo_gong', name: '伯公', note: '爷爷的哥哥'),
  RelationEntity(id: 'e_shu_gong', name: '叔公', note: '爷爷的弟弟'),
  RelationEntity(id: 'e_gu_po_pat', name: '姑婆', note: '爷爷的姐妹'),
  RelationEntity(id: 'e_jiu_gong_pat', name: '舅公', note: '奶奶的兄弟'),
  RelationEntity(id: 'e_yi_po_pat', name: '姨婆', note: '奶奶的姐妹'),
  RelationEntity(id: 'e_jiu_gong_mat_u', name: '舅公', note: '外公的兄弟'),
  RelationEntity(id: 'e_gu_po_mat', name: '姑婆', note: '外公的姐妹'),
  RelationEntity(id: 'e_jiu_gong_mat_a', name: '舅公', note: '外婆的兄弟'),
  RelationEntity(id: 'e_yi_po_mat', name: '姨婆', note: '外婆的姐妹'),
  // 父母辈堂表（爸爸/妈妈的堂表兄弟姐妹）
  RelationEntity(id: 'e_tang_bo', name: '堂伯', note: '爸爸的堂兄'),
  RelationEntity(id: 'e_tang_shu', name: '堂叔', note: '爸爸的堂弟'),
  RelationEntity(id: 'e_tang_gu', name: '堂姑', note: '爸爸的堂姐妹'),
  RelationEntity(id: 'e_biao_shu', name: '表叔', note: '爸爸的表兄弟'),
  RelationEntity(id: 'e_biao_gu', name: '表姑', note: '爸爸的表姐妹'),
  RelationEntity(id: 'e_tang_jiu', name: '堂舅', note: '妈妈的堂兄弟'),
  RelationEntity(id: 'e_tang_yi', name: '堂姨', note: '妈妈的堂姐妹'),
  RelationEntity(id: 'e_biao_jiu', name: '表舅', note: '妈妈的表兄弟'),
  RelationEntity(id: 'e_biao_yi', name: '表姨', note: '妈妈的表姐妹'),
  // 同辈的堂/表侄辈
  RelationEntity(id: 'e_tang_zhi', name: '堂侄', note: '堂兄弟的儿子'),
  RelationEntity(id: 'e_tang_zhi_nv', name: '堂侄女', note: '堂兄弟的女儿'),
  RelationEntity(id: 'e_biao_zhi', name: '表侄', note: '表兄弟的儿子'),
  RelationEntity(id: 'e_biao_zhi_nv', name: '表侄女', note: '表兄弟的女儿'),
  // 配偶方兄弟姊妹（姻亲）
  RelationEntity(id: 'e_aunt_wife_old', name: '姨姐', note: '妻子的姐姐（大姨子）'),
  RelationEntity(id: 'e_aunt_wife_young', name: '姨妹', note: '妻子的妹妹（小姨子）'),
  RelationEntity(id: 'e_brother_wife_old', name: '大舅子', note: '妻子的哥哥（内兄）'),
  RelationEntity(id: 'e_brother_wife_young', name: '小舅子', note: '妻子的弟弟（内弟）'),
  RelationEntity(id: 'e_brother_hus_old', name: '大伯子', note: '丈夫的哥哥'),
  RelationEntity(id: 'e_brother_hus_young', name: '小叔子', note: '丈夫的弟弟'),
  RelationEntity(id: 'e_sister_hus_old', name: '大姑子', note: '丈夫的姐姐'),
  RelationEntity(id: 'e_sister_hus_young', name: '小姑子', note: '丈夫的妹妹'),
  // 二级姻亲
  RelationEntity(id: 'e_lianjin', name: '连襟', note: '妻子的姐妹的丈夫'),
  RelationEntity(id: 'e_zhouli', name: '妯娌', note: '丈夫的兄弟的妻子'),
  RelationEntity(id: 'e_nei_zhi', name: '内侄', note: '妻子的兄弟的儿子'),
  RelationEntity(id: 'e_nei_zhi_nv', name: '内侄女', note: '妻子的兄弟的女儿'),
  // 堂/表亲的配偶
  RelationEntity(id: 'e_tang_sao', name: '堂嫂', note: '堂哥的妻子'),
  RelationEntity(id: 'e_tang_di_xi', name: '堂弟媳', note: '堂弟的妻子'),
  RelationEntity(id: 'e_tang_jie_fu', name: '堂姐夫', note: '堂姐的丈夫'),
  RelationEntity(id: 'e_tang_mei_fu', name: '堂妹夫', note: '堂妹的丈夫'),
  RelationEntity(id: 'e_biao_sao', name: '表嫂', note: '表哥的妻子'),
  RelationEntity(id: 'e_biao_di_xi', name: '表弟媳', note: '表弟的妻子'),
  RelationEntity(id: 'e_biao_jie_fu', name: '表姐夫', note: '表姐的丈夫'),
  RelationEntity(id: 'e_biao_mei_fu', name: '表妹夫', note: '表妹的丈夫'),
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

/// 配偶方兄弟姊妹（妻子的姐姐=姨姐、丈夫的哥哥=大伯子…）。
final List<RelationRule> kKinshipRulesSpouseSibling = [
  // 妻子的兄弟姊妹
  RelationRule(id: 'r_wife_es', fromId: 'e_wife', termId: 't_elder_sister', toId: 'e_aunt_wife_old'),
  RelationRule(id: 'r_wife_ys', fromId: 'e_wife', termId: 't_younger_sister', toId: 'e_aunt_wife_young'),
  RelationRule(id: 'r_wife_eb', fromId: 'e_wife', termId: 't_elder_brother', toId: 'e_brother_wife_old'),
  RelationRule(id: 'r_wife_yb', fromId: 'e_wife', termId: 't_younger_brother', toId: 'e_brother_wife_young'),
  // 丈夫的兄弟姊妹
  RelationRule(id: 'r_husband_eb', fromId: 'e_husband', termId: 't_elder_brother', toId: 'e_brother_hus_old'),
  RelationRule(id: 'r_husband_yb', fromId: 'e_husband', termId: 't_younger_brother', toId: 'e_brother_hus_young'),
  RelationRule(id: 'r_husband_es', fromId: 'e_husband', termId: 't_elder_sister', toId: 'e_sister_hus_old'),
  RelationRule(id: 'r_husband_ys', fromId: 'e_husband', termId: 't_younger_sister', toId: 'e_sister_hus_young'),
];

/// 二级姻亲（连襟/妯娌/内侄 + 配偶方兄弟姊妹的子女）。
final List<RelationRule> kKinshipRulesInLawSecond = [
  // 连襟：妻子的姐妹的丈夫
  RelationRule(id: 'r_aunt_wife_old_husband', fromId: 'e_aunt_wife_old', termId: 't_husband', toId: 'e_lianjin'),
  RelationRule(id: 'r_aunt_wife_young_husband', fromId: 'e_aunt_wife_young', termId: 't_husband', toId: 'e_lianjin'),
  // 妯娌：丈夫的兄弟的妻子
  RelationRule(id: 'r_brother_hus_old_wife', fromId: 'e_brother_hus_old', termId: 't_wife', toId: 'e_zhouli'),
  RelationRule(id: 'r_brother_hus_young_wife', fromId: 'e_brother_hus_young', termId: 't_wife', toId: 'e_zhouli'),
  // 内侄：妻子的兄弟的儿子
  RelationRule(id: 'r_brother_wife_old_son', fromId: 'e_brother_wife_old', termId: 't_son', toId: 'e_nei_zhi'),
  RelationRule(id: 'r_brother_wife_old_daughter', fromId: 'e_brother_wife_old', termId: 't_daughter', toId: 'e_nei_zhi_nv'),
  RelationRule(id: 'r_brother_wife_young_son', fromId: 'e_brother_wife_young', termId: 't_son', toId: 'e_nei_zhi'),
  RelationRule(id: 'r_brother_wife_young_daughter', fromId: 'e_brother_wife_young', termId: 't_daughter', toId: 'e_nei_zhi_nv'),
  // 妻子的姐妹的子女 = 外甥/外甥女
  RelationRule(id: 'r_aunt_wife_old_son', fromId: 'e_aunt_wife_old', termId: 't_son', toId: 'e_nephew_sis'),
  RelationRule(id: 'r_aunt_wife_old_daughter', fromId: 'e_aunt_wife_old', termId: 't_daughter', toId: 'e_niece_sis'),
  RelationRule(id: 'r_aunt_wife_young_son', fromId: 'e_aunt_wife_young', termId: 't_son', toId: 'e_nephew_sis'),
  RelationRule(id: 'r_aunt_wife_young_daughter', fromId: 'e_aunt_wife_young', termId: 't_daughter', toId: 'e_niece_sis'),
  // 丈夫的姐妹的子女 = 外甥/外甥女
  RelationRule(id: 'r_sister_hus_old_son', fromId: 'e_sister_hus_old', termId: 't_son', toId: 'e_nephew_sis'),
  RelationRule(id: 'r_sister_hus_old_daughter', fromId: 'e_sister_hus_old', termId: 't_daughter', toId: 'e_niece_sis'),
  RelationRule(id: 'r_sister_hus_young_son', fromId: 'e_sister_hus_young', termId: 't_son', toId: 'e_nephew_sis'),
  RelationRule(id: 'r_sister_hus_young_daughter', fromId: 'e_sister_hus_young', termId: 't_daughter', toId: 'e_niece_sis'),
  // 丈夫的兄弟的子女 = 侄子/侄女
  RelationRule(id: 'r_brother_hus_old_son', fromId: 'e_brother_hus_old', termId: 't_son', toId: 'e_nephew_br'),
  RelationRule(id: 'r_brother_hus_old_daughter', fromId: 'e_brother_hus_old', termId: 't_daughter', toId: 'e_niece_br'),
  RelationRule(id: 'r_brother_hus_young_son', fromId: 'e_brother_hus_young', termId: 't_son', toId: 'e_nephew_br'),
  RelationRule(id: 'r_brother_hus_young_daughter', fromId: 'e_brother_hus_young', termId: 't_daughter', toId: 'e_niece_br'),
];

/// 堂/表亲的配偶。
final List<RelationRule> kKinshipRulesTangBiaoSpouse = [
  RelationRule(id: 'r_tang_ge_wife', fromId: 'e_cousin_tang_old', termId: 't_wife', toId: 'e_tang_sao'),
  RelationRule(id: 'r_tang_di_wife', fromId: 'e_cousin_tang_young', termId: 't_wife', toId: 'e_tang_di_xi'),
  RelationRule(id: 'r_tang_jie_husband', fromId: 'e_cousin_tang_sis_old', termId: 't_husband', toId: 'e_tang_jie_fu'),
  RelationRule(id: 'r_tang_mei_husband', fromId: 'e_cousin_tang_sis_young', termId: 't_husband', toId: 'e_tang_mei_fu'),
  RelationRule(id: 'r_biao_ge_wife', fromId: 'e_cousin_biao_old', termId: 't_wife', toId: 'e_biao_sao'),
  RelationRule(id: 'r_biao_di_wife', fromId: 'e_cousin_biao_young', termId: 't_wife', toId: 'e_biao_di_xi'),
  RelationRule(id: 'r_biao_jie_husband', fromId: 'e_cousin_biao_sis_old', termId: 't_husband', toId: 'e_biao_jie_fu'),
  RelationRule(id: 'r_biao_mei_husband', fromId: 'e_cousin_biao_sis_young', termId: 't_husband', toId: 'e_biao_mei_fu'),
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

/// 祖父辈旁系：爷爷/奶奶/外公/外婆 的兄弟姊妹。
/// 同名不同源拆多个 id：舅公(奶奶系) 儿子=表叔，舅公(外公系) 儿子=堂舅，
/// 舅公(外婆系) 儿子=表舅 —— 图模型一条边只能一个终点，必须拆实体。
final List<RelationRule> kKinshipRulesGrandSibling = [
  // 爷爷的兄弟姊妹
  RelationRule(id: 'r_gf_eb', fromId: 'e_grandfather', termId: 't_elder_brother', toId: 'e_bo_gong'),
  RelationRule(id: 'r_gf_yb', fromId: 'e_grandfather', termId: 't_younger_brother', toId: 'e_shu_gong'),
  RelationRule(id: 'r_gf_es', fromId: 'e_grandfather', termId: 't_elder_sister', toId: 'e_gu_po_pat'),
  RelationRule(id: 'r_gf_ys', fromId: 'e_grandfather', termId: 't_younger_sister', toId: 'e_gu_po_pat'),
  // 奶奶的兄弟姊妹
  RelationRule(id: 'r_gm_eb', fromId: 'e_grandmother', termId: 't_elder_brother', toId: 'e_jiu_gong_pat'),
  RelationRule(id: 'r_gm_yb', fromId: 'e_grandmother', termId: 't_younger_brother', toId: 'e_jiu_gong_pat'),
  RelationRule(id: 'r_gm_es', fromId: 'e_grandmother', termId: 't_elder_sister', toId: 'e_yi_po_pat'),
  RelationRule(id: 'r_gm_ys', fromId: 'e_grandmother', termId: 't_younger_sister', toId: 'e_yi_po_pat'),
  // 外公的兄弟姊妹
  RelationRule(id: 'r_wgf_eb', fromId: 'e_wai_grandfather', termId: 't_elder_brother', toId: 'e_jiu_gong_mat_u'),
  RelationRule(id: 'r_wgf_yb', fromId: 'e_wai_grandfather', termId: 't_younger_brother', toId: 'e_jiu_gong_mat_u'),
  RelationRule(id: 'r_wgf_es', fromId: 'e_wai_grandfather', termId: 't_elder_sister', toId: 'e_gu_po_mat'),
  RelationRule(id: 'r_wgf_ys', fromId: 'e_wai_grandfather', termId: 't_younger_sister', toId: 'e_gu_po_mat'),
  // 外婆的兄弟姊妹
  RelationRule(id: 'r_wgm_eb', fromId: 'e_wai_grandmother', termId: 't_elder_brother', toId: 'e_jiu_gong_mat_a'),
  RelationRule(id: 'r_wgm_yb', fromId: 'e_wai_grandmother', termId: 't_younger_brother', toId: 'e_jiu_gong_mat_a'),
  RelationRule(id: 'r_wgm_es', fromId: 'e_wai_grandmother', termId: 't_elder_sister', toId: 'e_yi_po_mat'),
  RelationRule(id: 'r_wgm_ys', fromId: 'e_wai_grandmother', termId: 't_younger_sister', toId: 'e_yi_po_mat'),
];

/// 祖父辈旁系 → 父母辈堂表（伯公的儿子=堂伯、舅公(外公系)的儿子=堂舅…）。
final List<RelationRule> kKinshipRulesGrandSiblingDown = [
  // 伯公/叔公/姑婆(爷爷系) 的子女 → 爸爸的堂/表兄弟姊妹
  RelationRule(id: 'r_bo_gong_son', fromId: 'e_bo_gong', termId: 't_son', toId: 'e_tang_bo'),
  RelationRule(id: 'r_bo_gong_daughter', fromId: 'e_bo_gong', termId: 't_daughter', toId: 'e_tang_gu'),
  RelationRule(id: 'r_shu_gong_son', fromId: 'e_shu_gong', termId: 't_son', toId: 'e_tang_shu'),
  RelationRule(id: 'r_shu_gong_daughter', fromId: 'e_shu_gong', termId: 't_daughter', toId: 'e_tang_gu'),
  RelationRule(id: 'r_gu_po_pat_son', fromId: 'e_gu_po_pat', termId: 't_son', toId: 'e_biao_shu'),
  RelationRule(id: 'r_gu_po_pat_daughter', fromId: 'e_gu_po_pat', termId: 't_daughter', toId: 'e_biao_gu'),
  // 舅公/姨婆(奶奶系) 的子女 → 爸爸的表兄弟姊妹
  RelationRule(id: 'r_jiu_gong_pat_son', fromId: 'e_jiu_gong_pat', termId: 't_son', toId: 'e_biao_shu'),
  RelationRule(id: 'r_jiu_gong_pat_daughter', fromId: 'e_jiu_gong_pat', termId: 't_daughter', toId: 'e_biao_gu'),
  RelationRule(id: 'r_yi_po_pat_son', fromId: 'e_yi_po_pat', termId: 't_son', toId: 'e_biao_shu'),
  RelationRule(id: 'r_yi_po_pat_daughter', fromId: 'e_yi_po_pat', termId: 't_daughter', toId: 'e_biao_gu'),
  // 舅公(外公系) 的子女 → 妈妈的堂兄弟姊妹
  RelationRule(id: 'r_jiu_gong_mat_u_son', fromId: 'e_jiu_gong_mat_u', termId: 't_son', toId: 'e_tang_jiu'),
  RelationRule(id: 'r_jiu_gong_mat_u_daughter', fromId: 'e_jiu_gong_mat_u', termId: 't_daughter', toId: 'e_tang_yi'),
  // 姑婆(外公系) 的子女 → 妈妈的表兄弟姊妹
  RelationRule(id: 'r_gu_po_mat_son', fromId: 'e_gu_po_mat', termId: 't_son', toId: 'e_biao_jiu'),
  RelationRule(id: 'r_gu_po_mat_daughter', fromId: 'e_gu_po_mat', termId: 't_daughter', toId: 'e_biao_yi'),
  // 舅公/姨婆(外婆系) 的子女 → 妈妈的表兄弟姊妹
  RelationRule(id: 'r_jiu_gong_mat_a_son', fromId: 'e_jiu_gong_mat_a', termId: 't_son', toId: 'e_biao_jiu'),
  RelationRule(id: 'r_jiu_gong_mat_a_daughter', fromId: 'e_jiu_gong_mat_a', termId: 't_daughter', toId: 'e_biao_yi'),
  RelationRule(id: 'r_yi_po_mat_son', fromId: 'e_yi_po_mat', termId: 't_son', toId: 'e_biao_jiu'),
  RelationRule(id: 'r_yi_po_mat_daughter', fromId: 'e_yi_po_mat', termId: 't_daughter', toId: 'e_biao_yi'),
];

/// 父母辈堂表 → 同辈（堂伯的儿子=堂哥、堂舅的女儿=表姐…）。
final List<RelationRule> kKinshipRulesTangBiaoDown = [
  // 爸爸的堂兄弟姊妹 → 堂亲同辈
  RelationRule(id: 'r_tang_bo_son', fromId: 'e_tang_bo', termId: 't_son', toId: 'e_cousin_tang_old'),
  RelationRule(id: 'r_tang_bo_daughter', fromId: 'e_tang_bo', termId: 't_daughter', toId: 'e_cousin_tang_sis_old'),
  RelationRule(id: 'r_tang_shu_son', fromId: 'e_tang_shu', termId: 't_son', toId: 'e_cousin_tang_young'),
  RelationRule(id: 'r_tang_shu_daughter', fromId: 'e_tang_shu', termId: 't_daughter', toId: 'e_cousin_tang_sis_young'),
  RelationRule(id: 'r_tang_gu_son', fromId: 'e_tang_gu', termId: 't_son', toId: 'e_cousin_biao_old'),
  RelationRule(id: 'r_tang_gu_daughter', fromId: 'e_tang_gu', termId: 't_daughter', toId: 'e_cousin_biao_sis_old'),
  // 爸爸的表兄弟姊妹 → 表亲同辈
  RelationRule(id: 'r_biao_shu_son', fromId: 'e_biao_shu', termId: 't_son', toId: 'e_cousin_biao_old'),
  RelationRule(id: 'r_biao_shu_daughter', fromId: 'e_biao_shu', termId: 't_daughter', toId: 'e_cousin_biao_sis_old'),
  RelationRule(id: 'r_biao_gu_son', fromId: 'e_biao_gu', termId: 't_son', toId: 'e_cousin_biao_young'),
  RelationRule(id: 'r_biao_gu_daughter', fromId: 'e_biao_gu', termId: 't_daughter', toId: 'e_cousin_biao_sis_young'),
  // 妈妈的堂兄弟姊妹 → 表亲同辈
  RelationRule(id: 'r_tang_jiu_son', fromId: 'e_tang_jiu', termId: 't_son', toId: 'e_cousin_biao_old'),
  RelationRule(id: 'r_tang_jiu_daughter', fromId: 'e_tang_jiu', termId: 't_daughter', toId: 'e_cousin_biao_sis_old'),
  RelationRule(id: 'r_tang_yi_son', fromId: 'e_tang_yi', termId: 't_son', toId: 'e_cousin_biao_young'),
  RelationRule(id: 'r_tang_yi_daughter', fromId: 'e_tang_yi', termId: 't_daughter', toId: 'e_cousin_biao_sis_young'),
  // 妈妈的表兄弟姊妹 → 表亲同辈
  RelationRule(id: 'r_biao_jiu_son', fromId: 'e_biao_jiu', termId: 't_son', toId: 'e_cousin_biao_young'),
  RelationRule(id: 'r_biao_jiu_daughter', fromId: 'e_biao_jiu', termId: 't_daughter', toId: 'e_cousin_biao_sis_young'),
  RelationRule(id: 'r_biao_yi_son', fromId: 'e_biao_yi', termId: 't_son', toId: 'e_cousin_biao_young'),
  RelationRule(id: 'r_biao_yi_daughter', fromId: 'e_biao_yi', termId: 't_daughter', toId: 'e_cousin_biao_sis_young'),
];

/// 同辈 → 堂/表侄辈（堂哥的儿子=堂侄、表哥的女儿=表侄女…）。
final List<RelationRule> kKinshipRulesTangBiaoNephew = [
  RelationRule(id: 'r_tang_ge_son', fromId: 'e_cousin_tang_old', termId: 't_son', toId: 'e_tang_zhi'),
  RelationRule(id: 'r_tang_ge_daughter', fromId: 'e_cousin_tang_old', termId: 't_daughter', toId: 'e_tang_zhi_nv'),
  RelationRule(id: 'r_tang_di_son', fromId: 'e_cousin_tang_young', termId: 't_son', toId: 'e_tang_zhi'),
  RelationRule(id: 'r_tang_di_daughter', fromId: 'e_cousin_tang_young', termId: 't_daughter', toId: 'e_tang_zhi_nv'),
  RelationRule(id: 'r_biao_ge_son', fromId: 'e_cousin_biao_old', termId: 't_son', toId: 'e_biao_zhi'),
  RelationRule(id: 'r_biao_ge_daughter', fromId: 'e_cousin_biao_old', termId: 't_daughter', toId: 'e_biao_zhi_nv'),
  RelationRule(id: 'r_biao_di_son', fromId: 'e_cousin_biao_young', termId: 't_son', toId: 'e_biao_zhi'),
  RelationRule(id: 'r_biao_di_daughter', fromId: 'e_cousin_biao_young', termId: 't_daughter', toId: 'e_biao_zhi_nv'),
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
        ...kKinshipRulesSpouseSibling,
        ...kKinshipRulesInLawSecond,
        ...kKinshipRulesCousin,
        ...kKinshipRulesTangBiaoSpouse,
        ...kKinshipRulesElderBack,
        ...kKinshipRulesGrandSibling,
        ...kKinshipRulesGrandSiblingDown,
        ...kKinshipRulesTangBiaoDown,
        ...kKinshipRulesTangBiaoNephew,
      ],
    );

class MockDataService {
  static List<String> getAIChatQuickPrompts() {
    return [
      '帮我写一段自我介绍',
      '如何学习 Flutter？',
      '解释什么是闭包',
      '推荐几个学习资源',
    ];
  }

  static List<String> getAgentQuickPrompts() {
    return [
      '完成了10次深呼吸',
      '跑步5公里，用时30分钟',
      '做了30个深蹲',
      '阅读了1小时',
    ];
  }
}

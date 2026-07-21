// lib/lab/demos/team_card_demo.dart
//
// 团建卡牌 Demo — 自定义角色池 + master 参与/旁观 + 发牌
//
// 方案 A：主入口，具体视图拆分到 lab/demos/team_card/*.dart

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'team_card/team_card_master.dart';
import 'team_card/team_card_player.dart';

class TeamCardDemo extends DemoPage {
  @override
  String get title => '团建卡牌';
  @override
  String get slug => 'team-card';
  @override
  String get description => '谁是卧底/狼人杀 自定义身份分配';
  @override
  bool get preferFullScreen => true;
  @override
  Widget buildPage(BuildContext context) => const TeamCardDemoPage();
}

class TeamCardDemoPage extends StatefulWidget {
  const TeamCardDemoPage({super.key});
  @override
  State<TeamCardDemoPage> createState() => _TeamCardDemoPageState();
}

class _TeamCardDemoPageState extends State<TeamCardDemoPage> {
  bool _isMaster = true;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('团建卡牌')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('我是房主')),
                ButtonSegment(value: false, label: Text('我是玩家')),
              ],
              selected: {_isMaster},
              onSelectionChanged: (s) => setState(() => _isMaster = s.first),
            ),
          ),
          Expanded(child: _isMaster ? const MasterView() : const PlayerView()),
        ],
      ),
    );
  }
}

void registerTeamCardDemo() {
  demoRegistry.register(TeamCardDemo());
}

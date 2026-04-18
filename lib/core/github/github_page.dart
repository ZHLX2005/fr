import 'package:flutter/material.dart';

import 'github_actions_page.dart';
import 'github_actions_service.dart';
import 'github_issues_page.dart';
import 'github_issues_service.dart';

class GithubPage extends StatelessWidget {
  final String issuesOwner;
  final String issuesRepo;
  final String actionsOwner;
  final String actionsRepo;
  final String token;

  const GithubPage({
    super.key,
    required this.issuesOwner,
    required this.issuesRepo,
    required this.actionsOwner,
    required this.actionsRepo,
    required this.token,
  });

  @override
  Widget build(BuildContext context) {
    final issuesService = GithubIssuesService(
      owner: issuesOwner,
      repo: issuesRepo,
      token: token,
    );
    final actionsService = GithubActionsService(
      owner: actionsOwner,
      repo: actionsRepo,
      token: token,
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GitHub'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Issues'),
              Tab(text: 'Actions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            GithubIssuesTab(service: issuesService),
            GithubActionsTab(
              service: actionsService,
              repoLabel: '$actionsOwner/$actionsRepo',
            ),
          ],
        ),
      ),
    );
  }
}

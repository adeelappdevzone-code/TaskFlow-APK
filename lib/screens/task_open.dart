import 'package:flutter/material.dart';

import '../data/task_repository.dart';
import 'task_detail_screen.dart';
import 'team_task_detail_screen.dart';

/// Opens any of my tasks (personal or team) in the side panel or as a page.
void openTaskRef(BuildContext context, TaskRef ref) {
  final team = ref.team;
  if (team == null) {
    openTaskDetail(context, ref.task);
  } else {
    openTeamTask(context, team, ref.task);
  }
}

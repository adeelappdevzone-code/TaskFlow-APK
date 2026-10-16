import 'package:flutter/material.dart';

import '../data/task_repository.dart';
import 'task_page.dart';

/// Opens any of my tasks (personal or team) in the side panel or as a page.
/// [comments]: team tasks open on the comments.
void openTaskRef(BuildContext context, TaskRef ref, {bool comments = false}) {
  final team = ref.team;
  if (team == null) {
    openTaskDetail(context, ref.task);
  } else {
    openTeamTask(context, team, ref.task, comments: comments);
  }
}

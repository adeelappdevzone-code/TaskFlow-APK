import 'package:flutter/material.dart';

import '../widgets/responsive.dart';
import 'task_detail_screen.dart';
import 'team_task_detail_screen.dart';

/// The side panel content for [DetailPanelHost] (wide screens).
Widget buildTaskPanel(BuildContext context, PanelTarget target, VoidCallback close) {
  final teamId = target.teamId;
  return teamId == null
      ? TaskDetailScreen(taskId: target.taskId, onClose: close)
      : TeamTaskDetailScreen(teamId: teamId, taskId: target.taskId, onClose: close);
}

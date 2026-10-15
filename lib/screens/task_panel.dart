import 'package:flutter/material.dart';

import '../widgets/responsive.dart';
import 'task_page.dart';

/// What [DetailPanelHost] shows on a laptop: the task page over the list.
Widget buildTaskPanel(BuildContext context, PanelTarget target, VoidCallback close) =>
    TaskPage(taskId: target.taskId, teamId: target.teamId, onClose: close);

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Width from which the app uses the laptop layout (side menu, panels).
const kWideLayout = 900.0;

bool isWideScreen(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideLayout;

/// Keeps content at a readable width in the middle of a wide screen
/// (does nothing on a phone).
class CenteredContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const CenteredContent({super.key, required this.child, this.maxWidth = 860});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// What the side panel shows: a personal task, or a team task (with [teamId]).
class PanelTarget {
  final String taskId;
  final String? teamId;
  const PanelTarget(this.taskId, {this.teamId});

  @override
  bool operator ==(Object other) =>
      other is PanelTarget && other.taskId == taskId && other.teamId == teamId;

  @override
  int get hashCode => Object.hash(taskId, teamId);
}

/// On a wide screen, shows tasks in a panel on the right instead of opening a
/// new page. Screens call [DetailPanelHost.of]; it returns null on phones (or
/// when there is no room), and they open a page as usual.
class DetailPanelHost extends StatefulWidget {
  final Widget child;

  /// Builds the panel for a target; [close] hides the panel.
  final Widget Function(BuildContext context, PanelTarget target, VoidCallback close) panelBuilder;

  const DetailPanelHost({super.key, required this.child, required this.panelBuilder});

  /// The nearest host that currently has room for a panel, or null.
  static DetailPanelHostState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PanelScope>()?.host;

  @override
  State<DetailPanelHost> createState() => DetailPanelHostState();
}

class DetailPanelHostState extends State<DetailPanelHost> {
  PanelTarget? _target;

  PanelTarget? get target => _target;

  void show(PanelTarget t) => setState(() => _target = t);

  void close() => setState(() => _target = null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      // Room for a list and a panel side by side.
      final wide = box.maxWidth >= kWideLayout;
      if (!wide) return _PanelScope(host: null, child: widget.child);
      final t = _target;
      final panelWidth = math.min(480.0, box.maxWidth * 0.42);
      return _PanelScope(
        host: this,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: widget.child),
            if (t != null) ...[
              const VerticalDivider(width: 1, color: AppColors.border),
              SizedBox(
                width: panelWidth,
                child: KeyedSubtree(
                  key: ValueKey(t),
                  child: widget.panelBuilder(context, t, close),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _PanelScope extends InheritedWidget {
  final DetailPanelHostState? host;
  const _PanelScope({required this.host, required super.child});

  @override
  bool updateShouldNotify(_PanelScope old) => old.host != host;
}

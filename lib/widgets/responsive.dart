import 'package:flutter/material.dart';

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

/// On a wide screen, shows a task over the page (inside the app frame)
/// instead of opening a new full-screen page. Screens call [DetailPanelHost.of]; it returns null on phones (or
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
      // Big screen: the task opens over the page (the side menu and top bar
      // stay); the page underneath keeps its state for "Back".
      final wide = box.maxWidth >= kWideLayout;
      if (!wide) return _PanelScope(host: null, child: widget.child);
      final t = _target;
      return _PanelScope(
        host: this,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
                offstage: t != null, child: TickerMode(enabled: t == null, child: widget.child)),
            if (t != null)
              Positioned.fill(
                child: KeyedSubtree(
                  key: ValueKey(t),
                  child: widget.panelBuilder(context, t, close),
                ),
              ),
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

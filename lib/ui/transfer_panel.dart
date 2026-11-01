import "package:flutter/material.dart";

import "../planner.dart";

class TransferPanel extends StatefulWidget {
  const TransferPanel({
    super.key,
    required this.heading,
    required this.fileName,
    required this.done,
    required this.total,
    required this.paused,
    required this.onTogglePause,
    this.index = 0,
    this.count = 0,
  });

  final String heading;
  final String fileName;
  final int done;
  final int total;
  final bool paused;
  final VoidCallback onTogglePause;
  final int index;
  final int count;

  @override
  State<TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends State<TransferPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _move;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = widget.total <= 0 ? 0.0 : (widget.done / widget.total).clamp(0.0, 1.0);
    final percentLabel = widget.total <= 0 ? "..." : "${(percent * 100).toStringAsFixed(percent < 0.1 && percent > 0 ? 1 : 0)}%";
    final where = widget.count > 0 ? "Arquivo ${widget.index} de ${widget.count}" : widget.heading;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: AnimatedBuilder(
                animation: _move,
                builder: (context, _) {
                  final t = widget.paused ? 0.35 : _move.value;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.smartphone, color: scheme.primary, size: 34),
                      SizedBox(
                        width: 92,
                        height: 36,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.sync_alt, color: scheme.primary.withOpacity(0.28)),
                            Align(
                              alignment: Alignment(-1 + (t * 2), 0),
                              child: Icon(
                                Icons.arrow_forward,
                                color: widget.paused ? scheme.outline : scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.smartphone, color: scheme.tertiary, size: 34),
                    ],
                  );
                },
              ),
            ),
            Text(widget.paused ? "Transferência pausada" : widget.heading, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(where, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(widget.fileName.isEmpty ? "Preparando..." : widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(percentLabel, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: scheme.primary)),
            LinearProgressIndicator(value: widget.total <= 0 ? null : percent),
            const SizedBox(height: 6),
            Text("${formatBytes(widget.done)} de ${formatBytes(widget.total)}"),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.onTogglePause,
              icon: Icon(widget.paused ? Icons.play_arrow : Icons.pause),
              label: Text(widget.paused ? "Continuar" : "Pausar"),
            ),
          ],
        ),
      ),
    );
  }
}

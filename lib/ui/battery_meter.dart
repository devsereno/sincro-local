import "dart:async";
import "dart:math";

import "package:battery_plus/battery_plus.dart";
import "package:flutter/material.dart";

import "../planner.dart";

class BatteryMeter extends StatefulWidget {
  const BatteryMeter({super.key, required this.done, required this.total, this.otherNow});

  final int done;
  final int total;
  final int? otherNow;

  @override
  State<BatteryMeter> createState() => _BatteryMeterState();
}

class _BatteryMeterState extends State<BatteryMeter> {
  int _level = -1;
  Timer? _timer;
  DateTime? _started;
  int _mark = 0;
  int _levelAtStart = -1;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _read());
  }

  Future<void> _read() async {
    final level = await Battery().batteryLevel.catchError((_) => -1);
    if (!mounted || level < 0) return;
    setState(() {
      _level = level;
      _started ??= DateTime.now();
      if (_levelAtStart < 0) _levelAtStart = level;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = _level < 0 ? 0 : _level;
    final known = _level >= 0;
    final speed = _speed();
    final remain = max(0, widget.total - widget.done);
    final seconds = speed <= 0 ? 0.0 : remain / speed;
    final drain = _drainPerHour();
    final atEnd = known ? (level - seconds / 3600 * drain).round().clamp(0, 100) : 0;
    final needs = known && (level <= 20 || atEnd < 20);
    final other = widget.otherNow;
    final otherEnd = other == null ? null : (other - seconds / 3600 * drain).round().clamp(0, 100);
    final otherNeeds = other != null && otherEnd != null && (other <= 20 || otherEnd < 20);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Monitor de bateria", style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(known ? "Nível atual: $level%" : "Lendo a bateria..."),
            ),
            const SizedBox(height: 8),
            if (known) _Bar(now: level, end: atEnd),
            if (known)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Text("0%"),
                    Expanded(
                      child: Text(
                        "Estimativa ao terminar: $atEnd%",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Text("100%"),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              widget.total <= 0 ? "Calculando o tempo..." : "Cerca de ${formatEta(seconds)} neste ritmo.",
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (needs)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  "Recomenda-se conectar o carregador neste aparelho.",
                  style: TextStyle(color: Color(0xFFD4651A), fontWeight: FontWeight.w800),
                ),
              ),
            if (other != null && otherEnd != null) ...[
              const SizedBox(height: 8),
              Text("No outro aparelho: $other% agora, ao terminar cerca de $otherEnd%."),
              if (otherNeeds)
                const Text(
                  "Conecte o carregador no outro aparelho. A bateria de lá não chega ao fim.",
                  style: TextStyle(color: Color(0xFFD4651A), fontWeight: FontWeight.w800),
                ),
            ],
          ],
        ),
      ),
    );
  }

  double _speed() {
    final now = DateTime.now();
    if (_started == null || widget.done < _mark) {
      _started = now;
      _mark = widget.done;
      return typicalBytesPerSecond;
    }
    final seconds = now.difference(_started!).inMilliseconds / 1000;
    final gained = widget.done - _mark;
    if (seconds < 3 || gained <= 0) return typicalBytesPerSecond;
    return gained / seconds;
  }

  double _drainPerHour() {
    if (_started == null || _levelAtStart < 0 || _level < 0 || _level >= _levelAtStart) return 12;
    final hours = DateTime.now().difference(_started!).inMilliseconds / 3600000;
    if (hours < 0.02) return 12;
    return ((_levelAtStart - _level) / hours).clamp(4, 40);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.now, required this.end});

  final int now;
  final int end;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: LayoutBuilder(
        builder: (context, limits) {
          final width = limits.maxWidth;
          double x(int value) => (value.clamp(0, 100) / 100) * width;
          final left = min(x(end), x(now));
          final span = max(8.0, (x(now) - x(end)).abs());
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 14,
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                ),
              ),
              Positioned(
                left: left,
                top: 14,
                width: span,
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(color: const Color(0xFF3DDC84), borderRadius: BorderRadius.circular(20)),
                ),
              ),
              Positioned(left: (x(now) - 10).clamp(0, width - 20), top: 0, child: Icon(Icons.arrow_drop_down, color: scheme.onSurface)),
              Positioned(left: (x(end) - 10).clamp(0, width - 20), top: 22, child: Icon(Icons.arrow_drop_up, color: scheme.onSurfaceVariant)),
              Positioned(left: (x(now) - 18).clamp(0, width - 24), top: 10, child: Icon(Icons.battery_charging_full, size: 18, color: scheme.onSurface)),
            ],
          );
        },
      ),
    );
  }
}

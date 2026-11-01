enum Mode { hybrid, sd, internal }

enum Dest { sd, internal }

const int gb = 1024 * 1024 * 1024;
const int mb = 1024 * 1024;
const int fat32Limit = 4 * gb;

class Placement {
  Placement({
    required this.name,
    required this.bytes,
    required this.sourcePath,
    required this.dest,
    required this.reason,
  });

  final String name;
  final int bytes;
  final String sourcePath;
  final Dest? dest;
  final String reason;
}

String modeLabel(Mode mode) {
  switch (mode) {
    case Mode.hybrid:
      return "Híbrido";
    case Mode.sd:
      return "Só SD";
    case Mode.internal:
      return "Só interna";
  }
}

String modeHint(Mode mode) {
  switch (mode) {
    case Mode.hybrid:
      return "Enche o cartão até a reserva. O que não cabe vai para a interna.";
    case Mode.sd:
      return "Tudo no cartão. Se encher, pausa. Não cai na interna.";
    case Mode.internal:
      return "Tudo na interna, respeitando a reserva. O cartão não entra.";
  }
}

String formatBytes(int bytes) {
  String num(double n, int digits) => n.toStringAsFixed(digits).replaceAll(".", ",");
  if (bytes >= gb) {
    final value = bytes / gb;
    return "${num(value, value >= 10 ? 0 : 1)} GB";
  }
  if (bytes >= mb) return "${num(bytes / mb, bytes >= 10 * mb ? 0 : 1)} MB";
  if (bytes >= 1024) return "${(bytes / 1024).round()} KB";
  return "$bytes B";
}

String formatEta(double seconds) {
  if (!seconds.isFinite || seconds < 1) return "menos de 1 s";
  final total = seconds.ceil();
  final m = total ~/ 60;
  final s = total % 60;
  if (m <= 0) return "$s s";
  if (m < 60) return s == 0 ? "$m min" : "$m min $s s";
  final h = m ~/ 60;
  return "$h h ${m % 60} min";
}

const double typicalBytesPerSecond = 2 * 1024 * 1024;

class ChargeForecast {
  const ChargeForecast({required this.now, required this.atEnd, required this.seconds, required this.needsCharger});

  final int now;
  final int atEnd;
  final double seconds;
  final bool needsCharger;
}

ChargeForecast chargeForecast({required int level, required int bytes, double bytesPerSecond = typicalBytesPerSecond}) {
  final speed = bytesPerSecond <= 0 ? typicalBytesPerSecond : bytesPerSecond;
  final seconds = bytes <= 0 ? 0.0 : bytes / speed;
  final atEnd = (level - (seconds / 3600) * 12).round().clamp(0, 100);
  return ChargeForecast(
    now: level,
    atEnd: atEnd,
    seconds: seconds,
    needsCharger: level <= 20 || atEnd < 20,
  );
}

List<Placement> placeFiles({
  required List<({String name, int bytes, String path})> files,
  required Mode mode,
  required int internalFree,
  required int sdFree,
  required bool fat32,
  required double internalBufferGb,
  required int sdBufferMb,
}) {
  var sdRoom = (sdFree - sdBufferMb * mb).clamp(0, 1 << 62);
  var internalRoom = (internalFree - (internalBufferGb * gb).round()).clamp(0, 1 << 62);

  bool fits(Dest dest, int bytes) {
    if (dest == Dest.sd && fat32 && bytes > fat32Limit) return false;
    final room = dest == Dest.sd ? sdRoom : internalRoom;
    return bytes <= room;
  }

  void consume(Dest dest, int bytes) {
    if (dest == Dest.sd) {
      sdRoom -= bytes;
    } else {
      internalRoom -= bytes;
    }
  }

  return [
    for (final file in files)
      () {
        final order = switch (mode) {
          Mode.sd => const [Dest.sd],
          Mode.internal => const [Dest.internal],
          Mode.hybrid => const [Dest.sd, Dest.internal],
        };
        for (final dest in order) {
          if (!fits(dest, file.bytes)) continue;
          consume(dest, file.bytes);
          return Placement(
            name: file.name,
            bytes: file.bytes,
            sourcePath: file.path,
            dest: dest,
            reason: "ok",
          );
        }
        final reason = fat32 && file.bytes > fat32Limit && mode != Mode.internal ? "fat32" : "full";
        return Placement(
          name: file.name,
          bytes: file.bytes,
          sourcePath: file.path,
          dest: null,
          reason: reason,
        );
      }(),
  ];
}

String placementLabel(Placement item) {
  if (item.dest == Dest.sd) return "Cartão SD";
  if (item.dest == Dest.internal) return "Interna";
  if (item.reason == "fat32") return "FAT32 recusa acima de 4 GB";
  return "Não cabe na reserva";
}

import "dart:io";
import "dart:typed_data";

import "package:crypto/crypto.dart";

class CancelFlag {
  bool cancelled = false;
  bool paused = false;
}

class DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<String> copyHashed({
  required File source,
  required File dest,
  required CancelFlag cancel,
  required void Function(int written) onProgress,
}) async {
  final sink = DigestSink();
  final input = sha256.startChunkedConversion(sink);
  final out = dest.openWrite();
  var written = 0;
  try {
    await for (final chunk in source.openRead(64 * 1024)) {
      if (cancel.cancelled) break;
      input.add(chunk);
      out.add(chunk);
      written += chunk.length;
      onProgress(written);
    }
    await out.flush();
    await out.close();
    input.close();
    if (cancel.cancelled) {
      if (await dest.exists()) await dest.delete();
      throw StateError("cancelado");
    }
    return sink.value.toString();
  } catch (error) {
    try {
      await out.close();
    } catch (_) {}
    if (await dest.exists()) await dest.delete();
    rethrow;
  }
}

Future<String> writeHashed({
  required Stream<List<int>> source,
  required File dest,
  required int total,
  required CancelFlag cancel,
  required void Function(int written) onProgress,
}) async {
  final sink = DigestSink();
  final input = sha256.startChunkedConversion(sink);
  final out = dest.openWrite();
  var written = 0;
  try {
    await for (final chunk in source) {
      while (cancel.paused && !cancel.cancelled) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (cancel.cancelled) break;
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      input.add(bytes);
      out.add(bytes);
      written += bytes.length;
      onProgress(written);
    }
    await out.flush();
    await out.close();
    input.close();
    if (cancel.cancelled || written != total) {
      if (await dest.exists()) await dest.delete();
      throw StateError(cancel.cancelled ? "cancelado" : "arquivo incompleto");
    }
    return sink.value.toString();
  } catch (error) {
    try {
      await out.close();
    } catch (_) {}
    if (await dest.exists()) await dest.delete();
    rethrow;
  }
}

Future<File> uniqueFile(Directory dir, String name) async {
  await dir.create(recursive: true);
  final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
  var candidate = File("${dir.path}/$clean");
  if (!await candidate.exists()) return candidate;
  final dot = clean.lastIndexOf(".");
  final stem = dot > 0 ? clean.substring(0, dot) : clean;
  final ext = dot > 0 ? clean.substring(dot) : "";
  for (var i = 1; i < 1000; i++) {
    candidate = File("${dir.path}/$stem ($i)$ext");
    if (!await candidate.exists()) return candidate;
  }
  return File("${dir.path}/$stem-${DateTime.now().millisecondsSinceEpoch}$ext");
}

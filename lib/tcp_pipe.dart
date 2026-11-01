import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

const chunkBytes = 4 * 1024 * 1024;
const directTcpPort = 45921;

class ChunkReader {
  ChunkReader(this.socket) {
    _sub = socket.listen((data) {
      _data.addAll(data);
      _wake();
    }, onError: (Object error) {
      _error = error;
      _wake();
    }, onDone: () {
      _done = true;
      _wake();
    });
  }

  final Socket socket;
  late final StreamSubscription<Uint8List> _sub;
  final _data = <int>[];
  var _done = false;
  Object? _error;
  Completer<void>? _wait;

  void _wake() {
    final pending = _wait;
    _wait = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<void> _more() async {
    if (_error != null) throw _error!;
    if (_done) throw StateError("conexão direta caiu");
    _wait = Completer<void>();
    await _wait!.future;
  }

  Future<Uint8List> take(int count) async {
    while (_data.length < count) {
      await _more();
    }
    final out = Uint8List.fromList(_data.sublist(0, count));
    _data.removeRange(0, count);
    return out;
  }

  Future<String> line() async {
    while (true) {
      final end = _data.indexOf(10);
      if (end >= 0) {
        final text = utf8.decode(_data.sublist(0, end));
        _data.removeRange(0, end + 1);
        return text;
      }
      await _more();
    }
  }

  Future<void> close() => _sub.cancel();
}

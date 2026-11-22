import 'dart:async';
import 'dart:convert';

class SseFrame {
  const SseFrame({this.id, this.event, required this.data, this.retryMs,
    required this.isCommentOnly});
  final String? id;
  final String? event;
  final String data;
  final int? retryMs;
  final bool isCommentOnly;
}

class SseParser {
  const SseParser();

  Stream<SseFrame> parse(Stream<List<int>> bytes) {
    String? id, event;
    int? retry;
    var comment = false;
    final data = <String>[];
    final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
    return lines.transform(StreamTransformer<String, SseFrame>.fromHandlers(handleData: (line, sink) {
      if (line.isEmpty) {
        if (comment || data.isNotEmpty || retry != null || event != null || id != null) {
          sink.add(SseFrame(id: id, event: event, data: data.join('\n'), retryMs: retry,
            isCommentOnly: comment && data.isEmpty && event == null && id == null && retry == null));
        }
        data.clear();
        id = event = null;
        retry = null;
        comment = false;
        return;
      }
      if (line.startsWith(':')) {
        comment = true;
        return;
      }
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'data': data.add(value);
        case 'event': event = value;
        case 'id': if (!value.contains('\u0000')) id = value;
        case 'retry': if (RegExp(r'^[0-9]+$').hasMatch(value)) retry = int.tryParse(value);
      }
    }));
  }
}

class SseStreamHandle {
  SseStreamHandle(Stream<List<int>> bytes, this._abort) {
    _frames = StreamController<SseFrame>(onCancel: close);
    _subscription = const SseParser().parse(bytes).listen(_frames.add,
        onError: _frames.addError, onDone: _frames.close);
  }
  final void Function() _abort;
  late final StreamController<SseFrame> _frames;
  StreamSubscription<SseFrame>? _subscription;
  bool _closed = false;
  Stream<SseFrame> get stream => _frames.stream;
  void close() {
    if (_closed) return;
    _closed = true;
    _abort();
    unawaited(_subscription?.cancel());
    if (!_frames.isClosed) unawaited(_frames.close());
  }
}

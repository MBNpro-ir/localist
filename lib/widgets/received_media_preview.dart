import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Small native video thumbnails, cached independently of history rebuilds.
class ReceivedVideoPreview extends StatefulWidget {
  const ReceivedVideoPreview({super.key, required this.path});
  final String path;
  @override
  State<ReceivedVideoPreview> createState() => _ReceivedVideoPreviewState();
}

class _ReceivedVideoPreviewState extends State<ReceivedVideoPreview> {
  static const _channel = MethodChannel('com.prs.localist.vpn');
  static final _cache = <String, Future<Uint8List?>>{};
  late Future<Uint8List?> _thumbnail;

  void _load() {
    if (_cache.length >= 80 && !_cache.containsKey(widget.path)) {
      _cache.remove(_cache.keys.first);
    }
    _thumbnail = _cache.putIfAbsent(widget.path, () async {
      if (!await File(widget.path).exists()) return null;
      try {
        return await _channel.invokeMethod<Uint8List>('getMediaThumbnail', {
          'path': widget.path,
        });
      } catch (_) {
        return null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReceivedVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) _load();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      FutureBuilder<Uint8List?>(
        future: _thumbnail,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return data == null
              ? Icon(
                  Icons.movie_outlined,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                )
              : Image.memory(
                  data,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.movie_outlined, size: 54),
                );
        },
      ),
      const Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.play_circle,
            color: Colors.white,
            shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
            size: 30,
          ),
        ),
      ),
    ],
  );
}

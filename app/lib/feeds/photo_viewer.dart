import 'dart:io';

import 'package:flutter/material.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import '../media/zoom.dart';
import 'media_view.dart';

/// Full-screen photos of one post: swipe between album photos, pinch or double tap to zoom.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.gateway,
    this.initialIndex = 0,
  });
  final List<PhotoMedia> photos;
  final TelegramGateway gateway;
  final int initialIndex;

  static Future<void> open(
    BuildContext context, {
    required List<PhotoMedia> photos,
    required TelegramGateway gateway,
    int initialIndex = 0,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PhotoViewerScreen(
        photos: photos,
        gateway: gateway,
        initialIndex: initialIndex,
      ),
    ),
  );

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Paging is off while a photo is zoomed in, so a drag pans the photo instead.
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.photos.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black45,
        foregroundColor: Colors.white,
        title: many ? Text('${_index + 1} of ${widget.photos.length}') : null,
      ),
      body: PageView.builder(
        controller: _pages,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _ZoomablePhoto(
          photo: widget.photos[i],
          gateway: widget.gateway,
          onZoomChanged: (z) {
            if (z != _zoomed) setState(() => _zoomed = z);
          },
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.photo,
    required this.gateway,
    required this.onZoomChanged,
  });
  final PhotoMedia photo;
  final TelegramGateway gateway;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_report);
  }

  void _report() => widget.onZoomChanged(_transform.isZoomed);

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: () => _transform.toggleZoom(_doubleTapAt),
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        child: Center(
          // The full-size file, not the viewport-sized one the timeline shows.
          child: Downloaded(
            file: widget.photo.largest,
            gateway: widget.gateway,
            placeholder: const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
            builder: (context, path) => Image.file(
              File(path),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

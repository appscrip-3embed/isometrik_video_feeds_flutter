import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart' as pm;

/// Grid thumbnail for a gallery asset backed by an in-memory bytes cache.
///
/// [cachedThumbnail] is read synchronously so cells scrolled back into view
/// paint immediately instead of flashing a placeholder.
class GalleryThumbnailWidget extends StatefulWidget {
  const GalleryThumbnailWidget({
    super.key,
    required this.assetId,
    required this.size,
    required this.cachedThumbnail,
    required this.loadThumbnail,
  });

  final String assetId;
  final pm.ThumbnailSize size;
  final Uint8List? Function(String assetId) cachedThumbnail;
  final Future<Uint8List?> Function(String assetId, pm.ThumbnailSize size)
      loadThumbnail;

  @override
  State<GalleryThumbnailWidget> createState() => _GalleryThumbnailWidgetState();
}

class _GalleryThumbnailWidgetState extends State<GalleryThumbnailWidget> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant GalleryThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      _bytes = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    final assetId = widget.assetId;
    _bytes = widget.cachedThumbnail(assetId);
    if (_bytes != null) return;
    widget.loadThumbnail(assetId, widget.size).then((bytes) {
      if (!mounted || widget.assetId != assetId) return;
      setState(() {
        _bytes = bytes;
        _failed = bytes == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return ColoredBox(
      color: Colors.grey.shade300,
      child: bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _brokenIcon,
            )
          : _failed
              ? _brokenIcon
              : const SizedBox.expand(),
    );
  }

  Widget get _brokenIcon => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.grey),
      );
}

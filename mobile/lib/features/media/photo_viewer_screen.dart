import 'dart:io';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class PhotoViewerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final int? size;
  final int? createdAt;

  const PhotoViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.size,
    this.createdAt,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _controlsVisible = true;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else if (_doubleTapDetails != null) {
      final position = _doubleTapDetails!.localPosition;
      _transformController.value = Matrix4.identity()
        ..translateByVector3(Vector3(-position.dx * 1.5, -position.dy * 1.5, 0.0))
        ..scaleByVector3(Vector3(2.5, 2.5, 1.0));
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.filePath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('File path copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);
    final exists = file.existsSync();
    final sizeKb = widget.size != null
        ? '${(widget.size! / 1024).toStringAsFixed(1)} KB'
        : (exists ? '${(file.lengthSync() / 1024).toStringAsFixed(1)} KB' : '');

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _controlsVisible
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeKb.isNotEmpty)
                    Text(
                      sizeKb,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy file path',
                  onPressed: _copyToClipboard,
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _controlsVisible = !_controlsVisible;
          });
        },
        onDoubleTapDown: (d) => _doubleTapDetails = d,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: exists
              ? InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.8,
                  maxScale: 5.0,
                  clipBehavior: Clip.none,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => _buildErrorState('Could not render image file'),
                  ),
                )
              : _buildErrorState('Photo not found on device\n(${widget.filePath})'),
        ),
      ),
      bottomNavigationBar: _controlsVisible
          ? Container(
              color: Colors.black.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.filePath,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_out_map, color: Colors.white70),
                      tooltip: 'Reset zoom',
                      onPressed: () {
                        _transformController.value = Matrix4.identity();
                      },
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildErrorState(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, size: 64, color: Colors.orange),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}

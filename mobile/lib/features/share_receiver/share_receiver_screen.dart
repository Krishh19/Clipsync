import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../data/secure_store.dart';
import '../../services/transfer_service.dart';

class ShareReceiverScreen extends StatefulWidget {
  final List<SharedMediaFile>? sharedFiles;
  final List<String>? initialItems;
  final TransferService? transferService;
  final void Function()? onClose;
  final Duration autoCloseDuration;

  const ShareReceiverScreen({
    super.key,
    this.sharedFiles,
    this.initialItems,
    this.transferService,
    this.onClose,
    this.autoCloseDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<ShareReceiverScreen> createState() => _ShareReceiverScreenState();
}

class _ShareReceiverScreenState extends State<ShareReceiverScreen> {
  late final TransferService _transferService;

  late List<_ShareItem> _items;
  int _currentIndex = 0;
  double _currentProgress = 0.0;
  bool _isSuccess = false;
  String? _errorMessage;
  Timer? _closeTimer;

  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB limit
  static const int maxTextSizeBytes = 1024 * 1024; // 1 MB limit

  @override
  void initState() {
    super.initState();
    _transferService =
        widget.transferService ?? TransferService(secureStore: SecureStore());

    _initItems();
    if (_items.isNotEmpty) {
      _startSequentialTransfer();
    }
  }

  void _initItems() {
    _items = [];
    if (widget.sharedFiles != null && widget.sharedFiles!.isNotEmpty) {
      for (final f in widget.sharedFiles!) {
        _items.add(_ShareItem(
          path: f.path,
          type: f.type,
          name: f.path.split(Platform.pathSeparator).last,
        ));
      }
    } else if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      for (final item in widget.initialItems!) {
        final isPath = File(item).existsSync();
        _items.add(_ShareItem(
          path: item,
          type: isPath ? SharedMediaType.file : SharedMediaType.text,
          name: isPath ? item.split(Platform.pathSeparator).last : item,
        ));
      }
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSequentialTransfer() async {
    setState(() {
      _isSuccess = false;
      _errorMessage = null;
      _currentProgress = 0.0;
    });

    for (int i = _currentIndex; i < _items.length; i++) {
      _currentIndex = i;
      final item = _items[i];

      setState(() {
        _currentProgress = 0.1;
      });

      try {
        if (item.type == SharedMediaType.text || item.type == SharedMediaType.url) {
          // Check text limit (1 MB)
          final bytes = item.path.length;
          if (bytes > maxTextSizeBytes) {
            throw ArgumentError('Text exceeds 1 MB limit');
          }
          final kind = (item.path.startsWith('http://') || item.path.startsWith('https://'))
              ? 'link'
              : 'text';
          await _transferService.sendText(item.path, kind: kind);
        } else {
          // Check file limit (50 MB)
          final file = File(item.path);
          if (!file.existsSync()) {
            throw FileSystemException('File not found', item.path);
          }
          final size = file.lengthSync();
          if (size > maxFileSizeBytes) {
            final mb = (size / (1024 * 1024)).toStringAsFixed(1);
            throw ArgumentError('File "${item.name}" exceeds 50 MB limit ($mb MB)');
          }

          await _transferService.sendFile(file, fileName: item.name);
        }

        setState(() {
          _currentProgress = 1.0;
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('Invalid argument(s): ', '');
          });
        }
        return; // Halt sequential transfer on error
      }
    }

    // All items sent successfully
    if (mounted) {
      setState(() {
        _isSuccess = true;
      });

      _closeTimer = Timer(widget.autoCloseDuration, () {
        if (mounted) {
          _handleClose();
        }
      });
    }
  }

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      SystemNavigator.pop();
    }
  }

  void _retry() {
    _startSequentialTransfer();
  }

  @override
  Widget build(BuildContext context) {
    final currentItemName =
        _items.isNotEmpty && _currentIndex < _items.length
            ? _items[_currentIndex].name
            : 'Content';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _items.isEmpty
                  ? 'No items to send'
                  : 'Sending to PC (${_currentIndex + 1} of ${_items.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (_isSuccess) ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 56),
              const SizedBox(height: 12),
              Text(
                _items.length > 1
                    ? 'All ${_items.length} items sent!'
                    : 'Sent!',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ] else if (_errorMessage != null) ...[
              const Icon(Icons.error, color: Colors.red, size: 56),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: _handleClose,
                    child: const Text('Close'),
                  ),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                currentItemName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _currentProgress),
              const SizedBox(height: 12),
              Text(
                'Streaming to paired PC...',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareItem {
  final String path;
  final SharedMediaType type;
  final String name;

  const _ShareItem({
    required this.path,
    required this.type,
    required this.name,
  });
}

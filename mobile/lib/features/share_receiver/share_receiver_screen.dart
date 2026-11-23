import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class ShareReceiverScreen extends StatefulWidget {
  final List<String> items;

  const ShareReceiverScreen({super.key, this.items = const []});

  @override
  State<ShareReceiverScreen> createState() => _ShareReceiverScreenState();
}

class _ShareReceiverScreenState extends State<ShareReceiverScreen> {
  final int _currentIndex = 0;
  double _progress = 0.0;
  bool _isSuccess = false;
  String? _errorMessage;
  Timer? _closeTimer;

  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB limit per SPEC

  @override
  void initState() {
    super.initState();
    _startSending();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _startSending() async {
    // Check if items exceed size limit
    if (widget.items.length > maxFileSizeBytes) {
      setState(() {
        _errorMessage = 'Item exceeds 50 MB limit';
      });
      return;
    }

    setState(() {
      _progress = 0.5;
      _errorMessage = null;
      _isSuccess = false;
    });

    // Simulate transfer or execute transfer pipeline
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _progress = 1.0;
        _isSuccess = true;
      });

      _closeTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          SystemNavigator.pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sending to PC (${_currentIndex + 1}/${widget.items.isEmpty ? 1 : widget.items.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (_isSuccess) ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 8),
              const Text('Sent!'),
            ] else if (_errorMessage != null) ...[
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('Close'),
                  ),
                  ElevatedButton(
                    onPressed: _startSending,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ] else ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 12),
              const Text('Streaming to paired PC...'),
            ],
          ],
        ),
      ),
    );
  }
}

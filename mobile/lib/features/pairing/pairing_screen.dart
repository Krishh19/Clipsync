import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  bool _isManual = false;
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '47821');
  final _tokenController = TextEditingController();
  final _fpController = TextEditingController();

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _fpController.dispose();
    super.dispose();
  }

  void _onQrDetected(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null) {
        final payload = PairQrPayload.tryParse(raw);
        if (payload != null) {
          // Handle scanned QR payload
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scanned pairing QR for ${payload.serverName}')),
          );
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair with PC'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _isManual = !_isManual),
            child: Text(
              _isManual ? 'Scan QR' : 'Manual Entry',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _isManual ? _buildManualForm() : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: _onQrDetected,
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Point camera at the pairing QR code displayed in the ClipSync desktop app.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildManualForm() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(labelText: 'PC IP Address (Host)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(labelText: 'Port'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(labelText: 'Pairing Token'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fpController,
            decoration: const InputDecoration(labelText: 'Certificate Fingerprint (SHA-256)'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // Submit manual pair
            },
            child: const Text('Connect & Pair'),
          ),
        ],
      ),
    );
  }
}

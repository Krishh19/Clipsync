import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/pairing_models.dart';
import '../../data/secure_store.dart';
import '../../services/pairing_service.dart';

class PairingScreen extends StatefulWidget {
  final PairingService? pairingService;

  const PairingScreen({super.key, this.pairingService});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  late final PairingService _pairingService;
  final MobileScannerController _scannerController = MobileScannerController();

  bool _isManual = false;
  bool _isPairing = false;
  String? _statusMessage;

  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '47821');
  final _tokenController = TextEditingController();
  final _fpController = TextEditingController();
  final _nameController = TextEditingController(text: 'Windows PC');

  @override
  void initState() {
    super.initState();
    _pairingService = widget.pairingService ??
        PairingService(secureStore: SecureStore());
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _fpController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onQrDetected(BarcodeCapture capture) async {
    if (_isPairing) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null) {
        final payload = PairQrPayload.tryParse(raw);
        if (payload != null) {
          await _executePairing(payload);
          break;
        }
      }
    }
  }

  Future<void> _executePairing(PairQrPayload payload) async {
    setState(() {
      _isPairing = true;
      _statusMessage = 'Verifying certificate and pairing with ${payload.serverName}...';
    });

    final result = await _pairingService.pairWithPayload(payload);

    if (!mounted) return;

    setState(() {
      _isPairing = false;
      _statusMessage = null;
    });

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully paired with ${result.serverName}!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pairing failed: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onManualSubmit() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final token = _tokenController.text.trim();
    final fp = _fpController.text.trim();
    final name = _nameController.text.trim();

    if (host.isEmpty) {
      _showError('Host IP address cannot be empty');
      return;
    }
    if (port == null || port <= 0 || port > 65535) {
      _showError('Port must be between 1 and 65535');
      return;
    }
    if (token.isEmpty) {
      _showError('Pairing token cannot be empty');
      return;
    }
    final normalizedFp = fp.replaceAll(':', '').replaceAll(' ', '').toLowerCase();
    if (normalizedFp.length != 64) {
      _showError('Fingerprint must be a 64-character SHA-256 hex string');
      return;
    }

    final payload = PairQrPayload(
      host: host,
      port: port,
      token: token,
      fingerprint: normalizedFp,
      serverDeviceId: '', // Empty indicates manual override
      serverName: name.isNotEmpty ? name : 'Windows PC',
    );

    _executePairing(payload);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair with PC'),
        actions: [
          TextButton(
            onPressed: _isPairing
                ? null
                : () => setState(() => _isManual = !_isManual),
            child: Text(
              _isManual ? 'Scan QR' : 'Manual Entry',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isManual ? _buildManualForm() : _buildScanner(),
          if (_isPairing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage ?? 'Pairing in progress...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _onQrDetected,
                errorBuilder: (context, error) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_photography, size: 52, color: Colors.amber),
                          const SizedBox(height: 12),
                          const Text(
                            'Camera access is required to scan QR code',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${error.errorCode.name}: ${error.errorDetails?.message ?? "Permission required"}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _scannerController.start(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Grant Camera / Retry'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setState(() => _isManual = true),
                            child: const Text('Enter Details Manually'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Center(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.deepPurple, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'Scan the QR code shown in the ClipSync desktop app window.\nIt pairs securely using certificate pinning.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
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
            decoration: const InputDecoration(
              labelText: 'PC IP Address (Host)',
              hintText: 'e.g. 192.168.1.100',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'One-Time Pairing Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fpController,
            decoration: const InputDecoration(
              labelText: 'Certificate Fingerprint (SHA-256)',
              hintText: '64 hex characters',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'PC Name (Optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _isPairing ? null : _onManualSubmit,
            icon: const Icon(Icons.link),
            label: const Text(
              'Connect & Pair',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

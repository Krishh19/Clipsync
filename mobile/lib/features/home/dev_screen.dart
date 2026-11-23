import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../data/secure_store.dart';
import '../../services/transfer_service.dart';

class DevScreen extends StatefulWidget {
  final SecureStore? secureStore;
  final TransferService? transferService;

  const DevScreen({super.key, this.secureStore, this.transferService});

  @override
  State<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends State<DevScreen> {
  late final SecureStore _secureStore;
  late final TransferService _transferService;

  final TextEditingController _hostController =
      TextEditingController(text: '127.0.0.1');
  final TextEditingController _portController =
      TextEditingController(text: '47821');
  final TextEditingController _tokenController =
      TextEditingController(text: 'dev-token-clipsync');
  final TextEditingController _textController = TextEditingController();

  bool _isConnecting = false;
  String? _connectionResult;
  bool _isConnected = false;

  List<TransferItem> _transfers = [];

  @override
  void initState() {
    super.initState();
    _secureStore = widget.secureStore ?? SecureStore();
    _transferService = widget.transferService ??
        TransferService(secureStore: _secureStore);

    _loadSavedConfig();

    _transferService.queueStream.listen((items) {
      if (mounted) {
        setState(() {
          _transfers = List.from(items);
        });
      }
    });
  }

  void _loadSavedConfig() async {
    final host = await _secureStore.getPcHost();
    final port = await _secureStore.getPcPort();
    final token = await _secureStore.getPcSecret();
    if (host != null) _hostController.text = host;
    if (port != null) _portController.text = port.toString();
    if (token != null) _tokenController.text = token;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isConnecting = true;
      _connectionResult = null;
    });

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 47821;
    final token = _tokenController.text.trim();

    try {
      final client = ApiClient.fromConfig(
        host: host,
        port: port,
        deviceSecret: token,
        isDevPlainHttp: true,
      );

      final info = await client.getInfo();
      await _secureStore.saveDevConfig(host: host, port: port, token: token);

      setState(() {
        _isConnecting = false;
        _isConnected = true;
        _connectionResult =
            'Connected to ${info.name} (ID: ${info.deviceId}, Protocol: ${info.protocol})';
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _connectionResult = 'Connection failed: $e';
      });
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text;
    if (text.isEmpty) return;

    try {
      await _transferService.sendText(text);
      _textController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Text queued for transfer')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;

      final path = files.first.path;
      if (path == null) return;

      final file = File(path);
      final size = await file.length();

      // Reject files > 50 MB on client per SPEC Section 10 & 12
      if (size > 50 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File exceeds 50 MB limit (${(size / (1024 * 1024)).toStringAsFixed(1)} MB)',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await _transferService.sendFile(
        file,
        fileName: files.first.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File queued: ${files.first.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dev Sender (M2 MVP)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildConnectionCard(),
          const SizedBox(height: 16),
          _buildTextSenderCard(),
          const SizedBox(height: 16),
          _buildFileSenderCard(),
          const SizedBox(height: 16),
          const Text(
            'Transfer Queue & Progress',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildTransfersList(),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Dev Connection (Plain HTTP)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Host IP',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Dev Token',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isConnecting ? null : _testConnection,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(_isConnecting ? 'Testing...' : 'Test & Save Connection'),
            ),
            if (_connectionResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _connectionResult!,
                style: TextStyle(
                  color: _isConnected ? Colors.green : Colors.red,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextSenderCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Send Text (<= 1 MB)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter text to send directly to Windows clipboard...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _sendText,
              icon: const Icon(Icons.send),
              label: const Text('Send Text to PC'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSenderCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Send File (<= 50 MB)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pickAndSendFile,
              icon: const Icon(Icons.attach_file),
              label: const Text('Pick & Stream File (Photo, Video, etc.)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransfersList() {
    if (_transfers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No transfers in queue',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _transfers.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final item = _transfers[index];
        return ListTile(
          leading: Icon(
            item.kind == 'image'
                ? Icons.image
                : item.kind == 'video'
                    ? Icons.videocam
                    : Icons.text_snippet,
          ),
          title: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: ${item.status} • Size: ${(item.size / 1024).toStringAsFixed(1)} KB',
              ),
              if (item.status == 'sending') ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(value: item.progress),
                Text(
                  '${(item.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
              if (item.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  item.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
              ],
            ],
          ),
          trailing: item.status == 'done'
              ? const Icon(Icons.check_circle, color: Colors.green)
              : item.status == 'failed'
                  ? const Icon(Icons.error, color: Colors.red)
                  : const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
        );
      },
    );
  }
}

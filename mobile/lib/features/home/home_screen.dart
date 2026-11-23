import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../data/secure_store.dart';
import '../../services/transfer_service.dart';
import 'dev_screen.dart';

class HomeScreen extends StatefulWidget {
  final SecureStore? secureStore;
  final TransferService? transferService;

  const HomeScreen({super.key, this.secureStore, this.transferService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SecureStore _secureStore;
  late final TransferService _transferService;

  final TextEditingController _textController = TextEditingController();
  List<TransferItem> _recentTransfers = [];
  String _connectionStatus = 'Offline';
  String _pcName = 'Not Paired';

  @override
  void initState() {
    super.initState();
    _secureStore = widget.secureStore ?? SecureStore();
    _transferService = widget.transferService ??
        TransferService(secureStore: _secureStore);

    _loadPcInfo();

    _transferService.queueStream.listen((items) {
      if (mounted) {
        setState(() {
          _recentTransfers = List.from(items);
        });
      }
    });
  }

  void _loadPcInfo() async {
    final isDev = await _secureStore.isDevMode();
    final name = await _secureStore.getPcName();
    final host = await _secureStore.getPcHost();
    if (mounted) {
      setState(() {
        if (name != null || host != null) {
          _pcName = name ?? host ?? 'Paired PC';
          _connectionStatus = isDev ? 'Dev Mode' : 'Connected';
        } else {
          _pcName = 'Not Paired';
          _connectionStatus = 'Offline';
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _sendClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      try {
        await _transferService.sendText(text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard text queued for transfer')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Send error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty')),
        );
      }
    }
  }

  void _sendText() async {
    final text = _textController.text.trim();
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
            content: Text('Send error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _pickAndSendFile({FileType type = FileType.any}) async {
    try {
      final files = await FilePicker.pickFiles(type: type);
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
            content: Text('File picker error: $e'),
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
        title: const Text('ClipSync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.developer_mode),
            tooltip: 'Dev Connection (M2)',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DevScreen(
                    secureStore: _secureStore,
                    transferService: _transferService,
                  ),
                ),
              );
              _loadPcInfo();
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.pushNamed(context, '/history');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildConnectionChip(),
          const SizedBox(height: 24),
          _buildSendClipboardButton(),
          const SizedBox(height: 24),
          _buildTextInput(),
          const SizedBox(height: 16),
          _buildMediaButtons(),
          const SizedBox(height: 24),
          const Text(
            'Recent Transfers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildRecentTransfers(),
        ],
      ),
    );
  }

  Widget _buildConnectionChip() {
    Color chipColor = Colors.grey;
    if (_connectionStatus == 'Connected' || _connectionStatus == 'Dev Mode') {
      chipColor = Colors.green;
    }
    if (_connectionStatus == 'Searching') chipColor = Colors.orange;

    return Center(
      child: Chip(
        avatar: CircleAvatar(
          backgroundColor: chipColor,
          radius: 6,
        ),
        label: Text('$_pcName ($_connectionStatus)'),
      ),
    );
  }

  Widget _buildSendClipboardButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _sendClipboard,
      icon: const Icon(Icons.content_paste, size: 28),
      label: const Text(
        'Send Clipboard to PC',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildTextInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            decoration: const InputDecoration(
              hintText: 'Type text or paste a link...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _sendText,
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }

  Widget _buildMediaButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pickAndSendFile(type: FileType.media),
          icon: const Icon(Icons.photo_library),
          label: const Text('Photo/Video'),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickAndSendFile(type: FileType.any),
          icon: const Icon(Icons.attach_file),
          label: const Text('File'),
        ),
      ],
    );
  }

  Widget _buildRecentTransfers() {
    if (_recentTransfers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No recent transfers yet',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentTransfers.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final item = _recentTransfers[index];
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

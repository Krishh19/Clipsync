import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<TransferItem> _recentTransfers = [];
  final String _connectionStatus = 'Offline';
  final String _pcName = 'Not Paired';

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _sendClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _addTransfer(data.text!, 'text');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard is empty')),
        );
      }
    }
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      _addTransfer(text, 'text');
      _textController.clear();
    }
  }

  void _addTransfer(String label, String kind) {
    setState(() {
      _recentTransfers.insert(
        0,
        TransferItem(
          id: UniqueKey().toString(),
          direction: 'out',
          kind: kind,
          label: label,
          size: label.length,
          status: 'done',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClipSync'),
        actions: [
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
    if (_connectionStatus == 'Connected') chipColor = Colors.green;
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
          onPressed: () {
            // Pick photo / video
          },
          icon: const Icon(Icons.photo_library),
          label: const Text('Photo/Video'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            // Pick file
          },
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
          subtitle: Text(item.status),
          trailing: item.status == 'failed'
              ? IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    // Retry
                  },
                )
              : const Icon(Icons.check_circle, color: Colors.green),
        );
      },
    );
  }
}

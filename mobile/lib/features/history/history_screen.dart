import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final List<TransferItem> _items = [];

  void _copyItem(TransferItem item) {
    Clipboard.setData(ClipboardData(text: item.label));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() => _items.clear());
            },
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text(
                'No transfer history',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  leading: Icon(
                    item.kind == 'image'
                        ? Icons.image
                        : item.kind == 'video'
                            ? Icons.videocam
                            : Icons.text_snippet,
                  ),
                  title: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.direction == 'in' ? 'Received' : 'Sent'} • ${DateTime.fromMillisecondsSinceEpoch(item.createdAt).toLocal().toString().split('.')[0]}',
                  ),
                  onTap: () => _copyItem(item),
                );
              },
            ),
    );
  }
}

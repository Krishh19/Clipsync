import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db.dart';

class HistoryScreen extends StatefulWidget {
  final AppDatabase? database;

  const HistoryScreen({super.key, this.database});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final AppDatabase _db;
  List<Transfer> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final items = await (_db.select(_db.transfers)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Transfer History?'),
        content: const Text(
          'This will remove all sent and received transfer records from your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.delete(_db.transfers).go();
      setState(() => _items.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer history cleared')),
        );
      }
    }
  }

  void _copyItem(Transfer item) {
    Clipboard.setData(ClipboardData(text: item.label));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied "${item.label}" to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear history',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isIncoming = item.direction == 'in';
                    final dateStr = DateTime.fromMillisecondsSinceEpoch(item.createdAt)
                        .toLocal()
                        .toString()
                        .split('.')[0];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isIncoming
                            ? Colors.blue.withValues(alpha: 0.15)
                            : Colors.green.withValues(alpha: 0.15),
                        child: Icon(
                          item.kind == 'image'
                              ? Icons.image
                              : item.kind == 'video'
                                  ? Icons.videocam
                                  : item.kind == 'link'
                                      ? Icons.link
                                      : Icons.text_snippet,
                          color: isIncoming ? Colors.blue : Colors.green,
                        ),
                      ),
                      title: Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${isIncoming ? 'Received from PC' : 'Sent to PC'} • $dateStr',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy',
                        onPressed: () => _copyItem(item),
                      ),
                      onTap: () => _copyItem(item),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Transfer History Yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Items sent or received between your phone and PC will appear here automatically. Tap any item to copy it to clipboard.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/db.dart';
import '../media/photo_viewer_screen.dart';
import '../media/text_detail_sheet.dart';

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
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'image', 'file', 'text', 'link'
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _db = widget.database ?? AppDatabase();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${item.label}" to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onItemTap(Transfer item) {
    if (item.kind == 'image' && item.filePath != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoViewerScreen(
            filePath: item.filePath!,
            title: item.label,
            size: item.size,
            createdAt: item.createdAt,
          ),
        ),
      );
    } else if (item.kind == 'text' || item.kind == 'link') {
      TextDetailSheet.show(
        context,
        text: item.label,
        direction: item.direction,
        createdAt: item.createdAt,
      );
    } else {
      _copyItem(item);
    }
  }

  Widget _buildLeadingThumbnail(Transfer item) {
    if (item.kind == 'image' && item.filePath != null && File(item.filePath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.filePath!),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallbackAvatar(item),
        ),
      );
    }
    return _buildFallbackAvatar(item);
  }

  Widget _buildFallbackAvatar(Transfer item) {
    final isIncoming = item.direction == 'in';
    return CircleAvatar(
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
                    : item.kind == 'file'
                        ? Icons.attach_file
                        : Icons.text_snippet,
        color: isIncoming ? Colors.blue : Colors.green,
      ),
    );
  }

  List<Transfer> get _filteredItems {
    return _items.filter((item) {
      // Type filter
      if (_selectedFilter != 'all') {
        if (_selectedFilter == 'file' && (item.kind == 'file' || item.kind == 'video')) {
          // matches file
        } else if (item.kind != _selectedFilter) {
          return false;
        }
      }
      // Search query
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchLabel = item.label.toLowerCase().contains(q);
        final matchPath = item.filePath?.toLowerCase().contains(q) ?? false;
        return matchLabel || matchPath;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;
    final imageCount = _items.where((i) => i.kind == 'image').length;
    final fileCount = _items.where((i) => i.kind == 'file' || i.kind == 'video').length;
    final textCount = _items.where((i) => i.kind == 'text').length;
    final linkCount = _items.where((i) => i.kind == 'link').length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Transfer History (${_items.length})'),
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
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search transfers by name or text...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      filled: true,
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                  ),
                ),

                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'All (${_items.length})'),
                      const SizedBox(width: 6),
                      _buildFilterChip('image', 'Photos ($imageCount)'),
                      const SizedBox(width: 6),
                      _buildFilterChip('file', 'Files ($fileCount)'),
                      const SizedBox(width: 6),
                      _buildFilterChip('text', 'Text ($textCount)'),
                      const SizedBox(width: 6),
                      _buildFilterChip('link', 'Links ($linkCount)'),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // List
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final isIncoming = item.direction == 'in';
                            final dateStr = DateTime.fromMillisecondsSinceEpoch(item.createdAt)
                                .toLocal()
                                .toString()
                                .split('.')[0];
                            final isImage = item.kind == 'image';

                            return ListTile(
                              leading: _buildLeadingThumbnail(item),
                              title: Text(
                                item.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                '${isIncoming ? '← From PC' : '→ To PC'} • $dateStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isImage)
                                    IconButton(
                                      icon: const Icon(Icons.remove_red_eye, size: 20),
                                      tooltip: 'View Photo',
                                      onPressed: () => _onItemTap(item),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 20),
                                    tooltip: 'Copy',
                                    onPressed: () => _copyItem(item),
                                  ),
                                ],
                              ),
                              onTap: () => _onItemTap(item),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        setState(() => _selectedFilter = value);
      },
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
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No Matching Transfers Found' : 'No Transfer History Yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try searching with different keywords or clearing filters.'
                  : 'Items sent or received between your phone and PC will appear here. Tap photos to view full size.',
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

extension _IterableFilter<T> on Iterable<T> {
  Iterable<T> filter(bool Function(T element) test) => where(test);
}

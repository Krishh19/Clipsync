import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../data/db.dart';
import '../../data/secure_store.dart';
import '../../services/events_service.dart';
import '../../services/notifications.dart';
import '../../services/transfer_service.dart';
import '../history/history_screen.dart';
import '../media/photo_viewer_screen.dart';
import '../media/text_detail_sheet.dart';
import '../pairing/pairing_screen.dart';
import '../settings/settings_screen.dart';
import 'dev_screen.dart';

class HomeScreen extends StatefulWidget {
  final SecureStore? secureStore;
  final TransferService? transferService;
  final AppDatabase? database;
  final EventsService? eventsService;

  const HomeScreen({
    super.key,
    this.secureStore,
    this.transferService,
    this.database,
    this.eventsService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SecureStore _secureStore;
  late final TransferService _transferService;
  late final AppDatabase _db;
  late final EventsService _eventsService;
  StreamSubscription<List<Transfer>>? _dbSubscription;
  StreamSubscription<List<TransferItem>>? _queueSubscription;
  StreamSubscription<bool>? _wsSubscription;

  final TextEditingController _textController = TextEditingController();
  List<TransferItem> _recentTransfers = [];
  List<Transfer> _persistedTransfers = [];
  String _connectionStatus = 'Offline';
  String _pcName = 'Not Paired';
  bool _isWsLive = false;

  @override
  void initState() {
    super.initState();
    _secureStore = widget.secureStore ?? SecureStore();
    _db = widget.database ?? AppDatabase();
    _transferService = widget.transferService ??
        TransferService(secureStore: _secureStore, database: _db);
    _eventsService = widget.eventsService ??
        EventsService(secureStore: _secureStore, database: _db);

    _initNotificationsAndEvents();
    _loadPcInfo();

    _queueSubscription = _transferService.queueStream.listen((items) {
      if (mounted) {
        setState(() {
          _recentTransfers = List.from(items);
        });
      }
    });

    _wsSubscription = _eventsService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isWsLive = connected;
        });
      }
    });

    _dbSubscription = (_db.select(_db.transfers)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(10))
        .watch()
        .listen((items) {
      if (mounted) {
        setState(() {
          _persistedTransfers = items;
        });
      }
    });
  }

  Future<void> _initNotificationsAndEvents() async {
    try {
      await NotificationsService.initialize(
        onNotificationTapped: (response) {
          if (response.actionId != null && response.payload != null) {
            _eventsService.handleNotificationAction(
              actionId: response.actionId!,
              payload: response.payload!,
            );
          }
        },
      );
      await NotificationsService.requestPermission();
    } catch (_) {}
    await _eventsService.start();
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
    if (!isDev && host != null) {
      _eventsService.stop();
      await _eventsService.start();
    } else if (host == null) {
      _eventsService.stop();
    }
  }

  Future<void> _openPairing() async {
    try {
      await context.push('/pair');
    } catch (_) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PairingScreen()),
      );
    }
    _loadPcInfo();
  }

  Future<void> _openHistory() async {
    try {
      await context.push('/history');
    } catch (_) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HistoryScreen()),
      );
    }
  }

  Future<void> _openSettings() async {
    try {
      await context.push('/settings');
    } catch (_) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
    _loadPcInfo();
  }

  @override
  void dispose() {
    _eventsService.stop();
    _wsSubscription?.cancel();
    _queueSubscription?.cancel();
    _dbSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }

  String _formatRelativeTime(int timestampMs) {
    final now = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  void _onPersistedItemTap(Transfer item) {
    if (item.kind == 'image' && item.filePath != null && File(item.filePath!).existsSync()) {
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
      Clipboard.setData(ClipboardData(text: item.label));
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied "${item.label}" to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
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

  void _sendClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      if (LoopPrevention.isIncoming(text)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clipboard text was received from PC (loop prevented)'),
            ),
          );
        }
        return;
      }
      try {
        final kind = (text.startsWith('http://') || text.startsWith('https://'))
            ? 'link'
            : 'text';
        await _transferService.sendText(text, kind: kind);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard text queued for transfer')),
          );
        }
      } catch (e) {
        String errorMsg = 'Send error: $e';
        if (e.toString().contains('exceeds maximum limit')) {
          errorMsg = 'Clipboard text exceeds 1 MB limit. Please shorten or share as a file.';
        } else if (e.toString().contains('Failed host lookup') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('timed out')) {
          errorMsg =
              'Could not reach $_pcName. Ensure ClipSync is open on your PC and both devices are on the same Wi-Fi.';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
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
      String errorMsg = 'Send error: $e';
      if (e.toString().contains('exceeds maximum limit')) {
        errorMsg = 'Text exceeds 1 MB limit. Please shorten text or share as a file.';
      } else if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('timed out')) {
        errorMsg =
            'Could not reach $_pcName. Ensure ClipSync is open on your PC and both devices are on the same Wi-Fi.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
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
                'File exceeds 50 MB limit (${(size / (1024 * 1024)).toStringAsFixed(1)} MB). Please select a file under 50 MB.',
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
          if (kDebugMode)
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
            tooltip: 'Transfer History',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Transfers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_persistedTransfers.isNotEmpty)
                TextButton.icon(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('View All'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildRecentTransfers(),
        ],
      ),
    );
  }

  Widget _buildConnectionChip() {
    final isPaired = _connectionStatus == 'Connected' || _connectionStatus == 'Dev Mode';
    Color dotColor = Colors.grey;
    String statusText = 'Not Paired — Tap to scan QR';
    if (isPaired) {
      if (_isWsLive) {
        dotColor = Colors.green;
        statusText = 'Live Sync Active';
      } else {
        dotColor = Colors.orange;
        statusText = 'Paired (Connecting...)';
      }
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (!isPaired) {
            _openPairing();
          } else if (!_isWsLive) {
            _eventsService.stop();
            _eventsService.start();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pcName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isPaired)
                FilledButton.tonalIcon(
                  onPressed: _openPairing,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Pair'),
                )
              else if (!_isWsLive)
                IconButton(
                  tooltip: 'Reconnect',
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    _eventsService.stop();
                    _eventsService.start();
                  },
                )
              else
                const Icon(Icons.verified_user, color: Colors.green, size: 20),
            ],
          ),
        ),
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
    final activeQueue = _recentTransfers.where((i) => i.status == 'sending' || i.status == 'queued').toList();
    final hasNoTransfers = activeQueue.isEmpty && _persistedTransfers.isEmpty;

    if (hasNoTransfers) {
      final isConnected =
          _connectionStatus == 'Connected' || _connectionStatus == 'Dev Mode';
      return Card(
        elevation: 0,
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            children: [
              Icon(
                Icons.sync_alt_rounded,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Ready to Sync',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                isConnected
                    ? 'Type text, tap "Send Clipboard", or choose a photo/file to send instantly to $_pcName.'
                    : 'Pair with your Windows PC to begin syncing clipboards and sending files.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!isConnected) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _openPairing,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR to Pair'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final displayItems = _persistedTransfers.take(6).toList();

    return Column(
      children: [
        if (activeQueue.isNotEmpty) ...[
          ...activeQueue.map((item) => Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sending... ${(item.size / 1024).toStringAsFixed(1)} KB'),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: item.progress),
                ],
              ),
            ),
          )),
        ],
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayItems.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = displayItems[index];
            final isIncoming = item.direction == 'in';
            final isImage = item.kind == 'image';

            return ListTile(
              leading: _buildLeadingThumbnail(item),
              title: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${isIncoming ? '← From PC' : '→ To PC'} • ${_formatRelativeTime(item.createdAt)} • ${(item.size / 1024).toStringAsFixed(1)} KB',
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
                      onPressed: () => _onPersistedItemTap(item),
                    ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: item.label));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied "${item.label}" to clipboard'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
              onTap: () => _onPersistedItemTap(item),
            );
          },
        ),
      ],
    );
  }
}

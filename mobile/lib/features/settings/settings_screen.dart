import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/secure_store.dart';
import '../../services/foreground_service.dart';

class SettingsScreen extends StatefulWidget {
  final SecureStore? secureStore;

  const SettingsScreen({super.key, this.secureStore});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SecureStore _secureStore;
  bool _foregroundServiceEnabled = false;
  PermissionStatus _notificationStatus = PermissionStatus.denied;
  String? _pairedPcName;
  String? _pairedPcHost;
  int? _pairedPcPort;
  bool _isPaired = false;

  @override
  void initState() {
    super.initState();
    _secureStore = widget.secureStore ?? SecureStore();
    _checkPermissions();
    _loadPairedPc();
  }

  Future<void> _loadPairedPc() async {
    final paired = await _secureStore.isPaired();
    final name = await _secureStore.getPcName();
    final host = await _secureStore.getPcHost();
    final port = await _secureStore.getPcPort();
    final fgsRunning = await ForegroundServiceController.isRunning();

    if (mounted) {
      setState(() {
        _isPaired = paired;
        _pairedPcName = name;
        _pairedPcHost = host;
        _pairedPcPort = port;
        _foregroundServiceEnabled = fgsRunning;
      });
    }
  }

  void _checkPermissions() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _notificationStatus = status;
      });
    }
  }

  Future<void> _confirmUnpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair PC?'),
        content: Text(
          'Are you sure you want to disconnect from ${_pairedPcName ?? "your PC"}? You will need to scan the QR code again to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _secureStore.clearPairedPc();
      await ForegroundServiceController.stopService();
      await _loadPairedPc();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unpaired successfully')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pcSubtitle = _isPaired
        ? '${_pairedPcName ?? "PC"} (${_pairedPcHost ?? "unknown"}:${_pairedPcPort ?? 47821})'
        : 'No PC currently paired';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Paired PC'),
            subtitle: Text(pcSubtitle),
            leading: Icon(
              Icons.computer,
              color: _isPaired ? Colors.green : Colors.grey,
            ),
          ),
          if (_isPaired)
            ListTile(
              title: const Text('Unpair PC', style: TextStyle(color: Colors.red)),
              leading: const Icon(Icons.link_off, color: Colors.red),
              onTap: _confirmUnpair,
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('Run Background Service'),
            subtitle: const Text(
              'Required to receive clipboard & files from PC when the app is in the background',
            ),
            value: _foregroundServiceEnabled,
            onChanged: (val) async {
              setState(() => _foregroundServiceEnabled = val);
              if (val) {
                await ForegroundServiceController.startService(
                  pcName: _pairedPcName ?? 'ClipSync PC',
                );
              } else {
                await ForegroundServiceController.stopService();
              }
            },
          ),
          ListTile(
            title: const Text('Notifications Permission'),
            subtitle: Text(_notificationStatus.isGranted ? 'Granted' : 'Not Granted'),
            leading: const Icon(Icons.notifications),
            trailing: _notificationStatus.isGranted
                ? const Icon(Icons.check, color: Colors.green)
                : TextButton(
                    onPressed: () async {
                      final s = await Permission.notification.request();
                      if (mounted) {
                        setState(() => _notificationStatus = s);
                      }
                    },
                    child: const Text('Enable'),
                  ),
          ),
          const Divider(),
          const ListTile(
            title: Text('About ClipSync'),
            subtitle: Text('Version 0.1.0 • Private Local Wi-Fi Sync'),
            leading: Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }
}

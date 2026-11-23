import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _foregroundServiceEnabled = false;
  PermissionStatus _notificationStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  void _checkPermissions() async {
    final status = await Permission.notification.status;
    setState(() {
      _notificationStatus = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Paired PC'),
            subtitle: Text('DESKTOP-CLIPSYNC (192.168.1.100:47821)'),
            leading: Icon(Icons.computer),
          ),
          ListTile(
            title: const Text('Unpair PC', style: TextStyle(color: Colors.red)),
            leading: const Icon(Icons.link_off, color: Colors.red),
            onTap: () {
              // Confirm and unpair
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Run Background Service'),
            subtitle: const Text(
              'Required to receive clipboard & files from PC when the app is closed',
            ),
            value: _foregroundServiceEnabled,
            onChanged: (val) {
              setState(() => _foregroundServiceEnabled = val);
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
                      setState(() => _notificationStatus = s);
                    },
                    child: const Text('Enable'),
                  ),
          ),
          const Divider(),
          const ListTile(
            title: Text('About ClipSync'),
            subtitle: Text('Version 1.0.0 • Local WiFi sync'),
            leading: Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }
}

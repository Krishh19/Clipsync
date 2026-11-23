import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'features/history/history_screen.dart';
import 'features/home/dev_screen.dart';
import 'features/home/home_screen.dart';
import 'features/pairing/pairing_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/share_receiver/share_receiver_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/pair',
      builder: (context, state) => const PairingScreen(),
    ),
    GoRoute(
      path: '/dev',
      builder: (context, state) => const DevScreen(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/share',
      builder: (context, state) {
        final files = state.extra as List<SharedMediaFile>?;
        return ShareReceiverScreen(sharedFiles: files);
      },
    ),
  ],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: ClipSyncApp(),
    ),
  );
}

class ClipSyncApp extends StatefulWidget {
  const ClipSyncApp({super.key});

  @override
  State<ClipSyncApp> createState() => _ClipSyncAppState();
}

class _ClipSyncAppState extends State<ClipSyncApp> {
  StreamSubscription? _intentSub;

  @override
  void initState() {
    super.initState();
    // Listen for incoming share intents while app is running
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        _router.push('/share', extra: files);
      }
    });

    // Handle initial intent when opened via share sheet
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        _router.push('/share', extra: files);
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ClipSync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

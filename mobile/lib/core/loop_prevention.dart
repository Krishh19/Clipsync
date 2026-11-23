import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Prevents echo loops where an item received from the PC is inadvertently
/// sent back to the PC (e.g. via clipboard auto-send, Quick Settings tile, or share action).
class LoopPrevention {
  static final Set<String> _incomingHashes = {};
  static final List<String> _history = [];
  static const int maxCapacity = 100;

  /// Returns SHA-256 hash of content string
  static String hashContent(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  /// Mark content received from PC as incoming
  static void markIncoming(String content) {
    if (content.isEmpty) return;
    final h = hashContent(content);
    _incomingHashes.add(h);
    _history.add(h);
    if (_history.length > maxCapacity) {
      final old = _history.removeAt(0);
      _incomingHashes.remove(old);
    }
  }

  /// Check whether content was recently received from PC
  static bool isIncoming(String content) {
    if (content.isEmpty) return false;
    final h = hashContent(content);
    return _incomingHashes.contains(h);
  }

  /// Clear loop prevention state (for tests)
  static void clear() {
    _incomingHashes.clear();
    _history.clear();
  }
}

/// Thrown when sending content that was recently received from PC
class LoopDetectedException implements Exception {
  final String message;
  const LoopDetectedException([
    this.message = 'Echo loop prevented: content was recently received from PC',
  ]);

  @override
  String toString() => message;
}

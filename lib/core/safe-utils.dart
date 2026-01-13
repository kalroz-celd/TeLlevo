// lib/core/safe_utils.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void safeSnack(String message, {Duration duration = const Duration(seconds: 3)}) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message), duration: duration),
  );
}

mixin SafeState<T extends StatefulWidget> on State<T> {
  bool _disposed = false;

  void safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    // Si estamos en frame, posterga setState al próximo frame
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Para cancelar fácilmente streams/timers/dio tokens en dispose()
class CancelBag {
  final List<void Function()> _cancellers = [];
  void add(void Function() cancel) => _cancellers.add(cancel);
  void dispose() {
    for (final c in _cancellers) {
      try { c(); } catch (_) {}
    }
    _cancellers.clear();
  }
}

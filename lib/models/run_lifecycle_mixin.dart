import 'package:flutter/material.dart';
import 'package:tellevo/services/dio.dart' as api;

enum RunLifecycleOutcome { started, completed, aborted }

/// Mixin para comenzar y completar un run de forma segura.
/// - Usa `useRootNavigator: true` en diálogos
/// - Verifica `mounted` después de cada await antes de tocar la UI
mixin RunLifecycleMixin<T extends StatefulWidget> on State<T> {
  Future<RunLifecycleOutcome?> startRunSafely({
    required int runId,
  }) async {
    if (!mounted) return RunLifecycleOutcome.aborted;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Comenzar ruta'),
        content: const Text('¿Confirmas que iniciarás este viaje ahora?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
        ],
      ),
    );

    if (ok != true) return RunLifecycleOutcome.aborted;
    if (!mounted) return RunLifecycleOutcome.aborted;

    final dio = api.dio();
    await dio.patch('/service-runs/$runId/start');
    if (!mounted) return RunLifecycleOutcome.aborted;

    return RunLifecycleOutcome.started;
  }

  Future<RunLifecycleOutcome?> completeRunSafely({
    required int runId,
  }) async {
    if (!mounted) return RunLifecycleOutcome.aborted;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Completar viaje'),
        content: const Text('¿Confirmas que el viaje ha finalizado?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
        ],
      ),
    );

    if (ok != true) return RunLifecycleOutcome.aborted;
    if (!mounted) return RunLifecycleOutcome.aborted;

    final dio = api.dio();
    await dio.patch('/service-runs/$runId/complete');
    if (!mounted) return RunLifecycleOutcome.aborted;

    return RunLifecycleOutcome.completed;
  }
}

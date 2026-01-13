import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:tellevo/services/dio.dart' as api;

/// Resultado de la acción sobre el run.
enum RunActionOutcome { deleted, cancelled, aborted }

/// Mixin que evita usar `context` tras awaits si la vista ya no está montada.
/// También fuerza `useRootNavigator: true` en los diálogos.
mixin RunActionsMixin<T extends StatefulWidget> on State<T> {
  Future<RunActionOutcome?> deleteOrCancelRunSafely({
    required int runId,
  }) async {
    if (!mounted) return RunActionOutcome.aborted;

    // 1) Confirmación (root navigator para evitar context huérfano)
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: const Text(
          '¿Seguro que quieres cancelar este viaje?\n\n'
          'Si no tiene actividad se eliminará; de lo contrario se marcará como cancelado.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
        ],
      ),
    );

    if (confirmed != true) return RunActionOutcome.aborted;
    if (!mounted) return RunActionOutcome.aborted;

    // 2) Intentar borrar primero
    final dio = api.dio();
    try {
      await dio.delete('/service-runs/$runId');
      if (!mounted) return RunActionOutcome.aborted;
      return RunActionOutcome.deleted;
    } on DioException catch (e) {
      // 3) Si ya tiene actividad, backend debe responder 409 → cancelar
      if ((e.response?.statusCode ?? 0) == 409) {
        await dio.patch('/service-runs/$runId/cancel');
        if (!mounted) return RunActionOutcome.aborted;
        return RunActionOutcome.cancelled;
      }
      rethrow;
    }
  }
}

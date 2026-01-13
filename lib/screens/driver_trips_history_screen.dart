import 'package:dio/dio.dart' show Dio, DioException, Options;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/services/auth.dart';
import 'package:tellevo/services/dio.dart' as api;

class DriverTripsHistoryScreen extends StatefulWidget {
  const DriverTripsHistoryScreen({super.key});

  @override
  State<DriverTripsHistoryScreen> createState() =>
      _DriverTripsHistoryScreenState();
}

class _DriverTripsHistoryScreenState extends State<DriverTripsHistoryScreen> {
  bool _loading = true;
  String? _error;

  late Dio _client;
  String? _token;
  bool _initialized = false;

  List<Map<String, dynamic>> _trips = [];

  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _client = api.dio();
      _token = context.read<Auth>().token;
      _loadTrips();
      _initialized = true;
    }
  }

  Future<void> _loadTrips() async {
    _safeSet(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await _client.get(
        // ✅ Ajusta la ruta a tu backend
        '/driver/trips-history',
        options: Options(
          headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
        ),
      );

      final raw = resp.data;

      // Soporta:
      // { data: [...] }  o  { trips: [...] }  o  [...]
      List list;
      if (raw is Map && raw['data'] is List) {
        list = raw['data'] as List;
      } else if (raw is Map && raw['trips'] is List) {
        list = raw['trips'] as List;
      } else if (raw is List) {
        list = raw;
      } else {
        list = const [];
      }

      _safeSet(() {
        _trips = list.cast<Map<String, dynamic>>();
      });
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      _safeSet(() {
        _error = 'No se pudo cargar el historial (HTTP $status): $body';
      });
    } catch (e) {
      _safeSet(() {
        _error = 'No se pudo cargar el historial: $e';
      });
    } finally {
      _safeSet(() => _loading = false);
    }
  }

  String _formatDateFromYmd(String? ymd) {
    if (ymd == null || ymd.trim().isEmpty) return '--/--/----';
    // esperado: YYYY-MM-DD
    if (ymd.length >= 10) {
      final yyyy = ymd.substring(0, 4);
      final mm = ymd.substring(5, 7);
      final dd = ymd.substring(8, 10);
      return '$dd/$mm/$yyyy';
    }
    return ymd;
  }

  String _hhmmFromField(dynamic departureTimeField) {
    final raw = (departureTimeField ?? '').toString();
    if (raw.isEmpty) return '--:--';
    if (raw.length >= 5 && raw[2] == ':') return raw.substring(0, 5);
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '--:--';
    }
  }

  String _routeFromService(dynamic service) {
    final dir =
        (service is Map ? service['direction'] : null)
            ?.toString()
            .toUpperCase();
    return (dir == 'VUELTA' || dir == 'IDA') ? dir! : '—';
  }

  String _installationFromTrip(Map<String, dynamic> t) {
    // Te cubro varios formatos comunes:
    // installation_name directo, o installation: {name}, o service: {installation: {name}}
    final direct = t['installation_name']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;

    final inst = t['installation'];
    if (inst is Map && (inst['name']?.toString().isNotEmpty ?? false)) {
      return inst['name'].toString();
    }

    final service = t['service'];
    final inst2 = (service is Map) ? service['installation'] : null;
    if (inst2 is Map && (inst2['name']?.toString().isNotEmpty ?? false)) {
      return inst2['name'].toString();
    }

    return 'Instalación';
  }

  int _passengersCountFromTrip(Map<String, dynamic> t) {
    // soporta: passengers_count, o passengers: [...], o service_run_passengers: [...]
    final direct = t['passengers_count'];
    if (direct is int) return direct;
    if (direct is num) return direct.toInt();

    final p1 = t['passengers'];
    if (p1 is List) return p1.length;

    final p2 = t['service_run_passengers'];
    if (p2 is List) return p2.length;

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text(
          'Historial de Viajes',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadTrips,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTrips,
        child: Builder(
          builder: (_) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_error != null) {
              return _ErrorState(message: _error!, onRetry: _loadTrips);
            }

            if (_trips.isEmpty) {
              return const _EmptyState(msg: 'Aún no tienes viajes realizados.');
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _trips.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final t = _trips[i];

                // Campos típicos de un run:
                final date = _formatDateFromYmd(t['service_date']?.toString());
                final time = _hhmmFromField(t['departure_time']);
                final installation = _installationFromTrip(t);
                final route = _routeFromService(t['service']);
                final passengers = _passengersCountFromTrip(t);

                return _HistoryTripCard(
                  date: date,
                  installation: installation,
                  route: route,
                  time: time,
                  passengers: passengers,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// ---------- Card de viaje histórico ----------
class _HistoryTripCard extends StatelessWidget {
  const _HistoryTripCard({
    required this.date,
    required this.installation,
    required this.route,
    required this.time,
    required this.passengers,
  });

  final String date;
  final String installation;
  final String route;
  final String time;
  final int passengers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface,
        border: Border.all(color: scheme.outline.withOpacity(.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fecha + Hora
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 16),
              const SizedBox(width: 6),
              Text(date, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              const Icon(Icons.schedule_rounded, size: 16),
              const SizedBox(width: 4),
              Text(time, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),

          // Instalación
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  installation,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Ruta + pasajeros
          Row(
            children: [
              Icon(
                route == 'IDA'
                    ? Icons.north_east_rounded
                    : Icons.south_west_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                route,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              const Icon(Icons.people_rounded, size: 18),
              const SizedBox(width: 4),
              Text(
                '$passengers pasajeros',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.msg = 'No hay datos para mostrar'});
  final String msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 52, color: scheme.error),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

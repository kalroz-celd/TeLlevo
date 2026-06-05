import 'dart:convert';

import 'package:dio/dio.dart' show Dio, DioException, Options;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/screens/add_passengers_screen.dart';
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

  late DateTime _selectedMonth;
  List<Map<String, dynamic>> _allTrips = [];
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
      final now = DateTime.now();
      _selectedMonth = DateTime(now.year, now.month);
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
        '/driver/trips-history',
        queryParameters: {'month': _formatMonthForQuery(_selectedMonth)},
        options: Options(
          headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
        ),
      );

      final raw = resp.data;
      debugPrint(
        'driver/trips-history raw response: ${const JsonEncoder.withIndent('  ').convert(raw)}',
      );

      // Soporta respuestas planas y agrupadas por fecha:
      // { data: [...] }, { data: { '2026-06-01': [...] } }, { trips: [...] }, [...]
      List<dynamic> list;
      if (raw is Map) {
        if (raw['data'] is List) {
          list = raw['data'] as List;
        } else if (raw['data'] is Map) {
          list = _extractTripItems(raw['data'] as Map);
        } else if (raw['trips'] is List) {
          list = raw['trips'] as List;
        } else if (raw['trips'] is Map) {
          list = _extractTripItems(raw['trips'] as Map);
        } else {
          list = const [];
        }
      } else if (raw is List) {
        list = raw;
      } else {
        list = const [];
      }

      _safeSet(() {
        _allTrips = _normalizeTripList(list);
        _applyMonthFilter();
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

  List<dynamic> _extractTripItems(Map rawData) {
    final items = <dynamic>[];
    for (final value in rawData.values) {
      if (value is List) {
        items.addAll(value);
      } else if (value is Map) {
        items.addAll(_extractTripItems(value));
      } else if (value != null) {
        items.add(value);
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _normalizeTripList(List<dynamic> rawList) {
    final normalized = <Map<String, dynamic>>[];

    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        normalized.add(item);
      } else if (item is Map) {
        normalized.add(Map<String, dynamic>.from(item));
      } else if (item is List) {
        for (final child in item) {
          if (child is Map<String, dynamic>) {
            normalized.add(child);
          } else if (child is Map) {
            normalized.add(Map<String, dynamic>.from(child));
          }
        }
      }
    }

    return normalized;
  }

  DateTime _periodStartFor(DateTime month) {
    return DateTime(month.year, month.month - 1, 22);
  }

  DateTime _periodEndFor(DateTime month) {
    return DateTime(month.year, month.month, 21, 23, 59, 59, 999);
  }

  String _formatMonthForQuery(DateTime month) {
    final yyyy = month.year.toString().padLeft(4, '0');
    final mm = month.month.toString().padLeft(2, '0');
    return '$yyyy-$mm';
  }

  DateTime? _parseDate(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      if (raw.length >= 10) {
        final y = int.parse(raw.substring(0, 4));
        final m = int.parse(raw.substring(5, 7));
        final d = int.parse(raw.substring(8, 10));
        return DateTime(y, m, d);
      }
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  dynamic _dateValueFromTrip(Map<String, dynamic> trip) {
    for (final key in const [
      'service_date',
      'run_date',
      'travel_date',
      'trip_date',
      'date',
      'scheduled_date',
    ]) {
      final value = trip[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }

    final service = trip['service'];
    if (service is Map) {
      for (final key in const [
        'service_date',
        'run_date',
        'travel_date',
        'trip_date',
        'date',
        'scheduled_date',
      ]) {
        final value = service[key];
        if (value != null && value.toString().trim().isNotEmpty) return value;
      }
    }

    return null;
  }

  DateTime? _dateFromTrip(Map<String, dynamic> trip) {
    return _parseDate(_dateValueFromTrip(trip));
  }

  void _applyMonthFilter() {
    final start = _periodStartFor(_selectedMonth);
    final end = _periodEndFor(_selectedMonth);
    final hasReadableDates = _allTrips.any(
      (trip) => _dateFromTrip(trip) != null,
    );

    if (!hasReadableDates) {
      _trips = List<Map<String, dynamic>>.from(_allTrips);
      return;
    }

    _trips =
        _allTrips.where((trip) {
          final date = _dateFromTrip(trip);
          if (date == null) return false;
          return !date.isBefore(start) && !date.isAfter(end);
        }).toList();
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    await _loadTrips();
  }

  Future<void> _selectMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthPickerDialog(initialMonth: _selectedMonth),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
    });
    await _loadTrips();
  }

  String _monthName(int month) {
    const names = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return names[month - 1];
  }

  String _formatDateFromDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  String _selectedMonthLabel() {
    return '${_monthName(_selectedMonth.month)} ${_selectedMonth.year}';
  }

  String _selectedPeriodLabel() {
    final start = _periodStartFor(_selectedMonth);
    final end = _periodEndFor(_selectedMonth);
    return '${_formatDateFromDate(start)} al ${_formatDateFromDate(end)}';
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

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _directionFromTrip(Map<String, dynamic> t) {
    final service = t['service'];
    final dir =
        (service is Map ? service['direction'] : t['direction'])
            ?.toString()
            .toUpperCase();
    return (dir == 'VUELTA' || dir == 'IDA') ? dir! : '';
  }

  String _serviceText(
    Map<String, dynamic> service,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = service[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  ({double? startLat, double? startLng, double? endLat, double? endLng})
  _coordsFromService(Map<String, dynamic> service, String direction) {
    final rawStartLng = _asDouble(service['start_x_coord']);
    final rawStartLat = _asDouble(service['start_y_coord']);
    final rawEndLng = _asDouble(service['end_x_coord']);
    final rawEndLat = _asDouble(service['end_y_coord']);

    if (direction.toLowerCase() == 'vuelta') {
      return (
        startLat: rawEndLat,
        startLng: rawEndLng,
        endLat: rawStartLat,
        endLng: rawStartLng,
      );
    }
    return (
      startLat: rawStartLat,
      startLng: rawStartLng,
      endLat: rawEndLat,
      endLng: rawEndLng,
    );
  }

  Future<void> _openPassengersForTrip(Map<String, dynamic> trip) async {
    final serviceRaw = trip['service'];
    final service =
        serviceRaw is Map<String, dynamic>
            ? serviceRaw
            : serviceRaw is Map
            ? Map<String, dynamic>.from(serviceRaw)
            : <String, dynamic>{};
    final direction = _directionFromTrip(trip);
    final coords = _coordsFromService(service, direction);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddPassengersScreen(
              run: trip,
              installationName: _installationFromTrip(trip),
              direction: direction,
              startName: _serviceText(service, const [
                'start_location',
                'start_name',
                'origin',
              ], 'Inicio'),
              endName: _serviceText(service, const [
                'end_location',
                'end_name',
                'destination',
              ], 'Destino'),
              startLat: coords.startLat,
              startLng: coords.startLng,
              endLat: coords.endLat,
              endLng: coords.endLng,
              serviceDate: trip['service_date']?.toString(),
            ),
      ),
    );

    if (!mounted) return;
    await _loadTrips();
  }

  @override
  Widget build(BuildContext context) {
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

            return Column(
              children: [
                _MonthSelector(
                  monthLabel: _selectedMonthLabel(),
                  periodLabel: _selectedPeriodLabel(),
                  onPrevious: () => _changeMonth(-1),
                  onNext: () => _changeMonth(1),
                  onSelect: _selectMonth,
                ),
                Expanded(
                  child:
                      _trips.isEmpty
                          ? const _EmptyState(
                            msg: 'No tienes viajes realizados en este periodo.',
                          )
                          : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _trips.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final t = _trips[i];

                              // Campos típicos de un run:
                              final date = _formatDateFromYmd(
                                _dateValueFromTrip(t)?.toString(),
                              );
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
                                onTap: () => _openPassengersForTrip(t),
                              );
                            },
                          ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ---------- Card de viaje histórico ----------
class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.monthLabel,
    required this.periodLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final String monthLabel;
  final String periodLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outline.withOpacity(.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Mes anterior',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        monthLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        periodLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Mes siguiente',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialMonth.year;
  }

  String _monthName(int month) {
    const names = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return names[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Seleccionar mes'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Ano anterior',
                  onPressed: () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    _year.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ano siguiente',
                  onPressed: () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.4,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final selected =
                    _year == widget.initialMonth.year &&
                    month == widget.initialMonth.month;
                return OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor:
                        selected ? scheme.primaryContainer : scheme.surface,
                    foregroundColor:
                        selected ? scheme.onPrimaryContainer : scheme.onSurface,
                    side: BorderSide(
                      color:
                          selected
                              ? scheme.primary
                              : scheme.outline.withOpacity(.35),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context, DateTime(_year, month));
                  },
                  child: Text(
                    _monthName(month),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _HistoryTripCard extends StatelessWidget {
  const _HistoryTripCard({
    required this.date,
    required this.installation,
    required this.route,
    required this.time,
    required this.passengers,
    required this.onTap,
  });

  final String date;
  final String installation;
  final String route;
  final String time;
  final int passengers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      shadowColor: Colors.black.withOpacity(.05),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
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
                  Text(
                    date,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const Icon(Icons.schedule_rounded, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    time,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
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
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
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

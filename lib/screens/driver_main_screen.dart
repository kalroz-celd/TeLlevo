import 'package:dio/dio.dart' show Dio, DioException, Options;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tellevo/core/app_colors.dart';
import 'package:tellevo/services/auth.dart';
import 'package:tellevo/services/dio.dart' as api;
import 'add_passengers_screen.dart';
import 'driver_trips_history_screen.dart';

class DriverMainScreen extends StatefulWidget {
  const DriverMainScreen({super.key});

  @override
  State<DriverMainScreen> createState() => _DriverMainScreenState();
}

enum DriverStep { installation, service, schedule }

class _DriverMainScreenState extends State<DriverMainScreen> {
  bool _loading = true;
  String? _error;

  // Paso actual
  DriverStep _step = DriverStep.installation;

  // Datos
  List<Map<String, dynamic>> _installations = [];
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _schedules = [];

  // Selecciones
  Map<String, dynamic>? _selectedInstallation;
  Map<String, dynamic>? _selectedService;
  Map<String, dynamic>? _selectedSchedule;
  DateTime _selectedDate = DateTime.now();

  // Cache: serviceId -> schedules fusionados con runs (para mostrar hints)
  final Map<int, List<Map<String, dynamic>>> _schedulesByService = {};

  // Cliente HTTP + token (sin usar context en helpers async)
  late Dio _client;
  String? _token;
  bool _initialized = false;

  void _safeSet(void Function() fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    // _client y _token se inicializan en didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _client = api.dio();
      _token = context.read<Auth>().token;
      _loadInstallations();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _onLogout() async {
    final auth = context.read<Auth>();
    await auth.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  String _dateParam(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<List<Map<String, dynamic>>> _fetchSchedulesForService(
    int serviceId,
    DateTime date,
  ) async {
    final resp = await _client.get(
      '/services/$serviceId/schedules',
      queryParameters: {'date': _dateParam(date)},
      options: Options(
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
      ),
    );

    final body = resp.data;
    if (body is Map && body['schedules'] is List) {
      return (body['schedules'] as List).cast<Map<String, dynamic>>();
    }
    final raw = resp.data;
    final list = (raw is Map && raw['data'] is List) ? raw['data'] : raw;
    return (list as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _ensureRunsForService(
    int serviceId,
    DateTime date,
  ) async {
    final resp = await _client.post(
      '/services/$serviceId/runs/ensure',
      queryParameters: {'date': _dateParam(date)},
      options: Options(
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
      ),
    );

    final body = resp.data;
    if (body is Map && body['runs'] is List) {
      return (body['runs'] as List).cast<Map<String, dynamic>>();
    }
    final raw = resp.data;
    final list = (raw is Map && raw['data'] is List) ? raw['data'] : raw;
    return (list as List).cast<Map<String, dynamic>>();
  }

  /// 🔴 NUEVO: endpoint para obtener/crear un run propio para este conductor
  Future<Map<String, dynamic>> _claimRunForDriver({
    required int serviceId,
    required int scheduleId,
    required DateTime date,
  }) async {
    final resp = await _client.post(
      '/services/$serviceId/runs/claim-for-driver',
      // Puedes usar data o queryParameters según cómo lo definas en Laravel
      data: {
        'service_schedule_id': scheduleId,
        'service_date': _dateParam(date),
      },
      options: Options(
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
      ),
    );

    final data = resp.data;
    if (data is Map && data['run'] is Map) {
      return (data['run'] as Map).cast<String, dynamic>();
    }
    // Si el backend devuelve el run directo
    return (data as Map).cast<String, dynamic>();
  }

  Future<void> _loadInstallations() async {
    _safeSet(() {
      _loading = true;
      _error = null;
      _step = DriverStep.installation;
      _selectedInstallation = null;
      _selectedService = null;
      _selectedSchedule = null;
      _services = [];
      _schedules = [];
      _schedulesByService.clear();
    });

    try {
      final resp = await _client.get(
        '/driver/installations',
        options: Options(
          headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
        ),
      );

      if (!mounted) return;

      final raw = resp.data;
      final list = (raw is Map && raw['data'] is List) ? raw['data'] : raw;
      final data = (list as List).cast<Map<String, dynamic>>();

      _safeSet(() => _installations = data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (!mounted) return;
      _safeSet(
        () =>
            _error =
                'No se pudieron cargar las instalaciones (HTTP $status): $body',
      );
    } catch (e) {
      if (!mounted) return;
      _safeSet(() => _error = 'No se pudieron cargar las instalaciones: $e');
    } finally {
      if (!mounted) return;
      _safeSet(() => _loading = false);
    }
  }

  Future<void> _selectInstallation(Map<String, dynamic> inst) async {
    if (!mounted) return;
    _safeSet(() {
      _selectedInstallation = inst;
      _selectedService = null;
      _selectedSchedule = null;
      _services = [];
      _schedules = [];
      _step = DriverStep.service;
    });

    final embed =
        (inst['services'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _safeSet(() => _services = embed);

    if (embed.isEmpty) return;

    // Precargar schedules fusionados por cada servicio (fecha seleccionada)
    try {
      final futures = <Future<void>>[];
      for (final s in embed) {
        final sid = int.tryParse('${s['id']}');
        if (sid == null) continue;

        futures.add(() async {
          try {
            final schedules = await _fetchSchedulesForService(
              sid,
              _selectedDate,
            );
            final runs = await _ensureRunsForService(sid, _selectedDate);
            final fused = _mergeSchedulesWithRuns(schedules, runs);
            if (!mounted) return;
            _safeSet(() {
              _schedulesByService[sid] = fused;
            });
          } catch (_) {
            if (!mounted) return;
            _safeSet(() {
              _schedulesByService[sid] = const [];
            });
          }
        }());
      }
      await Future.wait(futures);
      if (!mounted) return;
    } catch (_) {
      /* vista sigue */
    }
  }

  Future<void> _selectService(Map<String, dynamic> service) async {
    _safeSet(() {
      _selectedService = service;
      _selectedSchedule = null;
      _schedules = [];
      _loading = true;
      _error = null;
    });

    final sid = int.tryParse('${service['id']}') ?? -1;

    // Cache inmediato (solo para mostrar horarios)
    final cached = _schedulesByService[sid];
    if (cached != null) {
      _safeSet(() {
        _schedules = cached;
        _step = DriverStep.schedule;
      });
    }

    // Refresco con fusión schedules + runs/ensure
    try {
      final schedules = await _fetchSchedulesForService(sid, _selectedDate);
      final runs = await _ensureRunsForService(sid, _selectedDate);
      final fused = _mergeSchedulesWithRuns(schedules, runs);

      if (!mounted) return;
      _safeSet(() {
        _schedulesByService[sid] = fused;
        _schedules = fused;
        _step = DriverStep.schedule;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (cached == null) {
        final status = e.response?.statusCode;
        final body = e.response?.data;
        _safeSet(
          () => _error = 'No se pudieron cargar horarios (HTTP $status): $body',
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (cached == null) {
        _safeSet(() => _error = 'No se pudieron cargar horarios: $e');
      }
    } finally {
      if (!mounted) return;
      _safeSet(() => _loading = false);
    }
  }

  /// ---- Helpers ----

  List<Map<String, dynamic>> _mergeSchedulesWithRuns(
    List<Map<String, dynamic>> schedules,
    List<Map<String, dynamic>> runs,
  ) {
    final byScheduleId = <String, List<Map<String, dynamic>>>{};
    final byTimeHHmm = <String, List<Map<String, dynamic>>>{};

    for (final r in runs) {
      final schId = '${r['service_schedule_id']}';
      (byScheduleId[schId] ??= []).add(r);

      final hhmm = _hhmmLocalFromField(r['departure_time']);
      if (hhmm != '--:--') (byTimeHHmm[hhmm] ??= []).add(r);
    }

    return schedules.map((s) {
      final map = Map<String, dynamic>.from(s);
      final schId = '${s['id']}';
      final time = _hhmmLocalFromField(s['departure_time']);

      final byIdMatches = byScheduleId[schId] ?? const [];
      final byTimeMatches =
          time != '--:--' ? (byTimeHHmm[time] ?? const []) : const [];

      final seen = <String>{};
      final mergedRuns = <Map<String, dynamic>>[];
      for (final r in [...byIdMatches, ...byTimeMatches]) {
        final id = '${r['id']}';
        if (seen.add(id)) mergedRuns.add(r);
      }

      map['_runs_for_this_schedule'] = mergedRuns;
      if (mergedRuns.isNotEmpty) {
        map['sequence_no'] = mergedRuns.first['sequence_no'];
        map['run_id'] = mergedRuns.first['id'];
      }
      return map;
    }).toList();
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  ({double? startLat, double? startLng, double? endLat, double? endLng})
  _coordsFromSelectedService() {
    final s = _selectedService ?? const {};
    final dir = (s['direction'] ?? '').toString().toLowerCase();

    final rawStartLng = _asDouble(s['start_x_coord']);
    final rawStartLat = _asDouble(s['start_y_coord']);
    final rawEndLng = _asDouble(s['end_x_coord']);
    final rawEndLat = _asDouble(s['end_y_coord']);

    if (dir == 'vuelta') {
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

  /// Abre un run propio para este conductor usando el endpoint claim-for-driver
  Future<void> _openRunForSchedule(
    int serviceId,
    Map<String, dynamic> schedule,
  ) async {
    final scheduleId = int.tryParse('${schedule['id']}');
    if (scheduleId == null) return;

    try {
      final run = await _claimRunForDriver(
        serviceId: serviceId,
        scheduleId: scheduleId,
        date: _selectedDate,
      );
      if (!mounted) return;
      await _goToAddPassengersWithRun(run);
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      final body = e.response?.data;
      _safeSet(
        () =>
            _error =
                'No se pudo asignar un viaje para este horario (HTTP $status): $body',
      );
    } catch (e) {
      if (!mounted) return;
      _safeSet(
        () => _error = 'No se pudo asignar un viaje para este horario: $e',
      );
    }
  }

  Future<void> _goToAddPassengersWithRun(Map<String, dynamic> run) async {
    final startName = (_selectedService?['start_location'] ?? '').toString();
    final endName = (_selectedService?['end_location'] ?? '').toString();
    final coords = _coordsFromSelectedService();

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddPassengersScreen(
              run: run,
              installationName: _selectedInstallation?['name'] ?? 'Instalación',
              direction:
                  (_selectedService?['direction'] ?? '')
                      .toString()
                      .toUpperCase(),
              startName: startName.isNotEmpty ? startName : 'Inicio',
              endName: endName.isNotEmpty ? endName : 'Destino',
              startLat: coords.startLat,
              startLng: coords.startLng,
              endLat: coords.endLat,
              endLng: coords.endLng,
            ),
      ),
    );

    if (!mounted) return;
    _loadInstallations();
  }

  String _hhmmLocalFromField(dynamic departureTimeField) {
    final raw = (departureTimeField ?? '').toString();
    if (raw.isEmpty) return '--:--';
    final hhmm = raw.length >= 5 && raw[2] == ':' ? raw.substring(0, 5) : null;
    if (hhmm != null) return hhmm;
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '--:--';
    }
  }

  List<String> _mergeTimesFromSchedules(List<Map<String, dynamic>> schedules) {
    final set = <String>{};
    for (final sch in schedules) {
      set.add(_hhmmLocalFromField(sch['departure_time']));
    }
    final list = set.where((t) => t != '--:--').toList();
    list.sort((a, b) {
      final ah = int.tryParse(a.substring(0, 2)) ?? 0;
      final am = int.tryParse(a.substring(3, 5)) ?? 0;
      final bh = int.tryParse(b.substring(0, 2)) ?? 0;
      final bm = int.tryParse(b.substring(3, 5)) ?? 0;
      if (ah != bh) return ah.compareTo(bh);
      return am.compareTo(bm);
    });
    return list;
  }

  void _goBackStep() {
    if (_step == DriverStep.schedule) {
      _safeSet(() {
        _step = DriverStep.service;
        _selectedSchedule = null;
        _schedules = [];
      });
    } else if (_step == DriverStep.service) {
      _safeSet(() {
        _step = DriverStep.installation;
        _selectedService = null;
        _selectedSchedule = null;
        _services = [];
        _schedules = [];
      });
    }
  }

  String _stepTitle() {
    switch (_step) {
      case DriverStep.installation:
        return 'Selecciona una instalación';
      case DriverStep.service:
        return 'Selecciona un servicio';
      case DriverStep.schedule:
        return 'Selecciona un horario';
    }
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  void _goToTripsHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverTripsHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<Auth>();
    final user = auth.user;
    final scheme = Theme.of(context).colorScheme;
    final avatar = auth.avatarUrl();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF4F7FB), Color(0xFFE8EDF4)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _goToTripsHistory,
                icon: const Icon(Icons.history_rounded),
                label: const Text(
                  'Historial de viajes',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
              ),
            ),
          ),
        ),
        body: WillPopScope(
          onWillPop: () async {
            if (_step == DriverStep.installation) return true;
            _goBackStep();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: _loadInstallations,
            child: CustomScrollView(
              slivers: [
                // Header degradado + Logout
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      Container(
                        height: 240,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                'assets/images/van_login.png',
                                fit: BoxFit.cover,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.primary.withOpacity(.65),
                                      Colors.black.withOpacity(.35),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Avatar
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 38,
                                  backgroundColor: Colors.white.withOpacity(
                                    .15,
                                  ),
                                  child:
                                      (avatar == null)
                                          ? const Icon(
                                            Icons.person_rounded,
                                            color: Colors.white,
                                            size: 38,
                                          )
                                          : ClipOval(
                                            child: Image.network(
                                              avatar,
                                              width: 76,
                                              height: 76,
                                              fit: BoxFit.cover,
                                              headers: auth.imageAuthHeaders(),
                                            ),
                                          ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Nombre + chips
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.name.isNotEmpty
                                          ? 'Hola, ${user.name.split(' ').first}'
                                          : 'Hola, Conductor',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 22,
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        const _HeaderPill(
                                          icon: Icons.badge_rounded,
                                          label: 'Rol: Conductor',
                                        ),
                                        _HeaderPill(
                                          icon: Icons.calendar_today_rounded,
                                          label: _formatDate(_selectedDate),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Botón salir
                              SizedBox(
                                height: 40,
                                child: OutlinedButton.icon(
                                  onPressed: _onLogout,
                                  icon: const Icon(
                                    Icons.logout_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Salir',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Colors.white70,
                                    ),
                                    shape: const StadiumBorder(),
                                    backgroundColor: Colors.white.withOpacity(
                                      .12,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Tarjeta flotante con título y refresh
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -20),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Card(
                        elevation: 2,
                        color: scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: scheme.outline.withOpacity(.25),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              if (_step != DriverStep.installation) ...[
                                IconButton(
                                  tooltip: 'Atrás',
                                  onPressed: _goBackStep,
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                const SizedBox(width: 6),
                              ] else ...[
                                const Icon(Icons.location_on_rounded),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  _stepTitle(),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                onPressed: _loadInstallations,
                                icon: const Icon(Icons.refresh_rounded),
                                tooltip: 'Actualizar',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Contenido
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(
                      message: _error!,
                      onRetry: _loadInstallations,
                    ),
                  )
                else
                  switch (_step) {
                    DriverStep.installation => SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver:
                          _installations.isEmpty
                              ? const SliverFillRemaining(
                                hasScrollBody: false,
                                child: _EmptyState(
                                  msg:
                                      'No hay instalaciones disponibles por ahora',
                                ),
                              )
                              : SliverGrid(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  i,
                                ) {
                                  final inst = _installations[i];
                                  final name = inst['name'] ?? 'Instalación';
                                  final services =
                                      (inst['services'] as List?) ?? [];
                                  final subtitle =
                                      '${services.length} servicios';

                                  return _InstallCard(
                                    title: name,
                                    subtitle: subtitle,
                                    icon: Icons.location_on_rounded,
                                    onTap: () => _selectInstallation(inst),
                                    subtitleMaxLines: 1,
                                  );
                                }, childCount: _installations.length),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 1.05,
                                    ),
                              ),
                    ),

                    DriverStep.service => SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver:
                          _services.isEmpty
                              ? const SliverFillRemaining(
                                hasScrollBody: false,
                                child: _EmptyState(
                                  msg: 'No hay servicios para esta instalación',
                                ),
                              )
                              : SliverList.builder(
                                itemCount: _services.length,
                                itemBuilder: (context, index) {
                                  final s = _services[index];
                                  final dir =
                                      (s['direction'] ?? '')
                                          .toString()
                                          .toUpperCase();

                                  final start =
                                      (s['start_location'] ?? '').toString();
                                  final end =
                                      (s['end_location'] ?? '').toString();

                                  final sid = int.tryParse('${s['id']}') ?? -1;
                                  final schList =
                                      _schedulesByService[sid] ?? const [];
                                  final merged = _mergeTimesFromSchedules(
                                    schList,
                                  );
                                  final timesText =
                                      merged.isEmpty
                                          ? 'Sin horarios'
                                          : merged.join(' • ');

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _InstallCard(
                                      icon:
                                          dir == 'IDA'
                                              ? Icons.north_east_rounded
                                              : Icons.south_west_rounded,
                                      title: dir,
                                      subtitle: '$start → $end\n$timesText',
                                      onTap: () => _selectService(s),
                                      subtitleMaxLines: 2,
                                    ),
                                  );
                                },
                              ),
                    ),

                    DriverStep.schedule => SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Fecha: ',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  _formatDate(_selectedDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_schedules.isEmpty)
                              const _EmptyState(
                                msg:
                                    'No hay horarios configurados para esta fecha',
                              )
                            else
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children:
                                    _schedules.map((sch) {
                                      final time = (sch['departure_time'] ?? '')
                                          .toString()
                                          .substring(0, 5);
                                      return ChoiceChip(
                                        label: Text(time),
                                        selected:
                                            _selectedSchedule?['id'] ==
                                            sch['id'],
                                        onSelected: (_) async {
                                          _safeSet(
                                            () => _selectedSchedule = sch,
                                          );
                                          final sid = int.tryParse(
                                            '${_selectedService?['id']}',
                                          );
                                          if (sid != null) {
                                            await _openRunForSchedule(sid, sch);
                                          }
                                        },
                                      );
                                    }).toList(),
                              ),
                            if (_selectedSchedule == null &&
                                _schedules.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  'Toca un horario para gestionar tu viaje',
                                  style: TextStyle(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  },

                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------- Card reutilizable tipo “opción” ----------
class _InstallCard extends StatelessWidget {
  const _InstallCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.place_rounded,
    this.subtitleMaxLines = 2,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData icon;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outline.withOpacity(.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.surface, scheme.surface.withOpacity(.92)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 140),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withOpacity(.9),
                              scheme.primary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withOpacity(.4),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.route_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
              Icons.info_outline_rounded,
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

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

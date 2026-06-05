import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tellevo/screens/route_map_screen.dart';
import 'package:tellevo/screens/qr_scan_screen.dart';
import 'package:tellevo/models/passenger_email_api.dart';
import 'package:tellevo/services/auth.dart';
import 'package:dio/dio.dart' show Dio, DioException, CancelToken, Options;
import 'package:provider/provider.dart';
import 'package:tellevo/services/dio.dart' as api;
import 'package:shared_preferences/shared_preferences.dart';

// ==== Timezone (IANA) ====
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class AddPassengersScreen extends StatefulWidget {
  const AddPassengersScreen({
    super.key,
    required this.run,
    required this.installationName,
    required this.direction,
    required this.startName,
    required this.endName,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.defaultTo,
    this.serviceDate,
  });

  final Map<String, dynamic> run;
  final String installationName;
  final String direction;
  final String startName;
  final String endName;

  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;

  final dynamic defaultTo;
  final String? serviceDate;

  @override
  State<AddPassengersScreen> createState() => _AddPassengersScreenState();
}

class _AddPassengersScreenState extends State<AddPassengersScreen> {
  final List<Map<String, String>> _rows = [];

  // Override de hora local por pasajero al escanear (clave: user_id o RUT)
  final Map<String, String> _localScanTimeByKey = {};

  // === Cache: NO usar context en helpers async ===
  late final Dio _client;
  late final String? _token;
  late final PassengerEmailApi _emailApi;

  bool _sending = false;
  bool _busyLifecycle = false;

  // ✅ Estado visual persistente de envío de correo
  tz.TZDateTime? _emailSentAtChile;
  String? _emailSentMsg;

  // CancelTokens para abortar requests si se cierra la pantalla
  CancelToken? _emailCancel;
  CancelToken? _reloadCancel;
  CancelToken? _checkinCancel;
  CancelToken? _lifecycleCancel;

  String _status = 'scheduled';

  // TZ Chile
  late final tz.Location _chileLoc;

  @override
  void initState() {
    super.initState();

    // Inicializa zonas y fija Chile
    tzdata.initializeTimeZones();
    _chileLoc = tz.getLocation('America/Santiago');

    // Cacheamos cliente y token una sola vez
    _client = api.dio();
    _token = context.read<Auth>().token;
    _emailApi = PassengerEmailApi(bearerToken: _token ?? '');

    _status = (widget.run['status'] ?? 'scheduled').toString();
    _reloadPassengers();

    // ✅ Cargar indicador persistido (si existe)
    _loadEmailSentState();
  }

  @override
  void dispose() {
    _emailCancel?.cancel('screen disposed');
    _reloadCancel?.cancel('screen disposed');
    _checkinCancel?.cancel('screen disposed');
    _lifecycleCancel?.cancel('screen disposed');
    super.dispose();
  }

  // ================= Helpers =================

  void maybeSnack(String msg) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.maybeOf(context);
    if (sm == null) return;
    sm.clearSnackBars();
    sm.showSnackBar(SnackBar(content: Text(msg)));
  }

  void safeSet(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String? _ymdFromValue(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
      return null;
    }

    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)) {
      return value.substring(0, 10);
    }

    try {
      final parsed = DateTime.parse(value);
      final cl = tz.TZDateTime.from(parsed, _chileLoc);
      final yyyy = cl.year.toString().padLeft(4, '0');
      final mm = cl.month.toString().padLeft(2, '0');
      final dd = cl.day.toString().padLeft(2, '0');
      return '$yyyy-$mm-$dd';
    } catch (_) {
      return null;
    }
  }

  String _runDateYmd() {
    final explicitDate = _ymdFromValue(widget.serviceDate);
    if (explicitDate != null) return explicitDate;

    for (final key in const [
      'service_date',
      'run_date',
      'date',
      'scheduled_date',
      'completed_at',
      'started_at',
      'created_at',
    ]) {
      final ymd = _ymdFromValue(widget.run[key]);
      if (ymd != null) return ymd;
    }

    final service = widget.run['service'];
    if (service is Map) {
      for (final key in const ['service_date', 'date', 'scheduled_date']) {
        final ymd = _ymdFromValue(service[key]);
        if (ymd != null) return ymd;
      }
    }

    final nowCl = tz.TZDateTime.now(_chileLoc);
    final yyyy = nowCl.year.toString().padLeft(4, '0');
    final mm = nowCl.month.toString().padLeft(2, '0');
    final dd = nowCl.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  String _runDateDdMmYyyy() {
    final ymd = _runDateYmd();
    return '${ymd.substring(8, 10)}/${ymd.substring(5, 7)}/${ymd.substring(0, 4)}';
  }

  // ¿La cadena ISO trae zona explícita? (Z o ±hh:mm al final)
  String _dateTimeForReport(String ymd, String? hhmm) {
    final time = (hhmm ?? '').trim();
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(time)) return ymd;
    return '$ymd $time:00';
  }

  bool _hasTzOffset(String s) {
    return RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(s.trim());
  }

  // Extrae componentes Y-M-D H:M:S(.ms) de una cadena sin zona (o HH:mm)
  ({int y, int m, int d, int hh, int mm, int ss, int ms}) _ymdHmsFromLoose(
    String s,
  ) {
    final re = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?(?:\.(\d{1,3}))?$',
    );
    final m = re.firstMatch(s.trim());
    if (m == null) {
      // fallback: solo HH:mm
      final reHm = RegExp(r'^(\d{2}):(\d{2})$');
      final mh = reHm.firstMatch(s.trim());
      final now = tz.TZDateTime.now(_chileLoc);
      if (mh != null) {
        final hh = int.tryParse(mh.group(1)!) ?? 0;
        final mm = int.tryParse(mh.group(2)!) ?? 0;
        return (
          y: now.year,
          m: now.month,
          d: now.day,
          hh: hh,
          mm: mm,
          ss: 0,
          ms: 0,
        );
      }
      // si no matchea nada, usa ahora
      return (
        y: now.year,
        m: now.month,
        d: now.day,
        hh: now.hour,
        mm: now.minute,
        ss: now.second,
        ms: now.millisecond,
      );
    }
    int p(int i) => int.tryParse(m.group(i)!) ?? 0;
    final ms = m.group(7);
    return (
      y: p(1),
      m: p(2),
      d: p(3),
      hh: p(4),
      mm: p(5),
      ss: p(6),
      ms: ms == null ? 0 : int.tryParse(ms.padRight(3, '0')) ?? 0,
    );
  }

  // Convierte string temporal a HH:mm "Chile".
  // - Si trae zona (Z/±hh:mm): parseo y convierto a America/Santiago
  // - Si NO trae zona: lo interpreto como hora local de Chile
  String _toChileHhmm(String raw) {
    final s = (raw).toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';
    try {
      if (_hasTzOffset(s)) {
        final dt = DateTime.parse(s);
        final cl = tz.TZDateTime.from(dt, _chileLoc);
        final hh = cl.hour.toString().padLeft(2, '0');
        final mm = cl.minute.toString().padLeft(2, '0');
        return '$hh:$mm';
      } else {
        final c = _ymdHmsFromLoose(s);
        final cl = tz.TZDateTime(
          _chileLoc,
          c.y,
          c.m,
          c.d,
          c.hh,
          c.mm,
          c.ss,
          c.ms,
        );
        final hh = cl.hour.toString().padLeft(2, '0');
        final mm = cl.minute.toString().padLeft(2, '0');
        return '$hh:$mm';
      }
    } catch (_) {
      return s.length >= 16
          ? s.substring(11, 16)
          : (s.length >= 5 ? s.substring(0, 5) : '');
    }
  }

  // "Ahora" en Chile, HH:mm
  String _nowHhmmChile() {
    final nowCl = tz.TZDateTime.now(_chileLoc);
    final hh = nowCl.hour.toString().padLeft(2, '0');
    final mm = nowCl.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _fmtChileHhmm(tz.TZDateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  String get _statusLabel {
    switch (_status) {
      case 'in_progress':
        return 'En progreso';
      case 'completed':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      case 'scheduled':
      default:
        return 'Programado';
    }
  }

  Color get _statusColor {
    switch (_status) {
      case 'in_progress':
        return Colors.orange.shade700;
      case 'completed':
        return Colors.green.shade700;
      case 'cancelled':
        return Colors.grey.shade600;
      case 'scheduled':
      default:
        return Colors.blue.shade700;
    }
  }

  // ================= Persistencia indicador email =================

  String _emailPrefsKey(int runId) =>
      'tellevo_run_${runId}_email_sent_at_utc_ms';

  Future<void> _loadEmailSentState() async {
    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_emailPrefsKey(runId));
    if (ms == null) return;

    final dtUtc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    final dtChile = tz.TZDateTime.from(dtUtc, _chileLoc);

    if (!mounted) return;
    safeSet(() {
      _emailSentAtChile = dtChile;
      _emailSentMsg = 'Correo enviado ✅';
    });
  }

  Future<void> _persistEmailSentState() async {
    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await prefs.setInt(_emailPrefsKey(runId), nowUtcMs);
  }

  // (Opcional) por si quieres limpiar manualmente
  Future<void> _clearEmailSentState() async {
    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailPrefsKey(runId));

    if (!mounted) return;
    safeSet(() {
      _emailSentAtChile = null;
      _emailSentMsg = null;
    });
  }

  // ================= UI: Indicador (cuadro celeste) =================

  Widget _emailIndicatorChip() {
    final msg = _emailSentMsg;
    if (msg == null) return const SizedBox.shrink();

    final ok = msg == 'Correo enviado ✅';
    final when =
        _emailSentAtChile == null
            ? ''
            : ' (${_fmtChileHhmm(_emailSentAtChile!)})';
    final text = '$msg$when';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE6F4EA) : const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? const Color(0xFF34A853) : const Color(0xFFEA4335),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error,
            size: 16,
            color: ok ? const Color(0xFF34A853) : const Color(0xFFEA4335),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: ok ? const Color(0xFF1E7E34) : const Color(0xFFB3261E),
            ),
          ),
        ],
      ),
    );
  }

  // ================= Acciones =================

  Future<void> _scanQr() async {
    if (!mounted) return;

    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) {
      maybeSnack('ID de run inválido o ausente.');
      return;
    }

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder:
            (_) => QrScanScreen(runId: runId, askSeat: false, askNotes: false),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;

    final qrRaw =
        (result?['qr'] ??
                result?['raw'] ??
                result?['code'] ??
                result?['text'] ??
                result?['content'] ??
                result?['value'] ??
                result?['data'] ??
                '')
            .toString()
            .trim();

    if (qrRaw.isEmpty) {
      maybeSnack('QR vacío o inválido.');
      return;
    }

    final payload = _payloadFromTellevoQr(qrRaw);
    if (payload.isEmpty) {
      maybeSnack(
        'QR inválido: no es un QR de Tellevo (tellevo_passenger / tellevo.passenger).',
      );
      return;
    }

    _checkinCancel?.cancel();
    _checkinCancel = CancelToken();

    try {
      await _client.post(
        '/service-runs/$runId/passengers/check-in',
        data: payload,
        cancelToken: _checkinCancel,
        options: Options(
          headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
        ),
      );
      if (!mounted) return;

      final key = _passengerKeyFromPayload(payload);
      if (key != null) {
        _localScanTimeByKey[key] = _nowHhmmChile();
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final backend = e.response?.data;
      final msg =
          (backend is Map)
              ? (backend['message'] ?? backend['error'] ?? backend.toString())
              : backend?.toString();
      maybeSnack(
        'No se pudo registrar (${code ?? '---'}): ${msg ?? e.message}',
      );
      return;
    } catch (e) {
      maybeSnack('Error al registrar: $e');
      return;
    }

    await _reloadPassengers();
    if (!mounted) return;
    maybeSnack('Pasajero registrado ✅');
  }

  /// Acepta:
  /// { "type": "tellevo_passenger" | "tellevo.passenger", "user_id":123, "rut":"12345678-K", "name":"..." }
  Map<String, dynamic> _payloadFromTellevoQr(String qrRaw) {
    try {
      final obj = json.decode(qrRaw);
      if (obj is Map) {
        final m = obj.map((k, v) => MapEntry(k.toString().toLowerCase(), v));
        final type = (m['type'] ?? '').toString().toLowerCase();
        if (type == 'tellevo_passenger' || type == 'tellevo.passenger') {
          final idStr = (m['user_id'] ?? m['userid'] ?? m['id'])?.toString();
          final rut = (m['rut'] ?? '').toString();
          final name = (m['name'] ?? m['full_name'] ?? m['nombre'])?.toString();

          final out = <String, dynamic>{'source': 'scan'};
          if (idStr != null && RegExp(r'^\d+$').hasMatch(idStr)) {
            out['user_id'] = int.parse(idStr);
          }
          if (rut.isNotEmpty) {
            out['rut'] = rut.replaceAll('.', '').toUpperCase();
          }
          if (name != null && name.isNotEmpty) {
            out['name'] = name;
          }
          if (out.containsKey('user_id') || out.containsKey('rut')) {
            return out;
          }
        }
      }
    } catch (_) {}
    return {};
  }

  String? _passengerKeyFromPayload(Map<String, dynamic> payload) {
    if (payload['user_id'] != null) return '${payload['user_id']}';
    final rut = (payload['rut'] ?? '').toString().trim().toUpperCase();
    if (rut.isNotEmpty) return rut;
    return null;
  }

  String? _passengerKeyFromUser(Map<String, dynamic> user) {
    final id = user['id'];
    if (id != null) return '$id';
    final ci = (user['ci'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final dv = (user['digit'] ?? '').toString().toUpperCase();
    final rut = (ci.isNotEmpty && dv.isNotEmpty) ? '$ci-$dv' : '';
    return rut.isNotEmpty ? rut : null;
  }

  Future<void> _reloadPassengers() async {
    if (!mounted) return;

    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) {
      maybeSnack('runId inválido');
      return;
    }

    _reloadCancel?.cancel();
    _reloadCancel = CancelToken();

    try {
      final res = await _client.get(
        '/service-runs/$runId/passengers',
        cancelToken: _reloadCancel,
        options: Options(
          headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
        ),
      );

      if (!mounted) return;

      final data = res.data;
      final List list =
          (data is Map && data['data'] is List)
              ? (data['data'] as List)
              : (data is List ? data : const []);

      final mapped =
          list.map<Map<String, String>>((p) {
            final Map<String, dynamic> pMap =
                (p is Map<String, dynamic>) ? p : <String, dynamic>{};

            final user =
                (pMap['user'] is Map)
                    ? (pMap['user'] as Map).cast<String, dynamic>()
                    : <String, dynamic>{};

            final first = (user['name'] ?? '').toString().trim();
            final last = (user['lastname'] ?? '').toString().trim();
            final name =
                ([first, last]..removeWhere((s) => s.isEmpty)).join(' ').trim();

            final ci = (user['ci'] ?? '').toString().replaceAll(
              RegExp(r'\D'),
              '',
            );
            final dv = (user['digit'] ?? '').toString().toUpperCase();
            final rut =
                (ci.isNotEmpty && dv.isNotEmpty) ? '$ci-$dv' : 'Desconocido';

            final at = (pMap['checked_in_at'] ?? '').toString();

            String hhmm = _toChileHhmm(at);

            final k = _passengerKeyFromUser(user);
            if (k != null && _localScanTimeByKey.containsKey(k)) {
              hhmm = _localScanTimeByKey[k]!;
            }

            return {
              'name': name.isEmpty ? 'Sin nombre' : name,
              'rut': rut,
              'scannedAt': hhmm,
              'raw': '',
            };
          }).toList();

      safeSet(() {
        _rows
          ..clear()
          ..addAll(mapped);
      });
    } catch (e) {
      if (!mounted) return;
      maybeSnack('Error recargando pasajeros: $e');
    }
  }

  void _openRoute() {
    final ok =
        widget.startLat != null &&
        widget.startLng != null &&
        widget.endLat != null &&
        widget.endLng != null;
    if (!ok) {
      maybeSnack('No hay coordenadas configuradas para este servicio');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => RouteMapScreen(
              startName: widget.startName,
              endName: widget.endName,
              startLatLng: LatLng(widget.startLat!, widget.startLng!),
              endLatLng: LatLng(widget.endLat!, widget.endLng!),
              installationName: widget.installationName,
              direction: widget.direction,
            ),
      ),
    );
  }

  Future<void> _sendEmail() async {
    if (!mounted) return;

    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) {
      maybeSnack('ID de run inválido.');
      return;
    }

    final List<String> to = switch (widget.defaultTo) {
      null => const [],
      String s => [s],
      List l => l.map((e) => e.toString()).toList(),
      _ => const [],
    };
    final serviceDate = _runDateYmd();

    final passengers =
        _rows
            .map(
              (p) => {
                'name': p['name'] ?? '',
                'rut': p['rut'] ?? '',
                'scanned_at': _dateTimeForReport(serviceDate, p['scannedAt']),
                'checked_in_at': _dateTimeForReport(
                  serviceDate,
                  p['scannedAt'],
                ),
                'scanned_time': p['scannedAt'] ?? '',
              },
            )
            .toList();

    if (_sending) return;
    safeSet(() => _sending = true);

    _emailCancel?.cancel();
    _emailCancel = CancelToken();

    try {
      await _emailApi.sendRunEmail(
        runId: runId,
        to: to,
        cc: const [],
        attachCsv: true,
        serviceDate: serviceDate,
        passengers: passengers,
      );
      if (!mounted) return;

      final nowChile = tz.TZDateTime.now(_chileLoc);
      safeSet(() {
        _emailSentAtChile = nowChile;
        _emailSentMsg = 'Correo enviado ✅';
      });

      await _persistEmailSentState();

      maybeSnack('Correo enviado ✅');
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      final backendMsg =
          (e.response?.data is Map)
              ? (e.response?.data['message'] ?? e.response?.data['error'])
              : e.response?.data?.toString();
      maybeSnack(
        'Error al enviar (${code ?? '---'}): ${backendMsg ?? e.message}',
      );
    } catch (e) {
      if (!mounted) return;
      maybeSnack('Error inesperado: $e');
    } finally {
      if (mounted) safeSet(() => _sending = false);
    }
  }

  // ===== Comenzar / Completar (PATCH, sin pop) =====
  Future<void> _handleStartRun() async {
    if (!mounted || _busyLifecycle) return;
    safeSet(() => _busyLifecycle = true);

    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) {
      maybeSnack('ID de run inválido.');
      safeSet(() => _busyLifecycle = false);
      return;
    }

    _lifecycleCancel?.cancel();
    _lifecycleCancel = CancelToken();

    try {
      await _client.patch(
        '/service-runs/$runId/start',
        data: const {},
        cancelToken: _lifecycleCancel,
        options: Options(
          headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
        ),
      );

      if (!mounted) return;
      safeSet(() => _status = 'in_progress');
      maybeSnack('Ruta iniciada ✅');
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      final backendMsg =
          (e.response?.data is Map)
              ? (e.response?.data['message'] ?? e.response?.data['error'])
              : e.response?.data?.toString();
      maybeSnack(
        'No se pudo iniciar (${code ?? '---'}): ${backendMsg ?? e.message}',
      );
    } finally {
      if (mounted) safeSet(() => _busyLifecycle = false);
    }
  }

  Future<void> _handleCompleteRun() async {
    if (!mounted || _busyLifecycle) return;
    safeSet(() => _busyLifecycle = true);

    final int? runId = _asInt(widget.run['id']);
    if (runId == null || runId <= 0) {
      maybeSnack('ID de run inválido.');
      safeSet(() => _busyLifecycle = false);
      return;
    }

    _lifecycleCancel?.cancel();
    _lifecycleCancel = CancelToken();

    try {
      await _client.patch(
        '/service-runs/$runId/complete',
        data: const {},
        cancelToken: _lifecycleCancel,
        options: Options(
          headers: _token != null ? {'Authorization': 'Bearer $_token'} : null,
        ),
      );

      if (!mounted) return;
      safeSet(() => _status = 'completed');
      maybeSnack('¡Viaje completado!');

      // Opcional:
      // await _clearEmailSentState();
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      final backendMsg =
          (e.response?.data is Map)
              ? (e.response?.data['message'] ?? e.response?.data['error'])
              : e.response?.data?.toString();
      maybeSnack(
        'No se pudo completar (${code ?? '---'}): ${backendMsg ?? e.message}',
      );
    } finally {
      if (mounted) safeSet(() => _busyLifecycle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        '${widget.installationName} • ${widget.direction.toUpperCase()}';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A87C3),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            startName: widget.startName,
            endName: widget.endName,
            onViewRoute: _openRoute,
          ),
          const SizedBox(height: 8),

          // ===== Bloque: Instalación / Fecha / Estado + Botones =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ Instalación/Fecha a la izquierda + indicador a la derecha (cuadro celeste)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Instalación: ${widget.installationName}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Fecha: ${_runDateDdMmYyyy()}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _emailIndicatorChip(),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_status == 'scheduled')
                            FilledButton.icon(
                              onPressed:
                                  _busyLifecycle ? null : _handleStartRun,
                              icon:
                                  _busyLifecycle
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.play_arrow),
                              label: Text(
                                _busyLifecycle ? 'Iniciando…' : 'Comenzar',
                              ),
                            ),
                          if (_status == 'in_progress')
                            FilledButton.icon(
                              onPressed:
                                  _busyLifecycle ? null : _handleCompleteRun,
                              icon:
                                  _busyLifecycle
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.flag),
                              label: Text(
                                _busyLifecycle ? 'Completando…' : 'Completar',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ===== Tabla de pasajeros =====
          Expanded(
            child:
                _rows.isEmpty
                    ? const _EmptyList()
                    : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DataTableTheme(
                        data: DataTableThemeData(
                          headingRowColor: MaterialStateProperty.all(
                            const Color(0xFFE0F3FA),
                          ),
                          headingTextStyle: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0A87C3),
                          ),
                        ),
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Center(child: Text('#'))),
                            DataColumn(label: Center(child: Text('Nombre'))),
                            DataColumn(label: Center(child: Text('RUT'))),
                            DataColumn(label: Center(child: Text('Hora'))),
                          ],
                          rows: List.generate(_rows.length, (i) {
                            final r = _rows[i];
                            return DataRow(
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 16,
                                    child: Center(child: Text('${i + 1}')),
                                  ),
                                ),
                                DataCell(Center(child: Text(r['name'] ?? ''))),
                                DataCell(Center(child: Text(r['rut'] ?? ''))),
                                DataCell(
                                  Center(child: Text(r['scannedAt'] ?? '')),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pasajeros: ${_rows.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                onPressed: _sending ? null : _sendEmail,
                icon:
                    _sending
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.email_outlined),
                label: Text(_sending ? 'Enviando…' : 'Enviar correo'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed:
                    (_sending || _status == 'completed') ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Escanear QR'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ====== UI ====== */

class _Header extends StatelessWidget {
  final String startName;
  final String endName;
  final VoidCallback onViewRoute;
  const _Header({
    required this.startName,
    required this.endName,
    required this.onViewRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A87C3), Color(0xFF74C0E3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Desde',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                Text(
                  startName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.white70, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      'Hacia',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                Text(
                  endName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onViewRoute,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0A87C3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.map_rounded),
            label: const Text('Ver ruta'),
          ),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Aún no hay pasajeros agregados.\nToca el botón para escanear.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

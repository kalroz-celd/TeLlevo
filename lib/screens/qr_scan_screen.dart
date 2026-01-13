import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dio/dio.dart';
import 'package:tellevo/services/dio.dart' as api;

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    required this.runId,
    this.defaultSource = 'scan',
    this.askSeat = false,
    this.askNotes = false,
  });

  final int runId;
  final String defaultSource;
  final bool askSeat;
  final bool askNotes;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _sending = false;
  bool _isTorchOn = false;
  bool _closed = false; // 👈 evita usar context tras cerrar
  CameraFacing _facing = CameraFacing.back;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      facing: _facing,
      detectionSpeed: DetectionSpeed.noDuplicates,
      torchEnabled: false,
      formats: const [BarcodeFormat.qrCode],
      autoStart: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _handled = true; // por si quedara un frame tardío
    unawaited(_controller.stop());
    _controller.dispose();
    _closed = true;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _closed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted && !_closed) _controller.start();
        });
        break;
      default:
        _controller.stop();
        break;
    }
  }

  void safePop([Object? result]) {
    if (_closed || !mounted) return;
    _closed = true; // 👈 marca cerrado ANTES de usar context
    Navigator.of(context).maybePop(result);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || _sending || _closed) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;

    _handled = true;
    await _controller.stop();
    if (!mounted || _closed) return;

    String? seat;
    String? notes;
    if (widget.askSeat || widget.askNotes) {
      final extra = await _askExtras();
      if (!mounted || _closed) return;
      seat = extra['seat'];
      notes = extra['notes'];
    }

    try {
      if (!mounted || _closed) return;
      setState(() => _sending = true);

      final uid = _extractUserId(raw);

      Map<String, dynamic> data;
      if (uid != null) {
        data = await _checkIn(
          runId: widget.runId,
          userId: uid,
          seatNumber: seat,
          notes: notes,
          source: widget.defaultSource,
        );

        final is422 = data['ok'] == false && data['status'] == 422;
        final userIdErr = (data['errors'] is Map)
            ? ((data['errors']['user_id'] as List?)?.join(', ') ?? '')
            : '';
        if (is422 && userIdErr.toLowerCase().contains('selected user id is invalid')) {
          if (!mounted || _closed) return;
          data = await _checkInFlexible(
            runId: widget.runId,
            raw: raw,
            seatNumber: seat,
            notes: notes,
            source: widget.defaultSource,
          );
        }
      } else {
        data = await _checkInFlexible(
          runId: widget.runId,
          raw: raw,
          seatNumber: seat,
          notes: notes,
          source: widget.defaultSource,
        );
      }

      if (!mounted || _closed) return;
      data['qr'] = raw;
      safePop(data); // 👈 cerrar una sola vez y no tocar más context
    } catch (e) {
      if (!mounted || _closed) return;
      safePop({
        'ok': false,
        'error': 'No se pudo registrar: $e',
        'qr': raw,
      });
    }
  }

  Future<Map<String, dynamic>> _checkIn({
    required int runId,
    required int userId,
    String? seatNumber,
    String? notes,
    String source = 'scan',
  }) async {
    final Dio dio = api.dio();
    try {
      final res = await dio.post(
        '/service-runs/$runId/passengers/check-in',
        data: {
          'user_id': userId,
          if (seatNumber != null && seatNumber.isNotEmpty) 'seat_number': seatNumber,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          'source': source,
        },
      );
      final map = (res.data as Map).cast<String, dynamic>();
      map['ok'] = true;
      return map;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data   = e.response?.data;
      return {
        'ok': false,
        'status': status,
        'error': (data is Map && data['message'] != null)
            ? data['message'].toString()
            : e.message ?? 'DioException',
        'errors': (data is Map && data['errors'] != null) ? data['errors'] : null,
      };
    }
  }

  Future<Map<String, dynamic>> _checkInFlexible({
    required int runId,
    required String raw,
    String? seatNumber,
    String? notes,
    String source = 'scan',
  }) async {
    final Dio dio = api.dio();

    final payload = <String, dynamic>{'source': source};

    try {
      final obj = jsonDecode(raw);
      if (obj is Map) {
        final rutJson = obj['rut']?.toString();
        final mailJson = obj['email']?.toString();
        if (rutJson != null && rutJson.isNotEmpty) payload['rut'] = rutJson;
        if (mailJson != null && mailJson.isNotEmpty) payload['email'] = mailJson;
      }
    } catch (_) {}

    payload.putIfAbsent('rut', () => _extractRut(raw));
    payload.putIfAbsent('email', () => _extractEmail(raw));

    if (seatNumber != null && seatNumber.isNotEmpty) payload['seat_number'] = seatNumber;
    if (notes != null && notes.isNotEmpty) payload['notes'] = notes;

    if (payload['rut'] == null && payload['email'] == null) {
      return {
        'ok': false,
        'status': 422,
        'error': 'QR no contiene user_id, rut ni email',
        'errors': {'qr': ['Formato de QR no soportado']},
      };
    }

    try {
      final res = await dio.post('/service-runs/$runId/passengers/check-in', data: payload);
      final map = (res.data as Map).cast<String, dynamic>();
      map['ok'] = true;
      return map;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data   = e.response?.data;
      return {
        'ok': false,
        'status': status,
        'error': (data is Map && data['message'] != null)
            ? data['message'].toString()
            : e.message ?? 'DioException',
        'errors': (data is Map && data['errors'] != null) ? data['errors'] : null,
      };
    }
  }

  /// Solo JSON con "user_id"
  int? _extractUserId(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['user_id'] != null) {
        return int.tryParse(data['user_id'].toString());
      }
    } catch (_) {}
    return null;
  }

  String? _extractRut(String raw) {
    final r = raw.trim();
    final regex = RegExp(r'^\d{6,9}-[\dkK]$');
    return regex.hasMatch(r) ? r : null;
  }

  String? _extractEmail(String raw) {
    final r = raw.trim();
    final regex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');
    return regex.hasMatch(r) ? r : null;
  }

  Future<Map<String, String?>> _askExtras() async {
    String? seat;
    String? notes;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final seatCtrl = TextEditingController();
        final notesCtrl = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.askSeat)
                TextField(
                  controller: seatCtrl,
                  decoration: const InputDecoration(labelText: 'Asiento (opcional)'),
                ),
              if (widget.askNotes)
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notas (opcional)'),
                  maxLines: 3,
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Omitir')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      seat = seatCtrl.text.trim().isEmpty ? null : seatCtrl.text.trim();
                      notes = notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();
                      Navigator.pop(ctx);
                    },
                    child: const Text('Continuar'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return {'seat': seat, 'notes': notes};
  }

  Future<void> _toggleTorch() async {
    if (!mounted || _closed) return;
    try {
      _isTorchOn = !_isTorchOn;
      await _controller.toggleTorch();
      if (mounted && !_closed) setState(() {});
    } catch (_) {
      if (!mounted || _closed) return;
      unawaited(_controller.start());
    }
  }

  Future<void> _switchCamera() async {
    if (!mounted || _closed) return;
    try {
      await _controller.stop();
      if (!mounted || _closed) return;
      _facing = _facing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
      await _controller.switchCamera();
      if (!mounted || _closed) return;
      await _controller.start();
      if (mounted && !_closed) setState(() {});
    } catch (_) {
      if (!mounted || _closed) return;
      unawaited(_controller.start());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              fit: BoxFit.cover,
              errorBuilder: (context, error, child) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Error de cámara',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                border: Border.all(width: 2, color: Colors.white),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        await _controller.stop();
                        safePop(null);
                      },
                      child: const Text('Cerrar'),
                    ),
                    IconButton(
                      tooltip: 'Linterna',
                      onPressed: _toggleTorch,
                      icon: Icon(
                        _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Cámara frontal/trasera',
                      onPressed: _switchCamera,
                      icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_sending)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

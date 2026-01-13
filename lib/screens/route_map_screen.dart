import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tellevo/models/map_api.dart';
import 'package:url_launcher/url_launcher.dart';

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({
    super.key,
    required this.startLatLng,
    required this.endLatLng,
    this.startName,
    this.endName,
    this.installationName,
    this.direction,
  });

  final LatLng startLatLng;
  final LatLng endLatLng;
  final String? startName;
  final String? endName;
  final String? installationName;
  final String? direction;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Completer<GoogleMapController> _mapCtrlCompleter = Completer();

  bool _loading = true;
  String? _error;

  // Vida útil (para cortar actualizaciones tras dispose)
  bool _alive = true;

  // Fit de cámara, una sola vez
  bool _cameraFitted = false;

  // Geometría/metricas
  List<LatLng> _routePoints = const [];
  int? _distanceM; // metros
  int? _durationS; // segundos

  @override
  void initState() {
    super.initState();
    _safeLoad();
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  bool get _isAlive => mounted && _alive;

  Future<void> _safeLoad() async {
    try {
      final api = MapApi();
      final data = await api.fetchDirections(
        start: widget.startLatLng,
        end: widget.endLatLng,
      );

      if (!_isAlive) return;

      // =======================
      // Construcción de geometría
      // =======================
      final pts = <LatLng>[];

      // 1) Polyline codificado
      final polylineStr = (data['polyline'] as String?);
      if (polylineStr != null && polylineStr.isNotEmpty) {
        pts.addAll(_decodePolyline(polylineStr));
      }

      // 2) Lista de puntos
      if (pts.length < 2 && data['points'] is List) {
        final lst = data['points'] as List;
        for (final p in lst) {
          if (p is List && p.length >= 2) {
            pts.add(LatLng(
              (p[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            ));
          } else if (p is Map && p['lat'] != null && p['lng'] != null) {
            pts.add(LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ));
          }
        }
      }

      // 3) GeoJSON (coordinates: [ [lng,lat], ... ])
      Map? gj = data['geojson'] is Map ? data['geojson'] as Map : null;
      gj ??= data['geometry'] is Map ? data['geometry'] as Map : null;
      if (pts.length < 2 && gj != null) {
        final coords = gj['coordinates'];
        if (coords is List) {
          for (final c in coords) {
            if (c is List && c.length >= 2) {
              pts.add(LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ));
            }
          }
        }
      }

      if (pts.length < 2) {
        // Fallback: dibuja recta e informa (sin romper UX)
        pts
          ..clear()
          ..add(widget.startLatLng)
          ..add(widget.endLatLng);
        if (_isAlive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo obtener la ruta. Mostrando línea recta.')),
          );
        }
      }

      // Métricas del backend (opcionalmente nulas)
      final distanceM = data['distance_m'] is num ? (data['distance_m'] as num).toInt() : null;
      final durationS = data['duration_s'] is num ? (data['duration_s'] as num).toInt() : null;

      // Markers/Polylines en memoria
      final markers = <Marker>{
        Marker(
          markerId: const MarkerId('start'),
          position: widget.startLatLng,
          infoWindow: InfoWindow(title: widget.startName ?? 'Inicio'),
        ),
        Marker(
          markerId: const MarkerId('end'),
          position: widget.endLatLng,
          infoWindow: InfoWindow(title: widget.endName ?? 'Destino'),
        ),
      };

      final polylines = <Polyline>{
        Polyline(
          polylineId: const PolylineId('route'),
          points: pts,
          width: 5,
          geodesic: false,
        ),
      };

      if (!_isAlive) return;
      setState(() {
        _routePoints = pts;
        _distanceM = distanceM;
        _durationS = durationS;
        _markers
          ..clear()
          ..addAll(markers);
        _polylines
          ..clear()
          ..addAll(polylines);
        _loading = false;
        _error = null;
      });

      _fitCameraSafely();
    } catch (e) {
      if (!_isAlive) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _fitCameraSafely() {
    if (!_isAlive || _cameraFitted || _routePoints.length < 2) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isAlive || _cameraFitted || _routePoints.length < 2) return;

      GoogleMapController? ctrl;
      try {
        if (_mapCtrlCompleter.isCompleted) {
          ctrl = await _mapCtrlCompleter.future;
        } else {
          ctrl = await _mapCtrlCompleter.future
              .timeout(const Duration(milliseconds: 3000));
        }
      } catch (_) {
        return;
      }
      if (!_isAlive || ctrl == null) return;

      final bounds = _computeBounds(_routePoints);
      try {
        await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
        if (_isAlive) _cameraFitted = true;
      } catch (_) {
        // Ignorar si aún no puede ajustar
      }
    });
  }

  // -------- Helpers de formato --------
  String _formatDistance(int? meters) {
    if (meters == null) return '—';
    if (meters < 1000) return '${meters} m';
    final km = meters / 1000.0;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.toStringAsFixed(0)} km';
    }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m} min';
    return '${h} h ${m.toString().padLeft(2, '0')} min';
  }

  Future<void> _openInGoogleMaps() async {
    final o = '${widget.startLatLng.latitude},${widget.startLatLng.longitude}';
    final d = '${widget.endLatLng.latitude},${widget.endLatLng.longitude}';
    final nameO = (widget.startName ?? '').trim();

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$o'
      '&destination=$d'
      '&travelmode=driving'
      '${nameO.isNotEmpty ? '&origin_place_id=' : ''}' // (no tenemos place_id real, así que omitimos)
    );

    if (await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && _isAlive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir Google Maps.')),
        );
      }
    } else if (_isAlive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay app para abrir Google Maps.')),
      );
    }
  }

  // --- Decodificador de Google Encoded Polyline ---
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  LatLngBounds _computeBounds(List<LatLng> pts) {
    double? minLat, maxLat, minLng, maxLng;
    for (final p in pts) {
      minLat = (minLat == null) ? p.latitude : (p.latitude < minLat ? p.latitude : minLat);
      maxLat = (maxLat == null) ? p.latitude : (p.latitude > maxLat ? p.latitude : maxLat);
      minLng = (minLng == null) ? p.longitude : (p.longitude < minLng ? p.longitude : minLng);
      maxLng = (maxLng == null) ? p.longitude : (p.longitude > maxLng ? p.longitude : maxLng);
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = [
      if (widget.installationName != null) widget.installationName!,
      if (widget.direction != null) widget.direction!,
    ].join(' • ');

    final infoBar = _InfoBar(
      originLabel: widget.startName ?? 'Inicio',
      destinationLabel: widget.endName ?? 'Destino',
      distanceText: _formatDistance(_distanceM),
      durationText: _formatDuration(_durationS),
      onOpenInMaps: _openInGoogleMaps,
    );

    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? 'Ruta' : title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                )
              : Column(
                  children: [
                    // Mapa
                    Expanded(
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: widget.startLatLng,
                          zoom: 14,
                        ),
                        onMapCreated: (controller) {
                          if (!_isAlive) return;
                          if (!_mapCtrlCompleter.isCompleted) {
                            _mapCtrlCompleter.complete(controller);
                          }
                          _fitCameraSafely();
                        },
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        compassEnabled: true,
                      ),
                    ),
                    // Barra de info
                    infoBar,
                  ],
                ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({
    required this.originLabel,
    required this.destinationLabel,
    required this.distanceText,
    required this.durationText,
    required this.onOpenInMaps,
  });

  final String originLabel;
  final String destinationLabel;
  final String distanceText;
  final String durationText;
  final VoidCallback onOpenInMaps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: const Color(0xFFF7F7F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Origen/Destino
          Row(
            children: [
              Expanded(
                child: _LineItem(
                  icon: Icons.my_location,
                  label: 'Origen',
                  value: originLabel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LineItem(
                  icon: Icons.flag,
                  label: 'Destino',
                  value: destinationLabel,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Distancia / Tiempo + botón
          Row(
            children: [
              _Chip(icon: Icons.straighten, label: distanceText, tooltip: 'Distancia'),
              const SizedBox(width: 12),
              _Chip(icon: Icons.schedule, label: durationText, tooltip: 'Tiempo estimado'),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: onOpenInMaps,
                icon: const Icon(Icons.map),
                label: const Text('Abrir en Google Maps'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.icon,
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment:
                alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: textAlign),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: textAlign),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.tooltip});
  final IconData icon;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

    return tooltip != null ? Tooltip(message: tooltip!, child: chip) : chip;
  }
}

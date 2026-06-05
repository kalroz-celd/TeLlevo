from pathlib import Path
p = Path(r'c:\dev\app_tellevo\tellevo_v0.1\tellevo\lib\screens\driver_trips_history_screen.dart')
text = p.read_text(encoding='utf-8')
old = '''      // Soporta:
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
        _allTrips = _normalizeTripList(list);
        _applyMonthFilter();
      });'''
new = '''      // Soporta respuestas planas y agrupadas por fecha:
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
      });'''
if old not in text:
    raise ValueError('Old block not found')
text = text.replace(old, new, 1)
helper = '''  List<dynamic> _extractTripItems(Map rawData) {
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

'''
marker = '  List<Map<String, dynamic>> _normalizeTripList(List<dynamic> rawList) {'
idx = text.find(marker)
if idx == -1:
    raise ValueError('Insert marker not found')
if helper not in text:
    text = text[:idx] + helper + text[idx:]
p.write_text(text, encoding='utf-8')
print('patched')

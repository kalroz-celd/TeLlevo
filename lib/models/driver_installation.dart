class DriverService {
  final int id;
  final String direction;        // 'ida' | 'vuelta'
  final String startLocation;    // puede venir como "lat,lng"
  final String endLocation;
  final int capacityPerDay;
  final bool isActive;

  const DriverService({
    required this.id,
    required this.direction,
    required this.startLocation,
    required this.endLocation,
    required this.capacityPerDay,
    required this.isActive,
  });

  factory DriverService.fromJson(Map<String, dynamic> json) {
    return DriverService(
      id: (json['id'] as num).toInt(),
      direction: (json['direction'] ?? '').toString(),
      startLocation: (json['start_location'] ?? json['startLocation'] ?? '').toString(),
      endLocation: (json['end_location'] ?? json['endLocation'] ?? '').toString(),
      capacityPerDay: (json['capacity_per_day'] ?? json['capacityPerDay'] ?? 1) as int,
      isActive: (json['is_active'] ?? json['isActive'] ?? true) == true,
    );
  }
}

class DriverInstallation {
  final int id;
  final String name;
  final String? startAddress;
  final String? endAddress;
  final List<DriverService> services;

  const DriverInstallation({
    required this.id,
    required this.name,
    required this.startAddress,
    required this.endAddress,
    required this.services,
  });

  factory DriverInstallation.fromJson(Map<String, dynamic> json) {
    final list = (json['services'] as List<dynamic>? ?? []);
    return DriverInstallation(
      id: (json['id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      startAddress: (json['start_address'] ?? json['startAddress'])?.toString(),
      endAddress: (json['end_address'] ?? json['endAddress'])?.toString(),
      services: list.map((e) => DriverService.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

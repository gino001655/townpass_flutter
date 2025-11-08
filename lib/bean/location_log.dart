class LocationLog {
  const LocationLog({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory LocationLog.fromJson(Map<String, dynamic> json) {
    return LocationLog(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  LocationLog copyWith({
    double? latitude,
    double? longitude,
    DateTime? capturedAt,
  }) {
    return LocationLog(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}


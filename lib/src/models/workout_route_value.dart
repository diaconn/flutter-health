/// 운동 경로(workout_route)의 GPS 한 지점.
class RoutePoint {
  final double lat;
  final double lon;
  final double? altitude; // m
  final int timestampMs;
  final double? speed; // m/s

  const RoutePoint({
    required this.lat,
    required this.lon,
    this.altitude,
    required this.timestampMs,
    this.speed,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) => RoutePoint(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        altitude: (json['altitude'] as num?)?.toDouble(),
        timestampMs: (json['timestampMs'] as num).toInt(),
        speed: (json['speed'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        if (altitude != null) 'altitude': altitude,
        'timestampMs': timestampMs,
        if (speed != null) 'speed': speed,
      };
}

/// 운동 경로(workout_route) 기록 — GPS 좌표 점들의 묶음.
class WorkoutRouteValue {
  final List<RoutePoint> points;

  const WorkoutRouteValue({required this.points});

  factory WorkoutRouteValue.fromJson(Map<String, dynamic> json) => WorkoutRouteValue(
        points: (json['points'] as List)
            .map((e) => RoutePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {'points': points.map((e) => e.toJson()).toList()};
}

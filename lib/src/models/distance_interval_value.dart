/// 이동 거리 구간(distance_interval) — **벽시계 10분 격자 버킷**의 이동 거리 합(m). metric 에서 분리된 독립 타입.
/// envelope 의 timestamp/endTimestamp 가 격자 경계(예: 09:00~09:10)이며, distance 는 그 10분 구간의 거리 합.
class DistanceIntervalValue {
  final double distance; // 구간 이동 거리 (m)

  const DistanceIntervalValue({required this.distance});

  factory DistanceIntervalValue.fromJson(Map<String, dynamic> json) =>
      DistanceIntervalValue(distance: (json['distance'] as num).toDouble());

  Map<String, dynamic> toJson() => {'distance': distance};
}

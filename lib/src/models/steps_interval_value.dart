/// 걸음 구간(steps_interval) — **벽시계 10분 격자 버킷**의 걸음 수 합. metric 에서 분리된 독립 타입.
/// envelope 의 timestamp/endTimestamp 가 격자 경계(예: 09:00~09:10)이며, count 는 그 10분 구간의 걸음 합.
class StepsIntervalValue {
  final int count; // 구간 걸음 수

  const StepsIntervalValue({required this.count});

  factory StepsIntervalValue.fromJson(Map<String, dynamic> json) =>
      StepsIntervalValue(count: (json['count'] as num).toInt());

  Map<String, dynamic> toJson() => {'count': count};
}

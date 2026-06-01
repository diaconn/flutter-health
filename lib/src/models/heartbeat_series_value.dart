/// 심박 시리즈(heartbeat_series) 기록. beat-to-beat raw 는 방대해서 제외하고
/// 측정 개수와 지속시간만 담는다.
class HeartbeatSeriesValue {
  final int count;
  final int durationSec;

  const HeartbeatSeriesValue({required this.count, required this.durationSec});

  factory HeartbeatSeriesValue.fromJson(Map<String, dynamic> json) => HeartbeatSeriesValue(
        count: (json['count'] as num).toInt(),
        durationSec: (json['durationSec'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'count': count, 'durationSec': durationSec};
}

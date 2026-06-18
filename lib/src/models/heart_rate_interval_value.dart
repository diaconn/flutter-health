/// 심박수(heart_rate_interval) — **벽시계 10분 격자 버킷**의 평균/최소/최대(bpm). metric 에서 분리된 독립 타입.
/// envelope 의 timestamp/endTimestamp 가 격자 경계(예: 09:00~09:10)이며, 값은 그 10분 구간의 집계.
class HeartRateIntervalValue {
  final int? avg; // 구간 평균 심박수 (bpm)
  final int? min; // 구간 최저 심박수 (bpm)
  final int? max; // 구간 최고 심박수 (bpm)

  const HeartRateIntervalValue({this.avg, this.min, this.max});

  factory HeartRateIntervalValue.fromJson(Map<String, dynamic> json) => HeartRateIntervalValue(
        avg: json['avg'] as int?,
        min: json['min'] as int?,
        max: json['max'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (avg != null) 'avg': avg,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };
}

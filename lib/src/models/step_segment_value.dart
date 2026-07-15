/// 걸음 활동 구간 1건 (iOS HKQuantitySample stepCount). iOS 전용.
/// 시작/종료는 envelope timestamp/endTimestamp, 여기엔 걸음수와 기록 기기 종류만.
class StepSegmentValue {
  /// 구간 걸음수.
  final int count;

  /// 기록 기기 종류: phone | watch | tablet | other (기기명 대신 정규화).
  final String sourceType;

  const StepSegmentValue({required this.count, required this.sourceType});

  factory StepSegmentValue.fromJson(Map<String, dynamic> json) => StepSegmentValue(
        count: (json['count'] as num).toInt(),
        sourceType: json['source_type'] as String? ?? 'other',
      );

  Map<String, dynamic> toJson() => {
        'count': count,
        'source_type': sourceType,
      };
}

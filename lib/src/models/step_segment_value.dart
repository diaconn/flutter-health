/// 걸음 구간 한 건 (iOS HealthKit `HKQuantityTypeIdentifierStepCount` 샘플 하나).
/// metric 의 합산값과 달리 건강 앱 상세목록의 개별 기록을 그대로 담는다.
/// 시작/종료 시각은 envelope 의 timestamp/endTimestamp 에 있고, 여기엔 걸음수와 소스 종류만.
class StepSegmentValue {
  /// 해당 구간의 걸음수.
  final int count;

  /// 기록 기기 종류: "phone" | "watch" | "tablet" | "other".
  /// 사용자 지정 기기명("내 iPhone" 등) 대신 정규화한 값이라 다중 소스 겹침을 단순하게 구분할 수 있다.
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

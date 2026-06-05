/// 키(신장) 한 건. 값은 **cm 로 통일** — iOS HealthKit(HKQuantityTypeIdentifier.height) ·
/// Android(Samsung UserProfile.HEIGHT) 양쪽 모두 cm.
/// iOS 는 [since]~[to] 구간의 키 샘플들을, Android 는 사용자 프로필에 설정된 현재 키 1건을 반환.
class HeightValue {
  /// 키 (cm).
  final double value;

  const HeightValue({required this.value});

  factory HeightValue.fromJson(Map<String, dynamic> json) => HeightValue(
        value: (json['value'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
      };
}

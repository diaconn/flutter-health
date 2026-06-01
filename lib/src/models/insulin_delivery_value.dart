/// iOS HealthKit `HKQuantityTypeIdentifierInsulinDelivery` 의 평탄화 모델.
///
/// HealthKit 메타키 `HKMetadataKeyInsulinDeliveryReason` 의 enum 값:
///   1 = Basal  → [reason] = "basal"
///   2 = Bolus  → [reason] = "bolus"   (식사·교정용)
/// 메타데이터가 없으면 [reason] = null.
///
/// Android(Samsung) 는 인슐린을 혈당 레코드 하위 필드 `BloodGlucoseType.INSULIN_INJECTED`
/// (Float, 양만) 로만 노출하며 basal/bolus 구분 enum 자체가 없음 → 이 데이터타입은 iOS 전용.
class InsulinDeliveryValue {
  /// 투여량 (IU, International Unit).
  final double dose;

  /// 투여 목적 — "basal" | "bolus" | null.
  final String? reason;

  const InsulinDeliveryValue({required this.dose, this.reason});

  factory InsulinDeliveryValue.fromJson(Map<String, dynamic> json) => InsulinDeliveryValue(
        dose: (json['dose'] as num).toDouble(),
        reason: json['reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'dose': dose,
        if (reason != null) 'reason': reason,
      };
}

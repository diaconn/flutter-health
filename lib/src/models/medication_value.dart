/// 복약 이벤트(medication) 기록 — iOS 26+ HKMedicationDoseEvent.
/// 약 이름은 별도 조회(HKUserAnnotatedMedicationQuery)가 필요해 여기선 복용 상태/용량만 담는다.
class MedicationValue {
  final String logStatus; // "taken"|"skipped"|"not_interacted"|"snoozed"|"notification_not_sent"|"not_logged"
  final String scheduleType; // "scheduled"|"as_needed"
  final double? doseQuantity;
  final String? unit;
  final int? scheduledDate; // epoch ms (scheduled 일 때만)

  const MedicationValue({
    required this.logStatus,
    required this.scheduleType,
    this.doseQuantity,
    this.unit,
    this.scheduledDate,
  });

  factory MedicationValue.fromJson(Map<String, dynamic> json) => MedicationValue(
        logStatus: json['log_status'] as String,
        scheduleType: json['schedule_type'] as String,
        doseQuantity: (json['dose_quantity'] as num?)?.toDouble(),
        unit: json['unit'] as String?,
        scheduledDate: (json['scheduled_date'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'log_status': logStatus,
        'schedule_type': scheduleType,
        if (doseQuantity != null) 'dose_quantity': doseQuantity,
        if (unit != null) 'unit': unit,
        if (scheduledDate != null) 'scheduled_date': scheduledDate,
      };
}

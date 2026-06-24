class BloodPressureValue {
  final double systolic;
  final double diastolic;
  final double? mean;
  final int? pulseRate;
  final bool? medicationTaken;

  const BloodPressureValue({
    required this.systolic,
    required this.diastolic,
    this.mean,
    this.pulseRate,
    this.medicationTaken,
  });

  factory BloodPressureValue.fromJson(Map<String, dynamic> json) => BloodPressureValue(
        systolic: (json['systolic'] as num).toDouble(),
        diastolic: (json['diastolic'] as num).toDouble(),
        mean: (json['mean'] as num?)?.toDouble(),
        pulseRate: (json['pulse_rate'] as num?)?.toInt(),
        medicationTaken: json['medication_taken'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'systolic': systolic,
        'diastolic': diastolic,
        if (mean != null) 'mean': mean,
        if (pulseRate != null) 'pulse_rate': pulseRate,
        if (medicationTaken != null) 'medication_taken': medicationTaken,
      };
}

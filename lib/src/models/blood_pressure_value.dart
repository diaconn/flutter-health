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
        pulseRate: (json['pulseRate'] as num?)?.toInt(),
        medicationTaken: json['medicationTaken'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'systolic': systolic,
        'diastolic': diastolic,
        if (mean != null) 'mean': mean,
        if (pulseRate != null) 'pulseRate': pulseRate,
        if (medicationTaken != null) 'medicationTaken': medicationTaken,
      };
}

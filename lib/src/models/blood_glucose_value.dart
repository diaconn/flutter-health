class BloodGlucoseSeriesEntry {
  final double glucose;
  final int timestampMs;

  const BloodGlucoseSeriesEntry({required this.glucose, required this.timestampMs});

  factory BloodGlucoseSeriesEntry.fromJson(Map<String, dynamic> json) => BloodGlucoseSeriesEntry(
        glucose: (json['glucose'] as num).toDouble(),
        timestampMs: (json['timestamp_ms'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'glucose': glucose,
        'timestamp_ms': timestampMs,
      };
}

class BloodGlucoseValue {
  final double glucose; // mg/dL
  final String? mealStatus; // "fasting"|"before_meal"|"after_meal"|"general" (Samsung 앱 입력 4종) 등
  final double? insulinInjected;
  final bool? medicationTaken;
  final List<BloodGlucoseSeriesEntry>? series;

  const BloodGlucoseValue({
    required this.glucose,
    this.mealStatus,
    this.insulinInjected,
    this.medicationTaken,
    this.series,
  });

  factory BloodGlucoseValue.fromJson(Map<String, dynamic> json) => BloodGlucoseValue(
        glucose: (json['glucose'] as num).toDouble(),
        mealStatus: json['meal_status'] as String?,
        insulinInjected: (json['insulin_injected'] as num?)?.toDouble(),
        medicationTaken: json['medication_taken'] as bool?,
        series: (json['series'] as List?)
            ?.map((e) => BloodGlucoseSeriesEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'glucose': glucose,
        if (mealStatus != null) 'meal_status': mealStatus,
        if (insulinInjected != null) 'insulin_injected': insulinInjected,
        if (medicationTaken != null) 'medication_taken': medicationTaken,
        if (series != null) 'series': series!.map((e) => e.toJson()).toList(),
      };
}

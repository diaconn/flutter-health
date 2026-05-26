class BloodGlucoseSeriesEntry {
  final double glucose;
  final int timestampMs;

  const BloodGlucoseSeriesEntry({required this.glucose, required this.timestampMs});

  factory BloodGlucoseSeriesEntry.fromJson(Map<String, dynamic> json) => BloodGlucoseSeriesEntry(
        glucose: (json['glucose'] as num).toDouble(),
        timestampMs: (json['timestampMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'glucose': glucose,
        'timestampMs': timestampMs,
      };
}

class BloodGlucoseValue {
  final double glucose; // mg/dL
  final String? measurementType; // "whole_blood"|"plasma"|"serum"
  final String? sampleSourceType; // "venous"|"capillary"
  final int? mealTimeMs;
  final String? mealStatus; // "fasting"|"before_meal"|"after_meal"|"before_breakfast"|...
  final double? insulinInjected;
  final bool? medicationTaken;
  final List<BloodGlucoseSeriesEntry>? series;

  const BloodGlucoseValue({
    required this.glucose,
    this.measurementType,
    this.sampleSourceType,
    this.mealTimeMs,
    this.mealStatus,
    this.insulinInjected,
    this.medicationTaken,
    this.series,
  });

  factory BloodGlucoseValue.fromJson(Map<String, dynamic> json) => BloodGlucoseValue(
        glucose: (json['glucose'] as num).toDouble(),
        measurementType: json['measurementType'] as String?,
        sampleSourceType: json['sampleSourceType'] as String?,
        mealTimeMs: (json['mealTimeMs'] as num?)?.toInt(),
        mealStatus: json['mealStatus'] as String?,
        insulinInjected: (json['insulinInjected'] as num?)?.toDouble(),
        medicationTaken: json['medicationTaken'] as bool?,
        series: (json['series'] as List?)
            ?.map((e) => BloodGlucoseSeriesEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'glucose': glucose,
        if (measurementType != null) 'measurementType': measurementType,
        if (sampleSourceType != null) 'sampleSourceType': sampleSourceType,
        if (mealTimeMs != null) 'mealTimeMs': mealTimeMs,
        if (mealStatus != null) 'mealStatus': mealStatus,
        if (insulinInjected != null) 'insulinInjected': insulinInjected,
        if (medicationTaken != null) 'medicationTaken': medicationTaken,
        if (series != null) 'series': series!.map((e) => e.toJson()).toList(),
      };
}

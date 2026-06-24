class HourlySummaryValue {
  final String hour; // "yyyy-MM-dd'T'HH" 로컬 기준
  final int? heartRateAvg;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? stepsTotal;
  final double? caloriesTotal; // kcal (basal + active)
  final double? caloriesActiveTotal; // kcal
  final int? activeTimeTotal; // min
  final double? distanceTotal; // m

  const HourlySummaryValue({
    required this.hour,
    this.heartRateAvg,
    this.heartRateMin,
    this.heartRateMax,
    this.stepsTotal,
    this.caloriesTotal,
    this.caloriesActiveTotal,
    this.activeTimeTotal,
    this.distanceTotal,
  });

  factory HourlySummaryValue.fromJson(Map<String, dynamic> json) => HourlySummaryValue(
        hour: json['hour'] as String,
        heartRateAvg: json['heart_rate_avg'] as int?,
        heartRateMin: json['heart_rate_min'] as int?,
        heartRateMax: json['heart_rate_max'] as int?,
        stepsTotal: json['steps_total'] as int?,
        caloriesTotal: (json['calories_total'] as num?)?.toDouble(),
        caloriesActiveTotal: (json['calories_active_total'] as num?)?.toDouble(),
        activeTimeTotal: json['active_time_total'] as int?,
        distanceTotal: (json['distance_total'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'hour': hour,
        if (heartRateAvg != null) 'heart_rate_avg': heartRateAvg,
        if (heartRateMin != null) 'heart_rate_min': heartRateMin,
        if (heartRateMax != null) 'heart_rate_max': heartRateMax,
        if (stepsTotal != null) 'steps_total': stepsTotal,
        if (caloriesTotal != null) 'calories_total': caloriesTotal,
        if (caloriesActiveTotal != null) 'calories_active_total': caloriesActiveTotal,
        if (activeTimeTotal != null) 'active_time_total': activeTimeTotal,
        if (distanceTotal != null) 'distance_total': distanceTotal,
      };
}

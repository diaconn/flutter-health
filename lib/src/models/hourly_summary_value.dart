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
        heartRateAvg: json['heartRateAvg'] as int?,
        heartRateMin: json['heartRateMin'] as int?,
        heartRateMax: json['heartRateMax'] as int?,
        stepsTotal: json['stepsTotal'] as int?,
        caloriesTotal: (json['caloriesTotal'] as num?)?.toDouble(),
        caloriesActiveTotal: (json['caloriesActiveTotal'] as num?)?.toDouble(),
        activeTimeTotal: json['activeTimeTotal'] as int?,
        distanceTotal: (json['distanceTotal'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'hour': hour,
        if (heartRateAvg != null) 'heartRateAvg': heartRateAvg,
        if (heartRateMin != null) 'heartRateMin': heartRateMin,
        if (heartRateMax != null) 'heartRateMax': heartRateMax,
        if (stepsTotal != null) 'stepsTotal': stepsTotal,
        if (caloriesTotal != null) 'caloriesTotal': caloriesTotal,
        if (caloriesActiveTotal != null) 'caloriesActiveTotal': caloriesActiveTotal,
        if (activeTimeTotal != null) 'activeTimeTotal': activeTimeTotal,
        if (distanceTotal != null) 'distanceTotal': distanceTotal,
      };
}

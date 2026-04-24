class HourlySummaryValue {
  final String hour; // "yyyy-MM-dd'T'HH" 로컬 기준
  final int? heartRateAvg;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? stepsTotal;
  final double? caloriesTotalKcal;
  final double? distanceTotalM;

  const HourlySummaryValue({
    required this.hour,
    this.heartRateAvg,
    this.heartRateMin,
    this.heartRateMax,
    this.stepsTotal,
    this.caloriesTotalKcal,
    this.distanceTotalM,
  });

  factory HourlySummaryValue.fromJson(Map<String, dynamic> json) => HourlySummaryValue(
        hour: json['hour'] as String,
        heartRateAvg: json['heartRateAvg'] as int?,
        heartRateMin: json['heartRateMin'] as int?,
        heartRateMax: json['heartRateMax'] as int?,
        stepsTotal: json['stepsTotal'] as int?,
        caloriesTotalKcal: (json['caloriesTotalKcal'] as num?)?.toDouble(),
        distanceTotalM: (json['distanceTotalM'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'hour': hour,
        if (heartRateAvg != null) 'heartRateAvg': heartRateAvg,
        if (heartRateMin != null) 'heartRateMin': heartRateMin,
        if (heartRateMax != null) 'heartRateMax': heartRateMax,
        if (stepsTotal != null) 'stepsTotal': stepsTotal,
        if (caloriesTotalKcal != null) 'caloriesTotalKcal': caloriesTotalKcal,
        if (distanceTotalM != null) 'distanceTotalM': distanceTotalM,
      };
}

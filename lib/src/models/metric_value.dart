class MetricValue {
  final int? heartRateAvg;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? stepsInterval;
  final int? stepsDaily;
  final double? caloriesInterval;
  final double? caloriesDaily;
  final double? caloriesActiveInterval;
  final double? caloriesActiveDaily;
  final double? distanceInterval;
  final double? distanceDaily;
  final int? spO2;
  final double? hrv;

  const MetricValue({
    this.heartRateAvg,
    this.heartRateMin,
    this.heartRateMax,
    this.stepsInterval,
    this.stepsDaily,
    this.caloriesInterval,
    this.caloriesDaily,
    this.caloriesActiveInterval,
    this.caloriesActiveDaily,
    this.distanceInterval,
    this.distanceDaily,
    this.spO2,
    this.hrv,
  });

  factory MetricValue.fromJson(Map<String, dynamic> json) => MetricValue(
        heartRateAvg: json['heartRateAvg'] as int?,
        heartRateMin: json['heartRateMin'] as int?,
        heartRateMax: json['heartRateMax'] as int?,
        stepsInterval: json['stepsInterval'] as int?,
        stepsDaily: json['stepsDaily'] as int?,
        caloriesInterval: (json['caloriesInterval'] as num?)?.toDouble(),
        caloriesDaily: (json['caloriesDaily'] as num?)?.toDouble(),
        caloriesActiveInterval: (json['caloriesActiveInterval'] as num?)?.toDouble(),
        caloriesActiveDaily: (json['caloriesActiveDaily'] as num?)?.toDouble(),
        distanceInterval: (json['distanceInterval'] as num?)?.toDouble(),
        distanceDaily: (json['distanceDaily'] as num?)?.toDouble(),
        spO2: json['spO2'] as int?,
        hrv: (json['hrv'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        if (heartRateAvg != null) 'heartRateAvg': heartRateAvg,
        if (heartRateMin != null) 'heartRateMin': heartRateMin,
        if (heartRateMax != null) 'heartRateMax': heartRateMax,
        if (stepsInterval != null) 'stepsInterval': stepsInterval,
        if (stepsDaily != null) 'stepsDaily': stepsDaily,
        if (caloriesInterval != null) 'caloriesInterval': caloriesInterval,
        if (caloriesDaily != null) 'caloriesDaily': caloriesDaily,
        if (caloriesActiveInterval != null) 'caloriesActiveInterval': caloriesActiveInterval,
        if (caloriesActiveDaily != null) 'caloriesActiveDaily': caloriesActiveDaily,
        if (distanceInterval != null) 'distanceInterval': distanceInterval,
        if (distanceDaily != null) 'distanceDaily': distanceDaily,
        if (spO2 != null) 'spO2': spO2,
        if (hrv != null) 'hrv': hrv,
      };
}

class DailySummaryValue {
  final String date; // "yyyy-MM-dd" 로컬 기준
  final int? heartRateAvg;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? stepsTotal;
  final double? caloriesTotalKcal;
  final double? distanceTotalM;
  final int? sleepDurationMin;
  final int? sleepDeepMin;
  final int? sleepRemMin;
  final int? exerciseCount;
  final int? exerciseTotalMin;
  final double? exerciseTotalCalories;

  const DailySummaryValue({
    required this.date,
    this.heartRateAvg,
    this.heartRateMin,
    this.heartRateMax,
    this.stepsTotal,
    this.caloriesTotalKcal,
    this.distanceTotalM,
    this.sleepDurationMin,
    this.sleepDeepMin,
    this.sleepRemMin,
    this.exerciseCount,
    this.exerciseTotalMin,
    this.exerciseTotalCalories,
  });

  factory DailySummaryValue.fromJson(Map<String, dynamic> json) => DailySummaryValue(
        date: json['date'] as String,
        heartRateAvg: json['heartRateAvg'] as int?,
        heartRateMin: json['heartRateMin'] as int?,
        heartRateMax: json['heartRateMax'] as int?,
        stepsTotal: json['stepsTotal'] as int?,
        caloriesTotalKcal: (json['caloriesTotalKcal'] as num?)?.toDouble(),
        distanceTotalM: (json['distanceTotalM'] as num?)?.toDouble(),
        sleepDurationMin: json['sleepDurationMin'] as int?,
        sleepDeepMin: json['sleepDeepMin'] as int?,
        sleepRemMin: json['sleepRemMin'] as int?,
        exerciseCount: json['exerciseCount'] as int?,
        exerciseTotalMin: json['exerciseTotalMin'] as int?,
        exerciseTotalCalories: (json['exerciseTotalCalories'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        if (heartRateAvg != null) 'heartRateAvg': heartRateAvg,
        if (heartRateMin != null) 'heartRateMin': heartRateMin,
        if (heartRateMax != null) 'heartRateMax': heartRateMax,
        if (stepsTotal != null) 'stepsTotal': stepsTotal,
        if (caloriesTotalKcal != null) 'caloriesTotalKcal': caloriesTotalKcal,
        if (distanceTotalM != null) 'distanceTotalM': distanceTotalM,
        if (sleepDurationMin != null) 'sleepDurationMin': sleepDurationMin,
        if (sleepDeepMin != null) 'sleepDeepMin': sleepDeepMin,
        if (sleepRemMin != null) 'sleepRemMin': sleepRemMin,
        if (exerciseCount != null) 'exerciseCount': exerciseCount,
        if (exerciseTotalMin != null) 'exerciseTotalMin': exerciseTotalMin,
        if (exerciseTotalCalories != null) 'exerciseTotalCalories': exerciseTotalCalories,
      };
}

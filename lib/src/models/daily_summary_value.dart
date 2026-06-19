class DailySummaryValue {
  final String date; // "yyyy-MM-dd" 로컬 기준
  final int? heartRateAvg;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? stepsTotal;
  final double? caloriesTotal; // kcal (basal + active)
  final double? caloriesActiveTotal; // kcal
  final int? activeTimeTotal; // min
  final double? distanceTotal; // m
  final int? sleepDuration; // min
  final int? exerciseCount;
  final int? exerciseTotalMin;
  final double? exerciseTotalCalories;

  const DailySummaryValue({
    required this.date,
    this.heartRateAvg,
    this.heartRateMin,
    this.heartRateMax,
    this.stepsTotal,
    this.caloriesTotal,
    this.caloriesActiveTotal,
    this.activeTimeTotal,
    this.distanceTotal,
    this.sleepDuration,
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
        caloriesTotal: (json['caloriesTotal'] as num?)?.toDouble(),
        caloriesActiveTotal: (json['caloriesActiveTotal'] as num?)?.toDouble(),
        activeTimeTotal: json['activeTimeTotal'] as int?,
        distanceTotal: (json['distanceTotal'] as num?)?.toDouble(),
        sleepDuration: json['sleepDuration'] as int?,
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
        if (caloriesTotal != null) 'caloriesTotal': caloriesTotal,
        if (caloriesActiveTotal != null) 'caloriesActiveTotal': caloriesActiveTotal,
        if (activeTimeTotal != null) 'activeTimeTotal': activeTimeTotal,
        if (distanceTotal != null) 'distanceTotal': distanceTotal,
        if (sleepDuration != null) 'sleepDuration': sleepDuration,
        if (exerciseCount != null) 'exerciseCount': exerciseCount,
        if (exerciseTotalMin != null) 'exerciseTotalMin': exerciseTotalMin,
        if (exerciseTotalCalories != null) 'exerciseTotalCalories': exerciseTotalCalories,
      };
}

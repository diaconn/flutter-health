class DailySummaryValue {
  final String date; // "yyyy-MM-dd" 로컬 기준
  final int? heartRateAvg;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? stepsTotal;
  final double? caloriesTotal; // kcal (basal + active)
  final double? caloriesActiveTotal; // kcal (active 만)
  final int? activeTimeTotal; // 애플 "운동 시간"(min) — 빠르게 걷기 이상 강도로 움직인 1분마다 적립되는 값, 운동으로 기록한 시간(exerciseTotalMin)과는 다른 값
  final double? distanceTotal; // m
  final int? sleepDuration; // min
  final int? inBedDuration; // min — 취침시간
  final int? exerciseCount; // 운동 기록 개수(시간이 겹쳐도 각각 1개로 센다)
  final int? exerciseTotalMin; // min — 운동한 시간. 겹친 시간은 한 번만 센다
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
    this.inBedDuration,
    this.exerciseCount,
    this.exerciseTotalMin,
    this.exerciseTotalCalories,
  });

  factory DailySummaryValue.fromJson(Map<String, dynamic> json) => DailySummaryValue(
        date: json['date'] as String,
        heartRateAvg: json['heart_rate_avg'] as int?,
        heartRateMin: json['heart_rate_min'] as int?,
        heartRateMax: json['heart_rate_max'] as int?,
        stepsTotal: json['steps_total'] as int?,
        caloriesTotal: (json['calories_total'] as num?)?.toDouble(),
        caloriesActiveTotal: (json['calories_active_total'] as num?)?.toDouble(),
        activeTimeTotal: json['active_time_total'] as int?,
        distanceTotal: (json['distance_total'] as num?)?.toDouble(),
        sleepDuration: json['sleep_duration'] as int?,
        inBedDuration: json['in_bed_duration'] as int?,
        exerciseCount: json['exercise_count'] as int?,
        exerciseTotalMin: json['exercise_total_min'] as int?,
        exerciseTotalCalories: (json['exercise_total_calories'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        if (heartRateAvg != null) 'heart_rate_avg': heartRateAvg,
        if (heartRateMin != null) 'heart_rate_min': heartRateMin,
        if (heartRateMax != null) 'heart_rate_max': heartRateMax,
        if (stepsTotal != null) 'steps_total': stepsTotal,
        if (caloriesTotal != null) 'calories_total': caloriesTotal,
        if (caloriesActiveTotal != null) 'calories_active_total': caloriesActiveTotal,
        if (activeTimeTotal != null) 'active_time_total': activeTimeTotal,
        if (distanceTotal != null) 'distance_total': distanceTotal,
        if (sleepDuration != null) 'sleep_duration': sleepDuration,
        if (inBedDuration != null) 'in_bed_duration': inBedDuration,
        if (exerciseCount != null) 'exercise_count': exerciseCount,
        if (exerciseTotalMin != null) 'exercise_total_min': exerciseTotalMin,
        if (exerciseTotalCalories != null) 'exercise_total_calories': exerciseTotalCalories,
      };
}

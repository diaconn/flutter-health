class ExerciseValue {
  final String exerciseType; // "walking"|"running"|"cycling"|"swimming"|"hiking"|"strength_training"|"yoga"|"elliptical"|"dance"|"other"
  final String? intensity;  // "low"|"medium"|"high"
  final int? durationMin;
  final double? calories;
  final int? heartRateAvg;
  final int? heartRateMax;
  final double? distance;

  const ExerciseValue({
    required this.exerciseType,
    this.intensity,
    this.durationMin,
    this.calories,
    this.heartRateAvg,
    this.heartRateMax,
    this.distance,
  });

  factory ExerciseValue.fromJson(Map<String, dynamic> json) => ExerciseValue(
        exerciseType: json['exerciseType'] as String,
        intensity: json['intensity'] as String?,
        durationMin: json['durationMin'] as int?,
        calories: (json['calories'] as num?)?.toDouble(),
        heartRateAvg: json['heartRateAvg'] as int?,
        heartRateMax: json['heartRateMax'] as int?,
        distance: (json['distance'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'exerciseType': exerciseType,
        if (intensity != null) 'intensity': intensity,
        if (durationMin != null) 'durationMin': durationMin,
        if (calories != null) 'calories': calories,
        if (heartRateAvg != null) 'heartRateAvg': heartRateAvg,
        if (heartRateMax != null) 'heartRateMax': heartRateMax,
        if (distance != null) 'distance': distance,
      };
}

/// 운동 세션 값. iOS(HealthKit)·Android(삼성헬스) 공통 필드만 유지한다.
class ExerciseValue {
  /// 운동 종목 코드(snake_case). 각 플랫폼 SDK 종목 식별자를 그대로 통과시킨다 —
  /// Android = PredefinedExerciseType 이름 소문자(예: "table_tennis","bench_press"),
  /// iOS = HKWorkoutActivityType case 이름 snake_case(예: "cycling","table_tennis").
  /// 비운동/미상은 "other".
  final String exerciseType;

  /// 운동 시간(분). 시작~종료(timestamp~endTimestamp)와 동일 의미의 분 단위 값.
  final int? duration;

  /// 소모 칼로리(kcal).
  final double? calories;

  /// 이동 거리(m). 거리 기반 운동(running·walking·cycling·swimming·hiking)만 채워지고,
  /// 비거리 운동(요가·근력 등)이나 거리 미입력 수동 기록은 null.
  final double? distance;

  final int? heartRateAvg;
  final int? heartRateMax;
  final int? heartRateMin;

  const ExerciseValue({required this.exerciseType, this.duration, this.calories, this.distance, this.heartRateAvg, this.heartRateMax, this.heartRateMin});

  factory ExerciseValue.fromJson(Map<String, dynamic> json) => ExerciseValue(exerciseType: json['exerciseType'] as String, duration: (json['duration'] as num?)?.toInt(), calories: (json['calories'] as num?)?.toDouble(), distance: (json['distance'] as num?)?.toDouble(), heartRateAvg: (json['heartRateAvg'] as num?)?.toInt(), heartRateMax: (json['heartRateMax'] as num?)?.toInt(), heartRateMin: (json['heartRateMin'] as num?)?.toInt());

  Map<String, dynamic> toJson() => {'exerciseType': exerciseType, if (duration != null) 'duration': duration, if (calories != null) 'calories': calories, if (distance != null) 'distance': distance, if (heartRateAvg != null) 'heartRateAvg': heartRateAvg, if (heartRateMax != null) 'heartRateMax': heartRateMax, if (heartRateMin != null) 'heartRateMin': heartRateMin};
}

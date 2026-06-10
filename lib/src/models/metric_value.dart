/// 5분(구간) 지표 + 당일 누적. `*Interval`=조회 구간([from,to]) 값, `*Daily`=당일 자정부터 누적.
class MetricValue {
  final int? heartRateAvg; // 구간 평균 심박수 (bpm)
  final int? heartRateMin; // 구간 최저 심박수 (bpm)
  final int? heartRateMax; // 구간 최고 심박수 (bpm)
  final int? stepsInterval; // 구간 걸음수
  final int? stepsDaily; // 당일 누적 걸음수
  final double? caloriesInterval; // 구간 총 소비 칼로리 (활동+기초대사, kcal) — 음식 섭취 아님
  final double? caloriesDaily; // 당일 누적 총 소비 칼로리 (활동+기초대사, kcal)
  final double? caloriesActiveInterval; // 구간 활동 소비 칼로리 (기초대사 제외, kcal)
  final double? caloriesActiveDaily; // 당일 누적 활동 소비 칼로리 (기초대사 제외, kcal)
  final double? distanceInterval; // 구간 이동 거리 (m)
  final double? distanceDaily; // 당일 누적 이동 거리 (m)

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
      };
}

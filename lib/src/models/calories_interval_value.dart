/// 소비 칼로리 구간(calories_interval) — **벽시계 10분 격자 버킷**의 활동 소비 칼로리(kcal).
/// envelope 의 timestamp/endTimestamp 가 격자 경계(예: 09:00~09:10). `active`=활동 소비(기초대사 제외).
/// 음식 섭취가 아니라 소모량이다.
class CaloriesIntervalValue {
  final double active; // 구간 활동 소비 칼로리 (기초대사 제외, kcal)

  const CaloriesIntervalValue({required this.active});

  factory CaloriesIntervalValue.fromJson(Map<String, dynamic> json) => CaloriesIntervalValue(active: (json['active'] as num).toDouble());

  Map<String, dynamic> toJson() => {'active': active};
}

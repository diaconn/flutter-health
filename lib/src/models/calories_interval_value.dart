/// 소비 칼로리 구간(calories_interval) — **벽시계 10분 격자 버킷**의 소비 칼로리(kcal). metric 에서 분리된 독립 타입.
/// envelope 의 timestamp/endTimestamp 가 격자 경계(예: 09:00~09:10). `total`=총소비(활동+기초대사), `active`=활동소비(기초대사 제외).
/// 음식 섭취가 아니라 소모량이다.
class CaloriesIntervalValue {
  final double total; // 구간 총 소비 칼로리 (활동+기초대사, kcal)
  final double? active; // 구간 활동 소비 칼로리 (기초대사 제외, kcal)

  const CaloriesIntervalValue({required this.total, this.active});

  factory CaloriesIntervalValue.fromJson(Map<String, dynamic> json) => CaloriesIntervalValue(
        total: (json['total'] as num).toDouble(),
        active: (json['active'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'total': total,
        if (active != null) 'active': active,
      };
}

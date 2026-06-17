/// 당일 누적 걸음 수(steps_daily) — 자정부터 수집 시점까지의 누적 합. metric 에서 분리된 독립 타입.
/// 구간 격자가 아니라 "오늘 하루 누적"이라 수집 시마다 최신 누적값 1건을 반환한다(서버는 일자별 max UPSERT).
class StepsDailyValue {
  final int count; // 당일 누적 걸음 수

  const StepsDailyValue({required this.count});

  factory StepsDailyValue.fromJson(Map<String, dynamic> json) =>
      StepsDailyValue(count: (json['count'] as num).toInt());

  Map<String, dynamic> toJson() => {'count': count};
}

/// 수면 값 — 플랫폼별 shape 가 다르다(플러그인은 raw 전달, 정규화·세션 합성은 서버).
/// - iOS: 단계 조각(fragment) 하나당 레코드 1개 → [stage]/[stageValue] 가 채워지고 [stages] 는 null.
/// - Android: 세션 레코드 1개에 [stages] 목록이 중첩 → [durationMin]/[stages] 가 채워지고 [stage]/[stageValue] 는 null.
class SleepValue {
  /// 세션 길이(분) — Android 세션 레코드. iOS 조각은 start/end 로 충분해 보통 null.
  final int? durationMin;

  /// iOS 조각의 애플 원시 단계: in_bed/asleep_unspecified/awake/asleep_core/asleep_deep/asleep_rem.
  final String? stage;

  /// iOS HKCategoryValueSleepAnalysis rawValue(0~5).
  final int? stageValue;

  /// Android 세션 내 단계 목록(삼성 원시 단계명: light/deep/rem/awake/undefined).
  final List<SleepStage>? stages;

  const SleepValue({this.durationMin, this.stage, this.stageValue, this.stages});

  factory SleepValue.fromJson(Map<String, dynamic> json) => SleepValue(
        durationMin: (json['duration_min'] as num?)?.toInt(),
        stage: json['stage'] as String?,
        stageValue: (json['stage_value'] as num?)?.toInt(),
        stages: (json['stages'] as List?)
            ?.map((e) => SleepStage.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
        if (durationMin != null) 'duration_min': durationMin,
        if (stage != null) 'stage': stage,
        if (stageValue != null) 'stage_value': stageValue,
        if (stages != null) 'stages': stages!.map((e) => e.toJson()).toList(growable: false),
      };
}

/// 수면 단계 구간 — Android 세션 내 단계 하나(원시 단계명 + 시작/종료 epoch ms).
class SleepStage {
  final String? stage;
  final int? startTime;
  final int? endTime;

  const SleepStage({this.stage, this.startTime, this.endTime});

  factory SleepStage.fromJson(Map<String, dynamic> json) => SleepStage(
        stage: json['stage'] as String?,
        startTime: (json['start_time'] as num?)?.toInt(),
        endTime: (json['end_time'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        if (stage != null) 'stage': stage,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
      };
}

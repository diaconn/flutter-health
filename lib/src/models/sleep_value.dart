class SleepStageValue {
  final String stage; // "awake" | "light" | "deep" | "rem"
  final int startMs;
  final int endMs;

  const SleepStageValue({required this.stage, required this.startMs, required this.endMs});

  factory SleepStageValue.fromJson(Map<String, dynamic> json) => SleepStageValue(
        stage: json['stage'] as String,
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'stage': stage, 'startMs': startMs, 'endMs': endMs};
}

class SleepValue {
  final int? durationMin;
  final int? awakeMin;
  final int? lightMin;
  final int? deepMin;
  final int? remMin;
  final List<SleepStageValue>? stages;

  const SleepValue({
    this.durationMin,
    this.awakeMin,
    this.lightMin,
    this.deepMin,
    this.remMin,
    this.stages,
  });

  factory SleepValue.fromJson(Map<String, dynamic> json) => SleepValue(
        durationMin: json['durationMin'] as int?,
        awakeMin: json['awakeMin'] as int?,
        lightMin: json['lightMin'] as int?,
        deepMin: json['deepMin'] as int?,
        remMin: json['remMin'] as int?,
        stages: (json['stages'] as List<dynamic>?)
            ?.map((e) => SleepStageValue.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        if (durationMin != null) 'durationMin': durationMin,
        if (awakeMin != null) 'awakeMin': awakeMin,
        if (lightMin != null) 'lightMin': lightMin,
        if (deepMin != null) 'deepMin': deepMin,
        if (remMin != null) 'remMin': remMin,
        if (stages != null) 'stages': stages!.map((e) => e.toJson()).toList(),
      };
}

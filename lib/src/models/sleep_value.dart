class SleepValue {
  final int? durationMin;

  const SleepValue({this.durationMin});

  factory SleepValue.fromJson(Map<String, dynamic> json) => SleepValue(
        durationMin: json['duration_min'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (durationMin != null) 'duration_min': durationMin,
      };
}

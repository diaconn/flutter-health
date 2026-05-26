class HeartRhythmValue {
  final String status; // "detected"|"undefined"

  const HeartRhythmValue({required this.status});

  factory HeartRhythmValue.fromJson(Map<String, dynamic> json) => HeartRhythmValue(
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {'status': status};
}

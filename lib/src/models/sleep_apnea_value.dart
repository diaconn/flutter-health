class SleepApneaValue {
  final String detectedSign; // "detected"|"not_detected"|"undefined"

  const SleepApneaValue({required this.detectedSign});

  factory SleepApneaValue.fromJson(Map<String, dynamic> json) => SleepApneaValue(
        detectedSign: json['detectedSign'] as String,
      );

  Map<String, dynamic> toJson() => {'detectedSign': detectedSign};
}

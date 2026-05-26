class BodyTemperatureValue {
  final double temperature; // 섭씨

  const BodyTemperatureValue({required this.temperature});

  factory BodyTemperatureValue.fromJson(Map<String, dynamic> json) => BodyTemperatureValue(
        temperature: (json['temperature'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'temperature': temperature};
}

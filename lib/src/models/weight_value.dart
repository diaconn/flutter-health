class WeightValue {
  final double weight;
  final double? bmi;
  final double? bodyFat;

  const WeightValue({
    required this.weight,
    this.bmi,
    this.bodyFat,
  });

  factory WeightValue.fromJson(Map<String, dynamic> json) => WeightValue(
        weight: (json['weight'] as num).toDouble(),
        bmi: (json['bmi'] as num?)?.toDouble(),
        bodyFat: (json['bodyFat'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'weight': weight,
        if (bmi != null) 'bmi': bmi,
        if (bodyFat != null) 'bodyFat': bodyFat,
      };
}

class WeightValue {
  final double weight; // kg
  final double? bmi; // kg/m²
  final double? bodyFat; // % (체지방률)

  const WeightValue({required this.weight, this.bmi, this.bodyFat});

  factory WeightValue.fromJson(Map<String, dynamic> json) => WeightValue(weight: (json['weight'] as num).toDouble(), bmi: (json['bmi'] as num?)?.toDouble(), bodyFat: (json['body_fat'] as num?)?.toDouble());

  Map<String, dynamic> toJson() => {'weight': weight, if (bmi != null) 'bmi': bmi, if (bodyFat != null) 'body_fat': bodyFat};
}

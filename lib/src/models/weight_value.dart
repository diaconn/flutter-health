class WeightValue {
  final double weight; // kg
  final double? bmi; // kg/m²
  final double? bodyFat; // % (체지방률) — bodyFatMass = weight × bodyFat/100 로 확인됨
  final double? bodyFatMass; // kg (체지방량)
  final double? fatFree; // % (제지방률)
  final double? fatFreeMass; // kg (제지방량)
  final double? skeletalMuscle; // % (골격근률)
  final double? skeletalMuscleMass; // kg (골격근량)
  final double? muscleMass; // kg (근육량)
  final double? totalBodyWater; // L (체수분량)
  final int? basalMetabolicRate; // kcal/day (기초대사량)

  const WeightValue({required this.weight, this.bmi, this.bodyFat, this.bodyFatMass, this.fatFree, this.fatFreeMass, this.skeletalMuscle, this.skeletalMuscleMass, this.muscleMass, this.totalBodyWater, this.basalMetabolicRate});

  factory WeightValue.fromJson(Map<String, dynamic> json) => WeightValue(weight: (json['weight'] as num).toDouble(), bmi: (json['bmi'] as num?)?.toDouble(), bodyFat: (json['bodyFat'] as num?)?.toDouble(), bodyFatMass: (json['bodyFatMass'] as num?)?.toDouble(), fatFree: (json['fatFree'] as num?)?.toDouble(), fatFreeMass: (json['fatFreeMass'] as num?)?.toDouble(), skeletalMuscle: (json['skeletalMuscle'] as num?)?.toDouble(), skeletalMuscleMass: (json['skeletalMuscleMass'] as num?)?.toDouble(), muscleMass: (json['muscleMass'] as num?)?.toDouble(), totalBodyWater: (json['totalBodyWater'] as num?)?.toDouble(), basalMetabolicRate: (json['basalMetabolicRate'] as num?)?.toInt());

  Map<String, dynamic> toJson() => {'weight': weight, if (bmi != null) 'bmi': bmi, if (bodyFat != null) 'bodyFat': bodyFat, if (bodyFatMass != null) 'bodyFatMass': bodyFatMass, if (fatFree != null) 'fatFree': fatFree, if (fatFreeMass != null) 'fatFreeMass': fatFreeMass, if (skeletalMuscle != null) 'skeletalMuscle': skeletalMuscle, if (skeletalMuscleMass != null) 'skeletalMuscleMass': skeletalMuscleMass, if (muscleMass != null) 'muscleMass': muscleMass, if (totalBodyWater != null) 'totalBodyWater': totalBodyWater, if (basalMetabolicRate != null) 'basalMetabolicRate': basalMetabolicRate};
}

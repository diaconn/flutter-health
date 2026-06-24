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

  factory WeightValue.fromJson(Map<String, dynamic> json) => WeightValue(weight: (json['weight'] as num).toDouble(), bmi: (json['bmi'] as num?)?.toDouble(), bodyFat: (json['body_fat'] as num?)?.toDouble(), bodyFatMass: (json['body_fat_mass'] as num?)?.toDouble(), fatFree: (json['fat_free'] as num?)?.toDouble(), fatFreeMass: (json['fat_free_mass'] as num?)?.toDouble(), skeletalMuscle: (json['skeletal_muscle'] as num?)?.toDouble(), skeletalMuscleMass: (json['skeletal_muscle_mass'] as num?)?.toDouble(), muscleMass: (json['muscle_mass'] as num?)?.toDouble(), totalBodyWater: (json['total_body_water'] as num?)?.toDouble(), basalMetabolicRate: (json['basal_metabolic_rate'] as num?)?.toInt());

  Map<String, dynamic> toJson() => {'weight': weight, if (bmi != null) 'bmi': bmi, if (bodyFat != null) 'body_fat': bodyFat, if (bodyFatMass != null) 'body_fat_mass': bodyFatMass, if (fatFree != null) 'fat_free': fatFree, if (fatFreeMass != null) 'fat_free_mass': fatFreeMass, if (skeletalMuscle != null) 'skeletal_muscle': skeletalMuscle, if (skeletalMuscleMass != null) 'skeletal_muscle_mass': skeletalMuscleMass, if (muscleMass != null) 'muscle_mass': muscleMass, if (totalBodyWater != null) 'total_body_water': totalBodyWater, if (basalMetabolicRate != null) 'basal_metabolic_rate': basalMetabolicRate};
}

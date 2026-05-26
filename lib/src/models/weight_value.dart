class WeightValue {
  final double weight;
  final double? height;
  final double? bmi;
  final double? bodyFat;
  final double? bodyFatMass;
  final double? fatFree;
  final double? fatFreeMass;
  final double? skeletalMuscle;
  final double? skeletalMuscleMass;
  final double? muscleMass;
  final double? totalBodyWater;
  final int? basalMetabolicRate;

  const WeightValue({
    required this.weight,
    this.height,
    this.bmi,
    this.bodyFat,
    this.bodyFatMass,
    this.fatFree,
    this.fatFreeMass,
    this.skeletalMuscle,
    this.skeletalMuscleMass,
    this.muscleMass,
    this.totalBodyWater,
    this.basalMetabolicRate,
  });

  factory WeightValue.fromJson(Map<String, dynamic> json) => WeightValue(
        weight: (json['weight'] as num).toDouble(),
        height: (json['height'] as num?)?.toDouble(),
        bmi: (json['bmi'] as num?)?.toDouble(),
        bodyFat: (json['bodyFat'] as num?)?.toDouble(),
        bodyFatMass: (json['bodyFatMass'] as num?)?.toDouble(),
        fatFree: (json['fatFree'] as num?)?.toDouble(),
        fatFreeMass: (json['fatFreeMass'] as num?)?.toDouble(),
        skeletalMuscle: (json['skeletalMuscle'] as num?)?.toDouble(),
        skeletalMuscleMass: (json['skeletalMuscleMass'] as num?)?.toDouble(),
        muscleMass: (json['muscleMass'] as num?)?.toDouble(),
        totalBodyWater: (json['totalBodyWater'] as num?)?.toDouble(),
        basalMetabolicRate: (json['basalMetabolicRate'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'weight': weight,
        if (height != null) 'height': height,
        if (bmi != null) 'bmi': bmi,
        if (bodyFat != null) 'bodyFat': bodyFat,
        if (bodyFatMass != null) 'bodyFatMass': bodyFatMass,
        if (fatFree != null) 'fatFree': fatFree,
        if (fatFreeMass != null) 'fatFreeMass': fatFreeMass,
        if (skeletalMuscle != null) 'skeletalMuscle': skeletalMuscle,
        if (skeletalMuscleMass != null) 'skeletalMuscleMass': skeletalMuscleMass,
        if (muscleMass != null) 'muscleMass': muscleMass,
        if (totalBodyWater != null) 'totalBodyWater': totalBodyWater,
        if (basalMetabolicRate != null) 'basalMetabolicRate': basalMetabolicRate,
      };
}

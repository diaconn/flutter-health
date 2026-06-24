class NutritionValue {
  final String? mealType; // "breakfast"|"lunch"|"dinner"|"morning_snack"|"afternoon_snack"|"evening_snack"
  final String? title;
  final double? calories;
  final double? totalFat;
  final double? saturatedFat;
  final double? polyunsaturatedFat;
  final double? monounsaturatedFat;
  final double? transFat;
  final double? carbohydrate;
  final double? dietaryFiber;
  final double? sugar;
  final double? protein;
  final double? cholesterol;
  final double? sodium;
  final double? potassium;
  final double? vitaminA;
  final double? vitaminC;
  final double? calcium;
  final double? iron;
  final double? magnesium;
  final double? caffeine;
  final double? vitaminD;

  const NutritionValue({
    this.mealType,
    this.title,
    this.calories,
    this.totalFat,
    this.saturatedFat,
    this.polyunsaturatedFat,
    this.monounsaturatedFat,
    this.transFat,
    this.carbohydrate,
    this.dietaryFiber,
    this.sugar,
    this.protein,
    this.cholesterol,
    this.sodium,
    this.potassium,
    this.vitaminA,
    this.vitaminC,
    this.calcium,
    this.iron,
    this.magnesium,
    this.caffeine,
    this.vitaminD,
  });

  factory NutritionValue.fromJson(Map<String, dynamic> json) => NutritionValue(
        mealType: json['meal_type'] as String?,
        title: json['title'] as String?,
        calories: (json['calories'] as num?)?.toDouble(),
        totalFat: (json['total_fat'] as num?)?.toDouble(),
        saturatedFat: (json['saturated_fat'] as num?)?.toDouble(),
        polyunsaturatedFat: (json['polyunsaturated_fat'] as num?)?.toDouble(),
        monounsaturatedFat: (json['monounsaturated_fat'] as num?)?.toDouble(),
        transFat: (json['trans_fat'] as num?)?.toDouble(),
        carbohydrate: (json['carbohydrate'] as num?)?.toDouble(),
        dietaryFiber: (json['dietary_fiber'] as num?)?.toDouble(),
        sugar: (json['sugar'] as num?)?.toDouble(),
        protein: (json['protein'] as num?)?.toDouble(),
        cholesterol: (json['cholesterol'] as num?)?.toDouble(),
        sodium: (json['sodium'] as num?)?.toDouble(),
        potassium: (json['potassium'] as num?)?.toDouble(),
        vitaminA: (json['vitamin_a'] as num?)?.toDouble(),
        vitaminC: (json['vitamin_c'] as num?)?.toDouble(),
        calcium: (json['calcium'] as num?)?.toDouble(),
        iron: (json['iron'] as num?)?.toDouble(),
        magnesium: (json['magnesium'] as num?)?.toDouble(),
        caffeine: (json['caffeine'] as num?)?.toDouble(),
        vitaminD: (json['vitamin_d'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        if (mealType != null) 'meal_type': mealType,
        if (title != null) 'title': title,
        if (calories != null) 'calories': calories,
        if (totalFat != null) 'total_fat': totalFat,
        if (saturatedFat != null) 'saturated_fat': saturatedFat,
        if (polyunsaturatedFat != null) 'polyunsaturated_fat': polyunsaturatedFat,
        if (monounsaturatedFat != null) 'monounsaturated_fat': monounsaturatedFat,
        if (transFat != null) 'trans_fat': transFat,
        if (carbohydrate != null) 'carbohydrate': carbohydrate,
        if (dietaryFiber != null) 'dietary_fiber': dietaryFiber,
        if (sugar != null) 'sugar': sugar,
        if (protein != null) 'protein': protein,
        if (cholesterol != null) 'cholesterol': cholesterol,
        if (sodium != null) 'sodium': sodium,
        if (potassium != null) 'potassium': potassium,
        if (vitaminA != null) 'vitamin_a': vitaminA,
        if (vitaminC != null) 'vitamin_c': vitaminC,
        if (calcium != null) 'calcium': calcium,
        if (iron != null) 'iron': iron,
        if (magnesium != null) 'magnesium': magnesium,
        if (caffeine != null) 'caffeine': caffeine,
        if (vitaminD != null) 'vitamin_d': vitaminD,
      };
}

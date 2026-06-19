class WaterIntakeValue {
  // 단위: mL (iOS HealthKit·Android Samsung 통일)
  final double amount;

  const WaterIntakeValue({required this.amount});

  factory WaterIntakeValue.fromJson(Map<String, dynamic> json) => WaterIntakeValue(amount: (json['amount'] as num).toDouble());

  Map<String, dynamic> toJson() => {'amount': amount};
}

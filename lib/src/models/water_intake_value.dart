class WaterIntakeValue {
  final double amount; // 단위: SDK 가 내려주는 그대로 (mL 추정)

  const WaterIntakeValue({required this.amount});

  factory WaterIntakeValue.fromJson(Map<String, dynamic> json) => WaterIntakeValue(
        amount: (json['amount'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'amount': amount};
}

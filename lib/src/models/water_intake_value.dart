class WaterIntakeValue {
  final double amount; // 단위: mL (iOS HealthKit·Android Samsung 통일)
  // 이 레코드가 속한 로컬 달력일 안에서 자정부터 이 레코드 시각까지 쌓인 누적 섭취량(러닝 합계).
  // 단위는 amount 와 동일. 같은 날 최신 레코드의 값 = 그날 전체 합계. 미산출 시 null.
  final double? cumulativeToDate;

  const WaterIntakeValue({required this.amount, this.cumulativeToDate});

  factory WaterIntakeValue.fromJson(Map<String, dynamic> json) => WaterIntakeValue(
        amount: (json['amount'] as num).toDouble(),
        cumulativeToDate: (json['cumulativeToDate'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        if (cumulativeToDate != null) 'cumulativeToDate': cumulativeToDate,
      };
}

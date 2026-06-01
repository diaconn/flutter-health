/// 단일 숫자값으로 표현되는 단순 측정 타입(호흡수·키·BMI·보행 지표 등)의 공통 value.
/// dataType 문자열로 측정 종류를 구분하고, [value] 의 단위는 dataType 별로 약속한다
/// (예: respiratory_rate=count/min, height=cm, body_fat=비율 0~1, resting_energy=kcal).
class QuantityValue {
  final double value;

  const QuantityValue({required this.value});

  factory QuantityValue.fromJson(Map<String, dynamic> json) =>
      QuantityValue(value: (json['value'] as num).toDouble());

  Map<String, dynamic> toJson() => {'value': value};
}

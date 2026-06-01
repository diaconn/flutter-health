/// 생리주기 상세(배란검사·자궁경부점액·성생활·임신검사 등) 기록.
/// 타입마다 value 의미가 제각각이라 HealthKit 의 원시 정수값([rawValue])을 그대로 담는다.
/// dataType 문자열로 종류를 구분하고, 해석은 소비 측에서 한다.
class ReproductiveValue {
  final int rawValue;

  const ReproductiveValue({required this.rawValue});

  factory ReproductiveValue.fromJson(Map<String, dynamic> json) =>
      ReproductiveValue(rawValue: (json['rawValue'] as num).toInt());

  Map<String, dynamic> toJson() => {'rawValue': rawValue};
}

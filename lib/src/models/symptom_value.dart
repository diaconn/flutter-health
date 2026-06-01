/// 증상 기록(기침·흉통 등)의 공통 value. dataType 문자열로 증상 종류를 구분한다.
class SymptomValue {
  final String severity; // "not_present"|"mild"|"moderate"|"severe"|"unspecified"

  const SymptomValue({required this.severity});

  factory SymptomValue.fromJson(Map<String, dynamic> json) =>
      SymptomValue(severity: json['severity'] as String);

  Map<String, dynamic> toJson() => {'severity': severity};
}

/// 생리주기 흐름(menstrual_flow) 기록.
class MenstrualFlowValue {
  final String flow; // "unspecified"|"light"|"medium"|"heavy"|"none"

  const MenstrualFlowValue({required this.flow});

  factory MenstrualFlowValue.fromJson(Map<String, dynamic> json) =>
      MenstrualFlowValue(flow: json['flow'] as String);

  Map<String, dynamic> toJson() => {'flow': flow};
}

/// 심전도(ECG) 기록. voltage raw 측정값은 방대해서 제외하고 분류 결과만 담는다.
class EcgValue {
  final String classification; // "sinus_rhythm"|"atrial_fibrillation"|"inconclusive_*"|...
  final double? averageHeartRate; // bpm
  final String symptomsStatus; // "present"|"none"|"not_set"

  const EcgValue({
    required this.classification,
    this.averageHeartRate,
    required this.symptomsStatus,
  });

  factory EcgValue.fromJson(Map<String, dynamic> json) => EcgValue(
        classification: json['classification'] as String,
        averageHeartRate: (json['averageHeartRate'] as num?)?.toDouble(),
        symptomsStatus: json['symptomsStatus'] as String,
      );

  Map<String, dynamic> toJson() => {
        'classification': classification,
        if (averageHeartRate != null) 'averageHeartRate': averageHeartRate,
        'symptomsStatus': symptomsStatus,
      };
}

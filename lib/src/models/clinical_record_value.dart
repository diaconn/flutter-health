/// 임상기록(clinical_*) — 의료기관 연동 데이터. FHIR resource 를 그대로 담는다.
/// dataType 문자열로 종류(알레르기·질환·투약·검사결과 등)를 구분한다.
class ClinicalRecordValue {
  final String recordType;
  final String displayName;
  final String? fhirResourceType; // "AllergyIntolerance"|"Condition"|...
  final String? fhirJson; // FHIR resource 원본 JSON 문자열

  const ClinicalRecordValue({
    required this.recordType,
    required this.displayName,
    this.fhirResourceType,
    this.fhirJson,
  });

  factory ClinicalRecordValue.fromJson(Map<String, dynamic> json) => ClinicalRecordValue(
        recordType: json['recordType'] as String,
        displayName: json['displayName'] as String,
        fhirResourceType: json['fhirResourceType'] as String?,
        fhirJson: json['fhirJson'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'recordType': recordType,
        'displayName': displayName,
        if (fhirResourceType != null) 'fhirResourceType': fhirResourceType,
        if (fhirJson != null) 'fhirJson': fhirJson,
      };
}

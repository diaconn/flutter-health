import 'health_record.dart';

/// 변경 피드(수정/삭제) 조회 결과.
///
/// - iOS: `HKAnchoredObjectQuery` 의 (추가 샘플 · 삭제 객체 UUID · 다음 anchor).
/// - Android(Samsung): `store.readChanges` 의 (UPSERT · DELETE · 다음 pageToken).
class HealthChanges {
  /// 추가·수정된 레코드(각 [HealthRecord.uid] 포함).
  /// iOS 의 "수정"은 HealthKit 이 구 uid 삭제 + 신 uid 추가로 표현하므로, 수정 시
  /// 신규 uid 는 여기에, 구 uid 는 [deletedUids] 에 함께 나타난다.
  final List<HealthRecord> upserted;

  /// 삭제된 레코드의 네이티브 고유 id 목록(iOS=HKDeletedObject.uuid / Android=Change.deleteDataUid).
  final List<String> deletedUids;

  /// 다음 증분 조회용 커서.
  /// - iOS: 직전 조회 이후 델타만 받기 위한 anchor(base64). **최초 호출은 null 로 시작(=기준선)**.
  /// - Android: **항상 null**(플러그인이 내부에서 전 페이지 소진). 증분은 `since`=직전 `to` 로 호출.
  final String? token;

  const HealthChanges({required this.upserted, required this.deletedUids, this.token});

  factory HealthChanges.fromMap(Map<dynamic, dynamic> map) => HealthChanges(upserted: ((map['upserted'] as List?) ?? const []).map((e) => HealthRecord.fromMap(e as Map)).toList(), deletedUids: ((map['deletedUids'] as List?) ?? const []).map((e) => e as String).toList(), token: map['token'] as String?);

  @override
  String toString() => 'HealthChanges(upserted: ${upserted.length}, deletedUids: ${deletedUids.length}, token: ${token == null ? 'null' : '${token!.length}chars'})';
}

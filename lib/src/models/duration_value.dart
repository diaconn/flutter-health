/// 지속시간으로 표현되는 category 기록(마음챙김·양치질·손씻기)의 공통 value.
/// dataType 문자열로 종류를 구분한다.
class DurationValue {
  final int durationSec;

  const DurationValue({required this.durationSec});

  factory DurationValue.fromJson(Map<String, dynamic> json) =>
      DurationValue(durationSec: (json['durationSec'] as num).toInt());

  Map<String, dynamic> toJson() => {'durationSec': durationSec};
}

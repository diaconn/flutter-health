/// 청력검사(audiogram) 한 지점 — 주파수별 좌/우 귀 청력 민감도(dBHL).
class AudiogramPoint {
  final double frequency; // Hz
  final double? leftEarDb;
  final double? rightEarDb;

  const AudiogramPoint({required this.frequency, this.leftEarDb, this.rightEarDb});

  factory AudiogramPoint.fromJson(Map<String, dynamic> json) => AudiogramPoint(
        frequency: (json['frequency'] as num).toDouble(),
        leftEarDb: (json['leftEarDb'] as num?)?.toDouble(),
        rightEarDb: (json['rightEarDb'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        if (leftEarDb != null) 'leftEarDb': leftEarDb,
        if (rightEarDb != null) 'rightEarDb': rightEarDb,
      };
}

/// 청력검사(audiogram) 기록 — 주파수별 민감도 지점들의 묶음.
class AudiogramValue {
  final List<AudiogramPoint> points;

  const AudiogramValue({required this.points});

  factory AudiogramValue.fromJson(Map<String, dynamic> json) => AudiogramValue(
        points: (json['points'] as List)
            .map((e) => AudiogramPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {'points': points.map((e) => e.toJson()).toList()};
}

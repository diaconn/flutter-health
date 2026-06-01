/// 마음 상태(state_of_mind, iOS 17+) 기록.
/// [valence] 는 -1.0(매우 불쾌)~1.0(매우 쾌) 범위. [labels] 는 HKStateOfMind.Label 의 rawValue.
class StateOfMindValue {
  final double valence;
  final String? kind; // "momentary"|"daily"
  final List<int>? labels;

  const StateOfMindValue({required this.valence, this.kind, this.labels});

  factory StateOfMindValue.fromJson(Map<String, dynamic> json) => StateOfMindValue(
        valence: (json['valence'] as num).toDouble(),
        kind: json['kind'] as String?,
        labels: (json['labels'] as List?)?.map((e) => (e as num).toInt()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'valence': valence,
        if (kind != null) 'kind': kind,
        if (labels != null) 'labels': labels,
      };
}

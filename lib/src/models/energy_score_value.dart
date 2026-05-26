class EnergyScoreValue {
  final double score;

  const EnergyScoreValue({required this.score});

  factory EnergyScoreValue.fromJson(Map<String, dynamic> json) => EnergyScoreValue(
        score: (json['score'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'score': score};
}

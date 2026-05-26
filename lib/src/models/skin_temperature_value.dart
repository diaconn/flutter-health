class SkinTemperatureSeriesEntry {
  final double temperature;
  final double? min;
  final double? max;
  final int startMs;
  final int endMs;

  const SkinTemperatureSeriesEntry({
    required this.temperature,
    this.min,
    this.max,
    required this.startMs,
    required this.endMs,
  });

  factory SkinTemperatureSeriesEntry.fromJson(Map<String, dynamic> json) => SkinTemperatureSeriesEntry(
        temperature: (json['temperature'] as num).toDouble(),
        min: (json['min'] as num?)?.toDouble(),
        max: (json['max'] as num?)?.toDouble(),
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        'startMs': startMs,
        'endMs': endMs,
      };
}

class SkinTemperatureValue {
  final double? temperature; // 평균 (점 데이터일 때만)
  final double? min;
  final double? max;
  final List<SkinTemperatureSeriesEntry>? series;

  const SkinTemperatureValue({
    this.temperature,
    this.min,
    this.max,
    this.series,
  });

  factory SkinTemperatureValue.fromJson(Map<String, dynamic> json) => SkinTemperatureValue(
        temperature: (json['temperature'] as num?)?.toDouble(),
        min: (json['min'] as num?)?.toDouble(),
        max: (json['max'] as num?)?.toDouble(),
        series: (json['series'] as List?)
            ?.map((e) => SkinTemperatureSeriesEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        if (temperature != null) 'temperature': temperature,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (series != null) 'series': series!.map((e) => e.toJson()).toList(),
      };
}

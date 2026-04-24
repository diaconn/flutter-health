import 'dart:convert';

import 'metric_value.dart';
import 'sleep_value.dart';
import 'exercise_value.dart';
import 'hourly_summary_value.dart';
import 'daily_summary_value.dart';

class HealthRecord {
  static const String typeMetric = 'metric';
  static const String typeSleep = 'sleep';
  static const String typeExercise = 'exercise';
  static const String typeHourlySummary = 'hourly_summary';
  static const String typeDailySummary = 'daily_summary';

  final String dataType;
  final int timestamp;
  final int endTimestamp;
  final String tzOffset;
  final String source;
  final String valueJson;
  final int createdAt;

  const HealthRecord({
    required this.dataType,
    required this.timestamp,
    required this.endTimestamp,
    required this.tzOffset,
    required this.source,
    required this.valueJson,
    required this.createdAt,
  });

  factory HealthRecord.fromMap(Map<dynamic, dynamic> map) => HealthRecord(
        dataType: map['dataType'] as String,
        timestamp: (map['timestamp'] as num).toInt(),
        endTimestamp: (map['endTimestamp'] as num).toInt(),
        tzOffset: map['tzOffset'] as String,
        source: map['source'] as String,
        valueJson: map['valueJson'] as String,
        createdAt: (map['createdAt'] as num).toInt(),
      );

  MetricValue? get asMetric =>
      dataType == typeMetric ? MetricValue.fromJson(jsonDecode(valueJson) as Map<String, dynamic>) : null;

  SleepValue? get asSleep =>
      dataType == typeSleep ? SleepValue.fromJson(jsonDecode(valueJson) as Map<String, dynamic>) : null;

  ExerciseValue? get asExercise =>
      dataType == typeExercise ? ExerciseValue.fromJson(jsonDecode(valueJson) as Map<String, dynamic>) : null;

  HourlySummaryValue? get asHourlySummary =>
      dataType == typeHourlySummary ? HourlySummaryValue.fromJson(jsonDecode(valueJson) as Map<String, dynamic>) : null;

  DailySummaryValue? get asDailySummary =>
      dataType == typeDailySummary ? DailySummaryValue.fromJson(jsonDecode(valueJson) as Map<String, dynamic>) : null;

  @override
  String toString() => 'HealthRecord(dataType: $dataType, timestamp: $timestamp, source: $source)';
}

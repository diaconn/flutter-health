import 'dart:convert';

import 'metric_value.dart';
import 'sleep_value.dart';
import 'exercise_value.dart';
import 'hourly_summary_value.dart';
import 'daily_summary_value.dart';
import 'weight_value.dart';
import 'blood_glucose_value.dart';
import 'blood_pressure_value.dart';
import 'nutrition_value.dart';
import 'water_intake_value.dart';
import 'floors_climbed_value.dart';
import 'body_temperature_value.dart';
import 'skin_temperature_value.dart';

class HealthRecord {
  static const String typeMetric = 'metric';
  static const String typeSleep = 'sleep';
  static const String typeExercise = 'exercise';
  static const String typeHourlySummary = 'hourly_summary';
  static const String typeDailySummary = 'daily_summary';
  static const String typeWeight = 'weight';
  static const String typeBloodGlucose = 'blood_glucose';
  static const String typeBloodPressure = 'blood_pressure';
  static const String typeNutrition = 'nutrition';
  static const String typeWaterIntake = 'water_intake';
  static const String typeFloorsClimbed = 'floors_climbed';
  static const String typeBodyTemperature = 'body_temperature';
  static const String typeSkinTemperature = 'skin_temperature';

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

  Map<String, dynamic> _decoded() => jsonDecode(valueJson) as Map<String, dynamic>;

  MetricValue? get asMetric => dataType == typeMetric ? MetricValue.fromJson(_decoded()) : null;
  SleepValue? get asSleep => dataType == typeSleep ? SleepValue.fromJson(_decoded()) : null;
  ExerciseValue? get asExercise => dataType == typeExercise ? ExerciseValue.fromJson(_decoded()) : null;
  HourlySummaryValue? get asHourlySummary =>
      dataType == typeHourlySummary ? HourlySummaryValue.fromJson(_decoded()) : null;
  DailySummaryValue? get asDailySummary =>
      dataType == typeDailySummary ? DailySummaryValue.fromJson(_decoded()) : null;
  WeightValue? get asWeight => dataType == typeWeight ? WeightValue.fromJson(_decoded()) : null;
  BloodGlucoseValue? get asBloodGlucose =>
      dataType == typeBloodGlucose ? BloodGlucoseValue.fromJson(_decoded()) : null;
  BloodPressureValue? get asBloodPressure =>
      dataType == typeBloodPressure ? BloodPressureValue.fromJson(_decoded()) : null;
  NutritionValue? get asNutrition =>
      dataType == typeNutrition ? NutritionValue.fromJson(_decoded()) : null;
  WaterIntakeValue? get asWaterIntake =>
      dataType == typeWaterIntake ? WaterIntakeValue.fromJson(_decoded()) : null;
  FloorsClimbedValue? get asFloorsClimbed =>
      dataType == typeFloorsClimbed ? FloorsClimbedValue.fromJson(_decoded()) : null;
  BodyTemperatureValue? get asBodyTemperature =>
      dataType == typeBodyTemperature ? BodyTemperatureValue.fromJson(_decoded()) : null;
  SkinTemperatureValue? get asSkinTemperature =>
      dataType == typeSkinTemperature ? SkinTemperatureValue.fromJson(_decoded()) : null;

  @override
  String toString() => 'HealthRecord(dataType: $dataType, timestamp: $timestamp, source: $source)';
}

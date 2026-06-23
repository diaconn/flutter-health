import 'dart:convert';

import 'blood_glucose_value.dart';
import 'blood_pressure_value.dart';
import 'calories_interval_value.dart';
import 'daily_summary_value.dart';
import 'distance_interval_value.dart';
import 'exercise_value.dart';
import 'heart_rate_interval_value.dart';
import 'height_value.dart';
import 'hourly_summary_value.dart';
import 'nutrition_value.dart';
import 'sleep_value.dart';
import 'step_segment_value.dart';
import 'steps_daily_value.dart';
import 'steps_interval_value.dart';
import 'water_intake_value.dart';
import 'weight_value.dart';

class HealthRecord {
  static const String typeHeartRateInterval = 'heart_rate_interval';
  static const String typeStepsInterval = 'steps_interval';
  static const String typeDistanceInterval = 'distance_interval';
  static const String typeCaloriesInterval = 'calories_interval';
  static const String typeStepsDaily = 'steps_daily';
  static const String typeSleep = 'sleep';
  static const String typeExercise = 'exercise';
  static const String typeHourlySummary = 'hourly_summary';
  static const String typeDailySummary = 'daily_summary';
  static const String typeWeight = 'weight';
  // 체성분 — iOS 는 항목별 독립 타입(원천 1:1). Android 는 body_composition 한 행에 번들(현행 유지).
  static const String typeBmi = 'bmi';
  static const String typeBodyFatPercentage = 'body_fat_percentage';
  static const String typeLeanBodyMass = 'lean_body_mass';
  static const String typeWaistCircumference = 'waist_circumference';
  static const String typeBloodGlucose = 'blood_glucose';
  static const String typeBloodPressure = 'blood_pressure';
  // 영양 — Android 는 nutrition 한 행에 번들, iOS 는 영양소별 독립 타입(nutrition_<영양소>, 서버가 prefix 로 처리).
  static const String typeNutrition = 'nutrition';
  static const String typeWaterIntake = 'water_intake';
  // step_segment·medication·insulin_delivery 는 iOS 전용(Android Samsung SDK 미제공). 플랫폼은 타입 이름이 아니라 source(apple_health/samsung_health)로 구분한다.
  static const String typeStepSegment = 'step_segment';
  static const String typeHeight = 'height';

  final String dataType;
  final int timestamp;
  final int endTimestamp;
  final String tzOffset;
  final String source;
  final String valueJson;
  final int createdAt;

  /// 원본 레코드의 네이티브 고유 id (iOS=HKSample.uuid / Android=HealthDataPoint.uid).
  /// 집계 버킷(heart_rate_interval·steps_interval·distance_interval·calories_interval·steps_daily·요약)은 원본 레코드가 아니라 null.
  final String? uid;

  const HealthRecord({required this.dataType, required this.timestamp, required this.endTimestamp, required this.tzOffset, required this.source, required this.valueJson, required this.createdAt, this.uid});

  factory HealthRecord.fromMap(Map<dynamic, dynamic> map) => HealthRecord(dataType: map['dataType'] as String, timestamp: (map['timestamp'] as num).toInt(), endTimestamp: (map['endTimestamp'] as num).toInt(), tzOffset: map['tzOffset'] as String, source: map['source'] as String, valueJson: map['valueJson'] as String, createdAt: (map['createdAt'] as num).toInt(), uid: map['uid'] as String?);

  Map<String, dynamic> _decoded() => jsonDecode(valueJson) as Map<String, dynamic>;

  HeartRateIntervalValue? get asHeartRateInterval => dataType == typeHeartRateInterval ? HeartRateIntervalValue.fromJson(_decoded()) : null;
  StepsIntervalValue? get asStepsInterval => dataType == typeStepsInterval ? StepsIntervalValue.fromJson(_decoded()) : null;
  DistanceIntervalValue? get asDistanceInterval => dataType == typeDistanceInterval ? DistanceIntervalValue.fromJson(_decoded()) : null;
  CaloriesIntervalValue? get asCaloriesInterval => dataType == typeCaloriesInterval ? CaloriesIntervalValue.fromJson(_decoded()) : null;
  StepsDailyValue? get asStepsDaily => dataType == typeStepsDaily ? StepsDailyValue.fromJson(_decoded()) : null;
  SleepValue? get asSleep => dataType == typeSleep ? SleepValue.fromJson(_decoded()) : null;
  ExerciseValue? get asExercise => dataType == typeExercise ? ExerciseValue.fromJson(_decoded()) : null;
  HourlySummaryValue? get asHourlySummary => dataType == typeHourlySummary ? HourlySummaryValue.fromJson(_decoded()) : null;
  DailySummaryValue? get asDailySummary => dataType == typeDailySummary ? DailySummaryValue.fromJson(_decoded()) : null;
  WeightValue? get asWeight => dataType == typeWeight ? WeightValue.fromJson(_decoded()) : null;
  BloodGlucoseValue? get asBloodGlucose => dataType == typeBloodGlucose ? BloodGlucoseValue.fromJson(_decoded()) : null;
  BloodPressureValue? get asBloodPressure => dataType == typeBloodPressure ? BloodPressureValue.fromJson(_decoded()) : null;
  NutritionValue? get asNutrition => dataType == typeNutrition ? NutritionValue.fromJson(_decoded()) : null;
  WaterIntakeValue? get asWaterIntake => dataType == typeWaterIntake ? WaterIntakeValue.fromJson(_decoded()) : null;
  StepSegmentValue? get asStepSegment => dataType == typeStepSegment ? StepSegmentValue.fromJson(_decoded()) : null;
  HeightValue? get asHeight => dataType == typeHeight ? HeightValue.fromJson(_decoded()) : null;

  @override
  String toString() => 'HealthRecord(dataType: $dataType, timestamp: $timestamp, source: $source)';
}

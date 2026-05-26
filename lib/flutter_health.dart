export 'src/models/health_record.dart';
export 'src/models/metric_value.dart';
export 'src/models/sleep_value.dart';
export 'src/models/exercise_value.dart';
export 'src/models/hourly_summary_value.dart';
export 'src/models/daily_summary_value.dart';
export 'src/models/weight_value.dart';
export 'src/models/blood_glucose_value.dart';
export 'src/models/blood_pressure_value.dart';
export 'src/models/nutrition_value.dart';
export 'src/models/water_intake_value.dart';
export 'src/models/sleep_apnea_value.dart';
export 'src/models/floors_climbed_value.dart';
export 'src/models/energy_score_value.dart';
export 'src/models/body_temperature_value.dart';
export 'src/models/skin_temperature_value.dart';
export 'src/models/heart_rhythm_value.dart';

import 'flutter_health_platform_interface.dart';
import 'src/models/health_record.dart';

class FlutterHealth {
  /// 삼성헬스(Android) / Apple Health(iOS) 가용성 확인.
  /// Android: API 29+ & 삼성헬스 앱 설치 시 true.
  /// iOS: HealthDataAvailable 시 true (iPad는 false).
  Future<bool> isAvailable() => FlutterHealthPlatform.instance.isAvailable();

  /// SDK 연결. Android는 HealthDataStore 초기화, iOS는 즉시 true.
  Future<bool> connect() => FlutterHealthPlatform.instance.connect();

  /// 연결 해제.
  Future<void> disconnect() => FlutterHealthPlatform.instance.disconnect();

  /// 권한이 하나 이상 부여되어 있는지 확인.
  Future<bool> isPermissionGranted() => FlutterHealthPlatform.instance.isPermissionGranted();

  /// 삼성헬스 / HealthKit 권한 UI를 표시. 일부만 허용해도 true 반환.
  Future<bool> requestPermission() => FlutterHealthPlatform.instance.requestPermission();

  /// [from]~[to] 구간의 5분 건강 지표 (metric) 레코드를 반환.
  /// 데이터 없으면 null.
  Future<HealthRecord?> queryMetric(DateTime from, DateTime to) =>
      FlutterHealthPlatform.instance.queryMetric(from, to);

  /// [since]~[to] 구간에 종료된 수면 세션 목록을 반환.
  Future<List<HealthRecord>> queryEndedSleepSessions(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryEndedSleepSessions(since, to);

  /// [since]~[to] 구간에 종료된 운동 세션 목록을 반환.
  Future<List<HealthRecord>> queryEndedExerciseSessions(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryEndedExerciseSessions(since, to);

  /// [hourStart]~[hourEnd] 구간의 시간별 집계 (hourly_summary) 레코드를 반환.
  Future<HealthRecord?> queryHourlySummary(DateTime hourStart, DateTime hourEnd) =>
      FlutterHealthPlatform.instance.queryHourlySummary(hourStart, hourEnd);

  /// [date] 하루의 일별 집계 (daily_summary) 레코드를 반환.
  Future<HealthRecord?> queryDailySummary(DateTime date) =>
      FlutterHealthPlatform.instance.queryDailySummary(date);

  /// [since]~[to] 구간 내 모든 체중 (weight) 측정 목록을 시간순으로 반환.
  Future<List<HealthRecord>> queryWeights(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryWeights(since, to);

  /// [since]~[to] 구간 내 모든 혈당 (blood_glucose) 측정 목록.
  Future<List<HealthRecord>> queryBloodGlucose(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBloodGlucose(since, to);

  /// [since]~[to] 구간 내 모든 혈압 (blood_pressure) 측정 목록.
  Future<List<HealthRecord>> queryBloodPressure(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBloodPressure(since, to);

  /// [since]~[to] 구간 내 모든 영양 (nutrition) 기록.
  Future<List<HealthRecord>> queryNutrition(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryNutrition(since, to);

  /// [since]~[to] 구간 내 모든 수분 섭취 (water_intake) 기록.
  Future<List<HealthRecord>> queryWaterIntake(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryWaterIntake(since, to);

  /// [since]~[to] 구간 내 모든 수면 무호흡 (sleep_apnea) 기록.
  Future<List<HealthRecord>> querySleepApnea(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.querySleepApnea(since, to);

  /// [since]~[to] 구간 내 모든 계단 (floors_climbed) 기록.
  Future<List<HealthRecord>> queryFloorsClimbed(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryFloorsClimbed(since, to);

  /// [since]~[to] 구간의 일별 에너지 점수 (energy_score) 목록.
  Future<List<HealthRecord>> queryEnergyScore(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryEnergyScore(since, to);

  /// [since]~[to] 구간 내 모든 체온 (body_temperature) 측정 목록.
  Future<List<HealthRecord>> queryBodyTemperature(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBodyTemperature(since, to);

  /// [since]~[to] 구간 내 모든 피부 온도 (skin_temperature) 측정 목록.
  Future<List<HealthRecord>> querySkinTemperature(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.querySkinTemperature(since, to);

  /// [since]~[to] 구간 내 부정맥 알림 (heart_rhythm) 기록.
  Future<List<HealthRecord>> queryIrregularHeartRhythm(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryIrregularHeartRhythm(since, to);
}

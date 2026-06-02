export 'src/models/health_record.dart';
export 'src/models/metric_value.dart';
export 'src/models/sleep_value.dart';
export 'src/models/exercise_value.dart';
export 'src/models/hourly_summary_value.dart';
export 'src/models/daily_summary_value.dart';
export 'src/models/weight_value.dart';
export 'src/models/blood_glucose_value.dart';
export 'src/models/blood_pressure_value.dart';
export 'src/models/insulin_delivery_value.dart';
export 'src/models/nutrition_value.dart';
export 'src/models/water_intake_value.dart';
export 'src/models/floors_climbed_value.dart';
export 'src/models/body_temperature_value.dart';
export 'src/models/step_segment_value.dart';
export 'src/models/medication_value.dart';

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

  /// [since]~[to] 구간 내 모든 체중 (weight) 측정 목록을 최신순(timestamp 내림차순)으로 반환.
  Future<List<HealthRecord>> queryWeights(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryWeights(since, to);

  /// [since]~[to] 구간 내 모든 혈당 (blood_glucose) 측정 목록.
  Future<List<HealthRecord>> queryBloodGlucose(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBloodGlucose(since, to);

  /// [since]~[to] 구간 내 모든 혈압 (blood_pressure) 측정 목록.
  Future<List<HealthRecord>> queryBloodPressure(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBloodPressure(since, to);

  /// iOS 전용. [since]~[to] 구간의 인슐린 투여 (insulin_delivery) — 양(IU) + basal/bolus reason.
  /// Android(Samsung) 는 SDK 가 reason 을 안 줘서 항상 빈 리스트. (혈당 레코드 안의 INSULIN_INJECTED 양만 받고 싶으면 [queryBloodGlucose] 사용.)
  Future<List<HealthRecord>> queryInsulinDelivery(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryInsulinDelivery(since, to);

  /// [since]~[to] 구간 내 모든 영양 (nutrition) 기록.
  Future<List<HealthRecord>> queryNutrition(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryNutrition(since, to);

  /// [since]~[to] 구간 내 모든 수분 섭취 (water_intake) 기록.
  Future<List<HealthRecord>> queryWaterIntake(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryWaterIntake(since, to);

  /// [since]~[to] 구간 내 모든 계단 (floors_climbed) 기록.
  Future<List<HealthRecord>> queryFloorsClimbed(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryFloorsClimbed(since, to);

  /// [since]~[to] 구간 내 모든 체온 (body_temperature) 측정 목록.
  Future<List<HealthRecord>> queryBodyTemperature(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBodyTemperature(since, to);

  /// iOS 전용. [since]~[to] 구간의 개별 걸음 구간 (step_segment) 목록을 최신순으로 반환.
  /// metric 의 합산값(stepsDaily)과 달리 각 구간의 시작/종료(envelope timestamp/endTimestamp)
  /// 와 구간별 걸음수(value.count)를 그대로 준다. iPhone·워치가 각각 기록하면 시간이 겹치는
  /// 샘플이 함께 나오므로(value.sourceType = phone/watch/tablet/other 로 구분), 단순 합은 stepsDaily 와 다를 수 있다.
  /// Android(Samsung) 는 미구현이라 빈 리스트.
  Future<List<HealthRecord>> queryStepSegments(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryStepSegments(since, to);

  /// [since]~[to] 구간 복약 이벤트 (medication, iOS 26+) 목록. 그 외 플랫폼/버전은 빈 리스트.
  Future<List<HealthRecord>> queryMedication(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryMedication(since, to);
}

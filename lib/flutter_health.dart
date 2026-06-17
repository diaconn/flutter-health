export 'src/models/health_record.dart';
export 'src/models/heart_rate_value.dart';
export 'src/models/steps_interval_value.dart';
export 'src/models/distance_interval_value.dart';
export 'src/models/calories_interval_value.dart';
export 'src/models/steps_daily_value.dart';
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
export 'src/models/step_segment_value.dart';
export 'src/models/height_value.dart';
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

  /// [since]~[to] 구간의 심박수를 **벽시계 10분 격자 버킷**별 집계(avg/min/max, bpm)로 반환(heart_rate). 완료된(닫힌) 칸만.
  Future<List<HealthRecord>> queryHeartRate(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryHeartRate(since, to);

  /// [since]~[to] 구간의 걸음 수를 **벽시계 10분 격자 버킷**별 합(steps_interval)으로 반환. 완료된 칸만.
  Future<List<HealthRecord>> querySteps(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.querySteps(since, to);

  /// [since]~[to] 구간의 이동 거리를 **벽시계 10분 격자 버킷**별 합(distance_interval, m)으로 반환. 완료된 칸만.
  Future<List<HealthRecord>> queryDistance(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryDistance(since, to);

  /// [since]~[to] 구간의 소비 칼로리를 **벽시계 10분 격자 버킷**별 합(calories_interval, total+active kcal)으로 반환. 완료된 칸만.
  Future<List<HealthRecord>> queryCalories(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryCalories(since, to);

  /// 당일 누적 걸음 수(steps_daily) 1건을 반환. [date] 가 가리키는 날의 자정~수집 시점 누적. 데이터 없으면 빈 리스트.
  Future<List<HealthRecord>> queryStepsDaily(DateTime date) =>
      FlutterHealthPlatform.instance.queryStepsDaily(date);

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

  /// [since]~[to] 구간의 걸음 구간 (step_segment) 목록을 반환. **iOS 전용.** 각 구간의 시작/종료는 envelope
  /// timestamp/endTimestamp, 구간별 걸음수는 value.count. metric 의 합산값(stepsDaily)과 다름.
  /// - iOS: 개별 stepCount 샘플(가변 시작/종료)을 그대로. value.sourceType = phone/watch/tablet/other
  ///   로 기기 구분(iPhone·워치 동시 기록 시 시간 겹침 가능 → 단순 합은 stepsDaily 와 다를 수 있음).
  /// - Android: 미지원(걸음은 walking 운동 세션으로 표시) → 빈 리스트 반환.
  Future<List<HealthRecord>> queryStepSegments(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryStepSegments(since, to);

  /// 키(신장, dataType="height") 목록을 반환. value.value 는 **cm**(양 플랫폼 통일).
  /// - iOS: HealthKit `height` 샘플들을 [since]~[to] 구간에서 반환(최신순).
  /// - Android(Samsung): 사용자 프로필에 설정된 현재 키 1건(시간 범위 무시). 프로필 미설정 시 빈 리스트.
  Future<List<HealthRecord>> queryHeight(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryHeight(since, to);

  /// [since]~[to] 구간 복약 이벤트 (medication, iOS 26+) 목록. 그 외 플랫폼/버전은 빈 리스트.
  Future<List<HealthRecord>> queryMedication(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryMedication(since, to);
}

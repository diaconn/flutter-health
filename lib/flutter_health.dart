export 'src/models/health_record.dart';
export 'src/models/health_changes.dart';
export 'src/models/heart_rate_interval_value.dart';
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
export 'src/models/height_value.dart';
export 'src/models/step_segment_value.dart';

import 'flutter_health_platform_interface.dart';
import 'src/models/health_record.dart';
import 'src/models/health_changes.dart';

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

  /// [since]~[to] 구간의 심박수를 **벽시계 10분 격자 버킷**별 집계(avg/min/max, bpm)로 반환(heart_rate_interval). 완료된(닫힌) 칸만.
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

  /// [since]~[to] 걸음 활동 구간(step_segment). **iOS 전용** — 개별 stepCount 샘플(value.count,
  /// value.sourceType=phone/watch/tablet/other). Android 는 STEPS_INTERVAL 로 수집 → 빈 리스트.
  Future<List<HealthRecord>> queryStepSegments(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryStepSegments(since, to);

  /// 키(신장, dataType="height") 목록을 반환. value.value 는 **cm**(양 플랫폼 통일).
  /// - iOS: HealthKit `height` 샘플들을 [since]~[to] 구간에서 반환(최신순).
  /// - Android(Samsung): 사용자 프로필에 설정된 현재 키 1건(시간 범위 무시). 프로필 미설정 시 빈 리스트.
  Future<List<HealthRecord>> queryHeight(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryHeight(since, to);

  /// [dataType] 의 변경 피드(추가·수정·삭제)를 반환. 삼성헬스/HealthKit 의 신규·편집·삭제를 소스와 1:1로 반영하기 위한 경로.
  ///
  /// - `upserted`: 신규 **또는** 수정된 레코드(각 uid 포함). 순수 추가면 `deletedUids` 는 비고, 수정이면 구 uid 가 `deletedUids` 에 함께 옴.
  /// - `deletedUids`: 삭제된(또는 수정으로 대체된 구버전) 레코드의 uid.
  /// - 증분(cursor) 사용법:
  ///   - iOS: 반환된 [HealthChanges.token](anchor)을 저장 → 다음 호출에 [token] 으로 넘기면 그 이후 델타만.
  ///   - Android: [since]~[to] 변경시각 창. 다음 증분은 [since]=직전 [to] 로 호출(내부에서 전 페이지 소진 → 반환 token 은 항상 null).
  ///
  /// 지원 [dataType]: `sleep`·`exercise`·`nutrition`·`blood_glucose`·`blood_pressure`·`weight`·`water_intake` (그 외는 빈 결과).
  /// 단, 실제 소비는 세션·다건 편집 이슈가 있는 `sleep`·`exercise`·`nutrition` 3종만 변경 피드로 쓰고, 나머지 4종은 API 지원만 하고 일반 조회를 사용한다.
  Future<HealthChanges> queryChanges(String dataType, {DateTime? since, DateTime? to, String? token}) =>
      FlutterHealthPlatform.instance.queryChanges(dataType, since: since, to: to, token: token);
}

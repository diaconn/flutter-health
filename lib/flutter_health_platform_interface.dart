import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_health_method_channel.dart';
import 'src/models/health_record.dart';

abstract class FlutterHealthPlatform extends PlatformInterface {
  FlutterHealthPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterHealthPlatform _instance = MethodChannelFlutterHealth();

  static FlutterHealthPlatform get instance => _instance;

  static set instance(FlutterHealthPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> isAvailable() => throw UnimplementedError();
  Future<bool> connect() => throw UnimplementedError();
  Future<void> disconnect() => throw UnimplementedError();
  Future<bool> isPermissionGranted() => throw UnimplementedError();
  Future<bool> requestPermission() => throw UnimplementedError();
  /// 심박수를 벽시계 10분 격자 버킷(avg/min/max, bpm)별로 반환. metric 에서 분리된 독립 타입(heart_rate). 완료된 칸만.
  Future<List<HealthRecord>> queryHeartRate(DateTime since, DateTime to) => throw UnimplementedError();
  /// 걸음 수를 벽시계 10분 격자 버킷(count)별 합으로 반환(steps_interval). 완료된 칸만.
  Future<List<HealthRecord>> querySteps(DateTime since, DateTime to) => throw UnimplementedError();
  /// 이동 거리를 벽시계 10분 격자 버킷(distance, m)별 합으로 반환(distance_interval). 완료된 칸만.
  Future<List<HealthRecord>> queryDistance(DateTime since, DateTime to) => throw UnimplementedError();
  /// 소비 칼로리를 벽시계 10분 격자 버킷(total/active, kcal)별 합으로 반환(calories_interval). 완료된 칸만.
  Future<List<HealthRecord>> queryCalories(DateTime since, DateTime to) => throw UnimplementedError();
  /// 당일 누적 걸음 수(steps_daily) 1건. [date] 가 가리키는 날의 자정~수집 시점 누적.
  Future<List<HealthRecord>> queryStepsDaily(DateTime date) => throw UnimplementedError();
  Future<List<HealthRecord>> queryEndedSleepSessions(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryEndedExerciseSessions(DateTime since, DateTime to) => throw UnimplementedError();
  Future<HealthRecord?> queryHourlySummary(DateTime hourStart, DateTime hourEnd) => throw UnimplementedError();
  Future<HealthRecord?> queryDailySummary(DateTime date) => throw UnimplementedError();
  Future<List<HealthRecord>> queryWeights(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryBloodGlucose(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryBloodPressure(DateTime since, DateTime to) => throw UnimplementedError();
  /// iOS 전용. `HKQuantityTypeIdentifierInsulinDelivery` 샘플들을 양(IU) + basal/bolus reason 함께 반환.
  /// Android(Samsung) 는 SDK 에 reason 자체가 없어 항상 빈 리스트.
  Future<List<HealthRecord>> queryInsulinDelivery(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryNutrition(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryWaterIntake(DateTime since, DateTime to) => throw UnimplementedError();
  /// 걸음 구간(step_segment)을 시작/종료/걸음수로 반환. **iOS 전용** — 개별 stepCount 샘플
  /// (sourceType phone/watch/tablet/other). Android 는 미지원(걸음은 walking 운동 세션으로 표시) → 빈 리스트.
  Future<List<HealthRecord>> queryStepSegments(DateTime since, DateTime to) => throw UnimplementedError();
  /// 키(신장, cm). iOS=HealthKit height 샘플 / Android=Samsung UserProfile 현재 키 1건.
  Future<List<HealthRecord>> queryHeight(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryMedication(DateTime since, DateTime to) => throw UnimplementedError();
}

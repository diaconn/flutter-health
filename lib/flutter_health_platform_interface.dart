import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_health_method_channel.dart';
import 'src/models/health_changes.dart';
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

  /// 심박수를 벽시계 10분 격자 버킷(avg/min/max, bpm)별로 반환. 완료된 칸만.
  Future<List<HealthRecord>> queryHeartRate(DateTime since, DateTime to) => throw UnimplementedError();

  /// 걸음 수를 벽시계 10분 격자 버킷(count)별 합으로 반환(steps_interval). 완료된 칸만.
  Future<List<HealthRecord>> querySteps(DateTime since, DateTime to) => throw UnimplementedError();

  /// 이동 거리를 벽시계 10분 격자 버킷(distance, m)별 합으로 반환(distance_interval). 완료된 칸만.
  Future<List<HealthRecord>> queryDistance(DateTime since, DateTime to) => throw UnimplementedError();

  /// 소비 칼로리를 벽시계 10분 격자 버킷(total/active, kcal)별 합으로 반환(calories_interval). 완료된 칸만.
  Future<List<HealthRecord>> queryCalories(DateTime since, DateTime to) => throw UnimplementedError();

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

  /// 키(신장, cm). iOS=HealthKit height 샘플 / Android=Samsung UserProfile 현재 키 1건.
  Future<List<HealthRecord>> queryHeight(DateTime since, DateTime to) => throw UnimplementedError();

  /// 변경 피드(추가·수정·삭제). iOS=HKAnchoredObjectQuery(anchor 델타) / Android=readChanges(변경시각 창).
  Future<HealthChanges> queryChanges(String dataType, {DateTime? since, DateTime? to, String? token}) => throw UnimplementedError();
}

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
  Future<HealthRecord?> queryMetric(DateTime from, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryEndedSleepSessions(DateTime since, DateTime to) => throw UnimplementedError();
  Future<List<HealthRecord>> queryEndedExerciseSessions(DateTime since, DateTime to) => throw UnimplementedError();
  Future<HealthRecord?> queryHourlySummary(DateTime hourStart, DateTime hourEnd) => throw UnimplementedError();
  Future<HealthRecord?> queryDailySummary(DateTime date) => throw UnimplementedError();
}

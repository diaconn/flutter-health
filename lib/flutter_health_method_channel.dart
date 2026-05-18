import 'package:flutter/services.dart';

import 'flutter_health_platform_interface.dart';
import 'src/models/health_record.dart';

class MethodChannelFlutterHealth extends FlutterHealthPlatform {
  final methodChannel = const MethodChannel('flutter_health');

  @override
  Future<bool> isAvailable() async =>
      await methodChannel.invokeMethod<bool>('isAvailable') ?? false;

  @override
  Future<bool> connect() async =>
      await methodChannel.invokeMethod<bool>('connect') ?? false;

  @override
  Future<void> disconnect() =>
      methodChannel.invokeMethod<void>('disconnect');

  @override
  Future<bool> isPermissionGranted() async =>
      await methodChannel.invokeMethod<bool>('isPermissionGranted') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await methodChannel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<HealthRecord?> queryMetric(DateTime from, DateTime to) async {
    final result = await methodChannel.invokeMethod<Map>('queryMetric', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    return result == null ? null : HealthRecord.fromMap(result);
  }

  @override
  Future<List<HealthRecord>> queryEndedSleepSessions(DateTime since, DateTime to) async {
    final result = await methodChannel.invokeMethod<List>('queryEndedSleepSessions', {
      'since': since.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    return (result ?? []).map((e) => HealthRecord.fromMap(e as Map)).toList();
  }

  @override
  Future<List<HealthRecord>> queryEndedExerciseSessions(DateTime since, DateTime to) async {
    final result = await methodChannel.invokeMethod<List>('queryEndedExerciseSessions', {
      'since': since.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    return (result ?? []).map((e) => HealthRecord.fromMap(e as Map)).toList();
  }

  @override
  Future<HealthRecord?> queryHourlySummary(DateTime hourStart, DateTime hourEnd) async {
    final result = await methodChannel.invokeMethod<Map>('queryHourlySummary', {
      'hourStart': hourStart.millisecondsSinceEpoch,
      'hourEnd': hourEnd.millisecondsSinceEpoch,
    });
    return result == null ? null : HealthRecord.fromMap(result);
  }

  @override
  Future<HealthRecord?> queryDailySummary(DateTime date) async {
    final result = await methodChannel.invokeMethod<Map>(
        'queryDailySummary', {'date': date.toIso8601String().substring(0, 10)});
    return result == null ? null : HealthRecord.fromMap(result);
  }

  @override
  Future<HealthRecord?> queryLatestWeight(DateTime since, DateTime to) async {
    final result = await methodChannel.invokeMethod<Map>('queryLatestWeight', {
      'since': since.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    return result == null ? null : HealthRecord.fromMap(result);
  }
}

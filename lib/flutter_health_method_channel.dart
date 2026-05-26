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
  Future<List<HealthRecord>> queryEndedSleepSessions(DateTime since, DateTime to) =>
      _queryList('queryEndedSleepSessions', since, to);

  @override
  Future<List<HealthRecord>> queryEndedExerciseSessions(DateTime since, DateTime to) =>
      _queryList('queryEndedExerciseSessions', since, to);

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
  Future<List<HealthRecord>> queryWeights(DateTime since, DateTime to) =>
      _queryList('queryWeights', since, to);

  @override
  Future<List<HealthRecord>> queryBloodGlucose(DateTime since, DateTime to) =>
      _queryList('queryBloodGlucose', since, to);

  @override
  Future<List<HealthRecord>> queryBloodPressure(DateTime since, DateTime to) =>
      _queryList('queryBloodPressure', since, to);

  @override
  Future<List<HealthRecord>> queryNutrition(DateTime since, DateTime to) =>
      _queryList('queryNutrition', since, to);

  @override
  Future<List<HealthRecord>> queryWaterIntake(DateTime since, DateTime to) =>
      _queryList('queryWaterIntake', since, to);

  @override
  Future<List<HealthRecord>> querySleepApnea(DateTime since, DateTime to) =>
      _queryList('querySleepApnea', since, to);

  @override
  Future<List<HealthRecord>> queryFloorsClimbed(DateTime since, DateTime to) =>
      _queryList('queryFloorsClimbed', since, to);

  @override
  Future<List<HealthRecord>> queryEnergyScore(DateTime since, DateTime to) =>
      _queryList('queryEnergyScore', since, to);

  @override
  Future<List<HealthRecord>> queryBodyTemperature(DateTime since, DateTime to) =>
      _queryList('queryBodyTemperature', since, to);

  @override
  Future<List<HealthRecord>> querySkinTemperature(DateTime since, DateTime to) =>
      _queryList('querySkinTemperature', since, to);

  @override
  Future<List<HealthRecord>> queryIrregularHeartRhythm(DateTime since, DateTime to) =>
      _queryList('queryIrregularHeartRhythm', since, to);

  Future<List<HealthRecord>> _queryList(String method, DateTime since, DateTime to) async {
    final List? result;
    try {
      result = await methodChannel.invokeMethod<List>(method, {
        'since': since.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      // iOS HealthKit 미구현 메서드 등 platform-not-implemented 케이스는 빈 리스트로 변환.
      return const [];
    }
    return (result ?? []).map((e) => HealthRecord.fromMap(e as Map)).toList();
  }
}

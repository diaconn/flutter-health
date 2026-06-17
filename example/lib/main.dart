import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_health/flutter_health.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'flutter_health demo',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: const HealthDemoPage(),
  );
}

class HealthDemoPage extends StatefulWidget {
  const HealthDemoPage({super.key});

  @override
  State<HealthDemoPage> createState() => _HealthDemoPageState();
}

class _HealthDemoPageState extends State<HealthDemoPage> {
  final _plugin = FlutterHealth();
  final List<String> _logs = [];

  bool _available = false;
  bool _connected = false;
  bool _permitted = false;
  bool _loopRunning = false;
  Timer? _loopTimer;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    super.dispose();
  }

  void _log(String msg) => setState(() => _logs.insert(0, msg));

  Future<void> _checkAvailability() async {
    try {
      final ok = await _plugin.isAvailable();
      setState(() => _available = ok);
      _log('isAvailable → $ok');
    } catch (e) {
      _log('isAvailable error: $e');
    }
  }

  Future<void> _connect() async {
    try {
      final ok = await _plugin.connect();
      setState(() => _connected = ok);
      _log('connect → $ok');
    } catch (e) {
      _log('connect error: $e');
    }
  }

  Future<void> _requestPermission() async {
    try {
      final ok = await _plugin.requestPermission();
      setState(() => _permitted = ok);
      _log('requestPermission → $ok');
    } catch (e) {
      _log('requestPermission error: $e');
    }
  }

  /// metric 에서 분리된 10분 격자 버킷 타입들(heart_rate·steps_interval·distance_interval·calories_interval).
  /// 데모는 최근 1시간을 조회해 여러 10분 버킷이 보이게 한다(닫힌 칸만 반환).
  Future<void> _queryInterval(String name) async {
    final to = DateTime.now();
    final since = to.subtract(const Duration(hours: 1));
    try {
      final records = switch (name) {
        'heart_rate' => await _plugin.queryHeartRate(since, to),
        'steps_interval' => await _plugin.querySteps(since, to),
        'distance_interval' => await _plugin.queryDistance(since, to),
        'calories_interval' => await _plugin.queryCalories(since, to),
        _ => <HealthRecord>[],
      };
      _logRecords('$name → ${records.length} bucket(s)', records, (r) => '  $name ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}\n${_prettyRecord(r)}');
    } catch (e) {
      _log('$name error: $e');
    }
  }

  /// 당일 누적 걸음(steps_daily) — 오늘 자정~지금 누적 1건.
  Future<void> _queryStepsDaily() async {
    try {
      final records = await _plugin.queryStepsDaily(DateTime.now());
      _logRecords('steps_daily → ${records.length} record(s)', records, (r) => '  steps_daily ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
    } catch (e) {
      _log('steps_daily error: $e');
    }
  }

  /// 10분 루프 1회 — 분리된 격자 타입 전부 + 당일 누적 걸음.
  void _intervalSweep() {
    _queryInterval('heart_rate');
    _queryInterval('steps_interval');
    _queryInterval('distance_interval');
    _queryInterval('calories_interval');
    _queryStepsDaily();
  }

  Future<void> _queryExercise() async {
    final to = DateTime.now();
    final since = DateTime(to.year, to.month, to.day); // 오늘 0시(로컬) — 오늘 종료된 운동만
    try {
      final records = await _plugin.queryEndedExerciseSessions(since, to);
      _logRecords('queryEndedExerciseSessions → ${records.length} session(s)', records, (r) => '  exercise ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}\n${_prettyRecord(r)}');
    } catch (e) {
      _log('queryEndedExerciseSessions error: $e');
    }
  }

  Future<void> _querySleep() async {
    final to = DateTime.now();
    final since = to.subtract(const Duration(hours: 36)); // 날짜 걸친 수면(예: 23시~07시)까지 포함되게 최근 36시간
    try {
      final records = await _plugin.queryEndedSleepSessions(since, to);
      _logRecords('queryEndedSleepSessions → ${records.length} session(s)', records, (r) => '  sleep ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}\n${_prettyRecord(r)}');
    } catch (e) {
      _log('queryEndedSleepSessions error: $e');
    }
  }

  Future<void> _queryHourly() async {
    final now = DateTime.now();
    final hourStart = DateTime(now.year, now.month, now.day, now.hour);
    final hourEnd = hourStart.add(const Duration(hours: 1));
    try {
      final record = await _plugin.queryHourlySummary(hourStart, hourEnd);
      _log('queryHourlySummary [${_fmt(hourStart)}]\n${record == null ? 'null' : _prettyRecord(record)}');
    } catch (e) {
      _log('queryHourlySummary error: $e');
    }
  }

  Future<void> _queryDaily() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    try {
      final record = await _plugin.queryDailySummary(yesterday);
      _log('queryDailySummary [${yesterday.toIso8601String().substring(0, 10)}]\n${record == null ? 'null' : _prettyRecord(record)}');
    } catch (e) {
      _log('queryDailySummary error: $e');
    }
  }

  Future<void> _queryWeight() async {
    final to = DateTime.now();
    final since = to.subtract(const Duration(days: 30)); // 체중/체성분은 매일 측정 안 함 — 최근 30일 최신값 유지
    try {
      final records = await _plugin.queryWeights(since, to);
      _logRecords('queryWeights → ${records.length} record(s)', records, (r) => '  weight ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
    } catch (e) {
      _log('queryWeights error: $e');
    }
  }

  Future<void> _queryListByName(String name) async {
    final to = DateTime.now();
    // 키는 매일 측정 안 함 → 최근 30일 최신값 유지. 그 외(혈당·혈압·영양·물·걸음구간 등)는 오늘치만.
    final since = name == 'height' ? to.subtract(const Duration(days: 30)) : DateTime(to.year, to.month, to.day); // 오늘 0시(로컬)
    try {
      final records = switch (name) {
        'blood_glucose' => await _plugin.queryBloodGlucose(since, to),
        'blood_pressure' => await _plugin.queryBloodPressure(since, to),
        'insulin_delivery' => await _plugin.queryInsulinDelivery(since, to), // iOS 전용
        'medication' => await _plugin.queryMedication(since, to), // iOS 전용 (iOS 26+)
        'nutrition' => await _plugin.queryNutrition(since, to),
        'water_intake' => await _plugin.queryWaterIntake(since, to),
        'step_segment' => await _plugin.queryStepSegments(since, to), // iOS 전용 (Android 미지원 → 빈 리스트)
        'height' => await _plugin.queryHeight(since, to), // iOS=HealthKit 샘플 / Android=UserProfile (cm)
        _ => <HealthRecord>[],
      };
      _logRecords('$name → ${records.length} record(s)', records, (r) => '  $name ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
    } catch (e) {
      _log('$name error: $e');
    }
  }

  void _toggleLoop() {
    if (_loopRunning) {
      _loopTimer?.cancel();
      setState(() => _loopRunning = false);
      _log('10-min loop stopped');
      return;
    }

    setState(() => _loopRunning = true);
    _log('10-min loop started');

    // Fire immediately, then align to next wall-clock 10-min boundary.
    _intervalSweep();

    final now = DateTime.now();
    final msInCycle = (now.minute % 10) * 60000 + now.second * 1000 + now.millisecond;
    final msToNext = 10 * 60000 - msInCycle;
    _loopTimer = Timer(Duration(milliseconds: msToNext), () {
      _intervalSweep();
      _loopTimer = Timer.periodic(const Duration(minutes: 10), (_) => _intervalSweep());
    });
  }

  Future<void> _copyLastLog() async {
    if (_logs.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _logs.first));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied last log to clipboard')));
    }
  }

  /// 전체 로그를 한 덩어리로 클립보드 복사 — 다른 앱(메일/노트/메시지/AirDrop)으로 옮겨 PC에서 분석.
  Future<void> _copyAllLogs() async {
    if (_logs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No logs to copy')));
      }
      return;
    }
    final stamp = DateTime.now().toIso8601String();
    // _logs 는 _log() 가 0번 인덱스에 insert 해서 역시간순 → 시간순으로 뒤집어 출력.
    final ordered = _logs.reversed.toList();
    final buf = StringBuffer()
      ..writeln('── flutter_health_example logs ──')
      ..writeln('exported_at: $stamp')
      ..writeln('count: ${ordered.length}')
      ..writeln('available: $_available · connected: $_connected · permitted: $_permitted')
      ..writeln('────────────────────────────────');
    for (var i = 0; i < ordered.length; i++) {
      buf
        ..writeln()
        ..writeln('[#${i + 1}]')
        ..writeln(ordered[i]);
    }
    final text = buf.toString();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${ordered.length} logs (${text.length} chars)')));
    }
  }

  String _fmt(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtMs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${d.month}/${d.day} ${_fmt(d)}';
  }

  /// 한 쿼리의 레코드를 한 로그 블록으로 출력
  void _logRecords(String header, List<HealthRecord> records, String Function(HealthRecord) line) {
    final buf = StringBuffer(header);
    for (final r in records) {
      buf.write('\n${line(r)}');
    }
    _log(buf.toString());
  }

  /// envelope(공통 7필드) 전체 + 파싱된 value(=valueJson)를 함께 보여준다.
  String _prettyRecord(HealthRecord r) {
    final envelope = <String, dynamic>{
      'dataType': r.dataType,
      'timestamp': r.timestamp,
      'endTimestamp': r.endTimestamp,
      'tzOffset': r.tzOffset,
      'source': r.source,
      'value': _tryDecode(r.valueJson), // 가독성 위해 escape 문자열 대신 nested 객체로
      'createdAt': r.createdAt,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// valueJson 을 객체로 디코드(실패 시 원문 문자열 그대로 반환).
  dynamic _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_health demo'),
        actions: [
          IconButton(icon: const Icon(Icons.copy), tooltip: 'Copy last log', onPressed: _copyLastLog),
          IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Copy ALL logs', onPressed: _copyAllLogs),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Clear logs', onPressed: () => setState(() => _logs.clear())),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(available: _available, connected: _connected, permitted: _permitted),
          const Divider(height: 1),
          // 버튼 영역: 최대 화면 42% 까지만 차지하고 그 이상은 자체 스크롤.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.42),
            child: SingleChildScrollView(
              child: _ButtonGrid(loopRunning: _loopRunning, onConnect: _connect, onRequestPermission: _requestPermission, onQueryInterval: _queryInterval, onQueryStepsDaily: _queryStepsDaily, onQuerySleep: _querySleep, onQueryExercise: _queryExercise, onQueryHourly: _queryHourly, onQueryDaily: _queryDaily, onQueryWeight: _queryWeight, onToggleLoop: _toggleLoop, onQueryByName: _queryListByName),
            ),
          ),
          const Divider(height: 1),
          // 로그 영역: 남은 공간 전체 + 자체 스크롤.
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('No logs yet', style: TextStyle(color: Colors.grey)),
                  )
                // SelectionArea + Text — 스크롤 가능한 ListView 안의 SelectableText 는
                // 스크롤 시 'selection.isValid' assertion 을 던진다. SelectionArea 로 선택/복사를 대신 제공.
                : SelectionArea(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      separatorBuilder: (_, _) => const Divider(height: 8),
                      itemBuilder: (_, i) => Text(_logs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final bool available, connected, permitted;

  const _StatusBar({required this.available, required this.connected, required this.permitted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_chip('Available', available), _chip('Connected', connected), _chip('Permitted', permitted)]),
    );
  }

  Widget _chip(String label, bool on) => Chip(label: Text('$label: ${on ? '✓' : '✗'}'), backgroundColor: on ? Colors.green.shade100 : Colors.red.shade100);
}

/// 플러그인은 공통(Android + iOS) 기능만 노출한다. (전용 기능은 SDK에서 제거됨)
/// 인슐린 투여·투여약은 iOS 전용 구현이라 버튼명에 (iOS) 표기.
class _ButtonGrid extends StatelessWidget {
  final bool loopRunning;
  final VoidCallback onConnect, onRequestPermission;
  final VoidCallback onQueryStepsDaily, onQuerySleep, onQueryExercise;
  final VoidCallback onQueryHourly, onQueryDaily, onQueryWeight, onToggleLoop;
  final Future<void> Function(String) onQueryInterval, onQueryByName;

  const _ButtonGrid({required this.loopRunning, required this.onConnect, required this.onRequestPermission, required this.onQueryInterval, required this.onQueryStepsDaily, required this.onQuerySleep, required this.onQueryExercise, required this.onQueryHourly, required this.onQueryDaily, required this.onQueryWeight, required this.onToggleLoop, required this.onQueryByName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _section('연결 · 권한', [FilledButton(onPressed: onConnect, child: const Text('Connect')), FilledButton(onPressed: onRequestPermission, child: const Text('Request Permission')), FilledButton.tonal(onPressed: onToggleLoop, child: Text(loopRunning ? 'Stop 10-min Loop' : 'Start 10-min Loop'))]),
          // metric 해체 → 10분 격자 버킷 타입 각각 버튼화 (최근 1시간 조회).
          _section('10분 격자 지표', [OutlinedButton(onPressed: () => onQueryInterval('heart_rate'), child: const Text('심박수')), OutlinedButton(onPressed: () => onQueryInterval('steps_interval'), child: const Text('걸음(10분)')), OutlinedButton(onPressed: () => onQueryInterval('distance_interval'), child: const Text('이동 거리')), OutlinedButton(onPressed: () => onQueryInterval('calories_interval'), child: const Text('소비 칼로리'))]),
          _section('걸음·요약', [OutlinedButton(onPressed: onQueryStepsDaily, child: const Text('당일 누적 걸음')), OutlinedButton(onPressed: onQueryHourly, child: const Text('Hourly Summary')), OutlinedButton(onPressed: onQueryDaily, child: const Text('Daily Summary')), OutlinedButton(onPressed: () => onQueryByName('step_segment'), child: const Text('걸음 샘플(iOS)')), OutlinedButton(onPressed: onQuerySleep, child: const Text('수면'))]),
          _section('운동', [OutlinedButton(onPressed: onQueryExercise, child: const Text('운동 세션 (1 day)'))]),
          _section('신체·체성분', [OutlinedButton(onPressed: onQueryWeight, child: const Text('체중·체성분')), OutlinedButton(onPressed: () => onQueryByName('height'), child: const Text('키'))]),
          _section('대사·혈액', [OutlinedButton(onPressed: () => onQueryByName('blood_glucose'), child: const Text('혈당')), OutlinedButton(onPressed: () => onQueryByName('blood_pressure'), child: const Text('혈압')), OutlinedButton(onPressed: () => onQueryByName('nutrition'), child: const Text('영양')), OutlinedButton(onPressed: () => onQueryByName('water_intake'), child: const Text('물 섭취')), OutlinedButton(onPressed: () => onQueryByName('insulin_delivery'), child: const Text('인슐린 투여(값) (iOS)')), OutlinedButton(onPressed: () => onQueryByName('medication'), child: const Text('투여약 복용로그 (iOS)'))]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> buttons) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4, left: 12),
        child: Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
      ),
    ],
  );
}

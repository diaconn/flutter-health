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

  /// 변경 피드 검증용 — 타입별 마지막 token(iOS anchor / Android pageToken) 저장.
  /// 최초 호출은 null(기준선) → 편집/삭제 후 저장된 token 으로 재호출하면 델타가 온다.
  final Map<String, String?> _changeTokens = {};

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

  /// 10분 격자 버킷 타입들(heart_rate_interval·steps_interval·distance_interval·calories_interval).
  /// 데모는 최근 1시간을 조회해 여러 10분 버킷이 보이게 한다(닫힌 칸만 반환).
  Future<void> _queryInterval(String name) async {
    final to = DateTime.now();
    final since = to.subtract(const Duration(hours: 1));
    try {
      final records = switch (name) {
        'heart_rate_interval' => await _plugin.queryHeartRate(since, to),
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

  /// 10분 루프 1회 — 분리된 격자 타입 전부.
  void _intervalSweep() {
    _queryInterval('heart_rate_interval');
    _queryInterval('steps_interval');
    _queryInterval('distance_interval');
    _queryInterval('calories_interval');
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
        'nutrition' => await _plugin.queryNutrition(since, to),
        'water_intake' => await _plugin.queryWaterIntake(since, to),
        'height' => await _plugin.queryHeight(since, to), // iOS=HealthKit 샘플 / Android=UserProfile (cm)
        _ => <HealthRecord>[],
      };
      _logRecords('$name → ${records.length} record(s)', records, (r) => '  $name ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
    } catch (e) {
      _log('$name error: $e');
    }
  }

  /// 변경 피드 조회 — 한 버튼으로 신규 추가·수정·삭제를 확인. `upserted`(신규·수정) + `deletedUids`(삭제·구버전).
  /// - iOS: 저장된 anchor(token) 기준 델타(최초 호출은 전량이 기준선).
  /// - Android: 최근 24h 변경시각 창을 매번 재스캔(별도 기준선 불필요).
  Future<void> _queryChanges(String dataType) async {
    final to = DateTime.now();
    final since = to.subtract(const Duration(hours: 24));
    try {
      final res = await _plugin.queryChanges(dataType, since: since, to: to, token: _changeTokens[dataType]);
      _changeTokens[dataType] = res.token; // 다음 조회용 저장(iOS anchor / Android pageToken)
      // { deleted, upserted } 한 덩어리 객체로 출력(수정=구 uid delete + 신 uid upsert 를 한눈에).
      final obj = <String, dynamic>{
        'deleted': res.deletedUids, // 삭제된 원본 uid (최초 동기화 땐 빈 배열)
        'upserted': [
          for (final r in res.upserted)
            <String, dynamic>{
              'dataType': r.dataType,
              'uid': r.uid,
              'timestamp': r.timestamp,
              'endTimestamp': r.endTimestamp,
              'tzOffset': r.tzOffset,
              'source': r.source,
              'value': _tryDecode(r.valueJson),
              'createdAt': r.createdAt,
            },
        ],
        'token': res.token, // 다음 조회 연속 토큰(iOS anchor / Android pageToken)
      };
      final rawLog = 'changes[$dataType]  (upsert ${res.upserted.length} · delete ${res.deletedUids.length})\n'
          '${const JsonEncoder.withIndent('  ').convert(obj)}';
      // 수면은 새 raw 단계 구조라 사람이 읽기 쉬운 요약을 덧붙인다(iOS=단계 조각별 / Android=세션 내 단계 목록).
      if (dataType == 'sleep' && res.upserted.isNotEmpty) {
        _log('$rawLog\n— 수면 단계 요약 —\n${res.upserted.map(_sleepLine).join('\n')}');
      } else {
        _log(rawLog);
      }
    } catch (e) {
      _log('changes[$dataType] error: $e');
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

  /// 수면 레코드 사람이 읽기 쉬운 한 줄 — iOS=단계 조각(각 uid) / Android=세션+단계 목록.
  String _sleepLine(HealthRecord r) {
    final v = r.asSleep;
    final durMin = (r.endTimestamp - r.timestamp) ~/ 60000;
    if (v == null) return '  sleep ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}';
    if (v.stage != null) {
      // iOS: sleepAnalysis 조각 1개 = 단계 1개.
      return '  [iOS 조각] ${v.stage}  ${durMin}m  ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}  uid=${r.uid ?? '-'}';
    }
    // Android: 세션 1개 + 단계 목록 중첩.
    final stageStr = (v.stages ?? []).map((s) {
      final sMin = ((s.endTime ?? 0) - (s.startTime ?? 0)) ~/ 60000;
      return '${s.stage}=${sMin}m';
    }).join(', ');
    return '  [AND 세션] ${v.durationMin ?? durMin}m  단계[${stageStr.isEmpty ? '없음' : stageStr}]  uid=${r.uid ?? '-'}';
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
              child: _ButtonGrid(loopRunning: _loopRunning, onConnect: _connect, onRequestPermission: _requestPermission, onQueryInterval: _queryInterval, onQueryHourly: _queryHourly, onQueryDaily: _queryDaily, onQueryWeight: _queryWeight, onToggleLoop: _toggleLoop, onQueryByName: _queryListByName, onQueryChanges: _queryChanges),
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
  final VoidCallback onQueryHourly, onQueryDaily, onQueryWeight, onToggleLoop;
  final Future<void> Function(String) onQueryInterval, onQueryByName, onQueryChanges;

  const _ButtonGrid({required this.loopRunning, required this.onConnect, required this.onRequestPermission, required this.onQueryInterval, required this.onQueryHourly, required this.onQueryDaily, required this.onQueryWeight, required this.onToggleLoop, required this.onQueryByName, required this.onQueryChanges});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12), // 상단 상태바(horizontal 12)와 좌측 열 정렬
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _section('연결 · 권한', [FilledButton(onPressed: onConnect, child: const Text('Connect')), FilledButton(onPressed: onRequestPermission, child: const Text('Request Permission')), FilledButton.tonal(onPressed: onToggleLoop, child: Text(loopRunning ? 'Stop 10-min Loop' : 'Start 10-min Loop'))]),
          // metric 해체 → 10분 격자 버킷 타입 각각 버튼화 (최근 1시간 조회).
          _section('10분 격자 지표', [OutlinedButton(onPressed: () => onQueryInterval('heart_rate_interval'), child: const Text('심박수 (최근 1h)')), OutlinedButton(onPressed: () => onQueryInterval('steps_interval'), child: const Text('걸음 수 (최근 1h)')), OutlinedButton(onPressed: () => onQueryInterval('distance_interval'), child: const Text('이동 거리 (최근 1h)')), OutlinedButton(onPressed: () => onQueryInterval('calories_interval'), child: const Text('소비 칼로리 (최근 1h)'))]),
          _section('요약', [OutlinedButton(onPressed: onQueryHourly, child: const Text('Hourly Summary (현재 1h)')), OutlinedButton(onPressed: onQueryDaily, child: const Text('Daily Summary (어제)'))]),
          // 수면·운동·영양은 변경 피드(신규+수정+삭제)로 조회 — 한 버튼으로 추가/편집/삭제 모두 확인.
          _section('수면·운동·영양', [OutlinedButton(onPressed: () => onQueryChanges('sleep'), child: const Text('수면 단계 raw (변경 24h)')), OutlinedButton(onPressed: () => onQueryChanges('exercise'), child: const Text('운동 (변경 24h)')), OutlinedButton(onPressed: () => onQueryChanges('nutrition'), child: const Text('영양 (변경 24h)'))]),
          _section('신체·체성분', [OutlinedButton(onPressed: onQueryWeight, child: const Text('체중·체성분 (최근 30일)')), OutlinedButton(onPressed: () => onQueryByName('height'), child: const Text('키 (최근 30일)'))]),
          _section('대사·혈액', [OutlinedButton(onPressed: () => onQueryChanges('blood_glucose'), child: const Text('혈당 (변경 24h)')), OutlinedButton(onPressed: () => onQueryChanges('blood_pressure'), child: const Text('혈압 (변경 24h)')), OutlinedButton(onPressed: () => onQueryChanges('water_intake'), child: const Text('물 섭취 (변경 24h)')), OutlinedButton(onPressed: () => onQueryByName('insulin_delivery'), child: const Text('인슐린 투여(값) (iOS·오늘)'))]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> buttons) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4), // 좌측 인셋 제거 — 제목·버튼을 ButtonGrid 좌측(12)에 flush
        child: Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: buttons),
    ],
  );
}

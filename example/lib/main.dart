import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_health/flutter_health.dart';

// ── demo 분류 보조 목록 (2026-05-28 PM 5 갱신: 사용자 keep 리스트 반영) ──
// 플러그인의 `QuantityType.activity/cardio/respiratory/metabolic` 은 그대로 두고,
// demo 에서는 필요한 부분집합만 보여주기 위해 로컬 사용 목록을 따로 정의.

/// 비운동 · 보행·활동 지표 (보행 5종만 — 러닝/자전거/계단/6분보행/stand·exercise·move/push/daylight 제외).
const _gaitActivityTypes = <String>[
  QuantityType.walkingSpeed,
  QuantityType.walkingStepLength,
  QuantityType.walkingAsymmetry,
  QuantityType.walkingDoubleSupport,
  QuantityType.walkingSteadiness,
];

/// 비운동 · 심혈관 (안정시 HR · 말초 관류 지수 제외 — keep 리스트에서 빠짐).
const _cardioTypes = <String>[
  QuantityType.walkingHeartRateAvg,
  QuantityType.heartRateRecovery,
  QuantityType.atrialFibrillationBurden,
  QuantityType.vo2max,
];

/// 비운동 · 호흡 (호흡수 · 흡입기 사용 횟수만 — FVC/FEV1/PEF 제외).
const _respiratoryTypes = <String>[
  QuantityType.respiratoryRate,
  QuantityType.inhalerUsage,
];

/// 비운동 · 대사·기타 (인슐린은 전용 `queryInsulinDelivery` 가 대체하므로 제외).
const _metabolicTypes = <String>[
  QuantityType.restingEnergy,
  QuantityType.electrodermalActivity,
  QuantityType.bloodAlcohol,
  QuantityType.numAlcoholicBeverages,
  QuantityType.falls,
];

/// 정신·기타 카테고리 3종(생활) — 마음챙김/양치/손씻기. 심혈관 이벤트는 `CategoryType.cardioEvents` 로 분리.
const _lifestyleCategoryTypes = <String>[
  CategoryType.mindful,
  CategoryType.toothbrushing,
  CategoryType.handwashing,
];

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

  Future<void> _queryMetric() async {
    final to   = DateTime.now();
    final from = to.subtract(const Duration(minutes: 5));
    try {
      final record = await _plugin.queryMetric(from, to);
      if (record == null) {
        _log('queryMetric → null');
      } else {
        _log('metric [${_fmt(from)}–${_fmt(to)}]\n${_prettyRecord(record)}');
      }
    } catch (e) {
      _log('queryMetric error: $e');
    }
  }

  Future<void> _queryExercise() async {
    final to    = DateTime.now();
    final since = to.subtract(const Duration(days: 1));
    try {
      final records = await _plugin.queryEndedExerciseSessions(since, to);
      _log('queryEndedExerciseSessions → ${records.length} session(s)');
      for (final r in records) {
        _log('  exercise ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}\n${_prettyRecord(r)}');
      }
    } catch (e) {
      _log('queryEndedExerciseSessions error: $e');
    }
  }

  Future<void> _queryHourly() async {
    final now       = DateTime.now();
    final hourStart = DateTime(now.year, now.month, now.day, now.hour);
    final hourEnd   = hourStart.add(const Duration(hours: 1));
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
    final to    = DateTime.now();
    final since = to.subtract(const Duration(days: 30));
    try {
      final records = await _plugin.queryWeights(since, to);
      _log('queryWeights → ${records.length} record(s)');
      for (final r in records.take(5)) {
        _log('  weight ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
      }
    } catch (e) {
      _log('queryWeights error: $e');
    }
  }

  Future<void> _queryListByName(String name) async {
    final to    = DateTime.now();
    final since = to.subtract(const Duration(days: 30));
    try {
      final records = switch (name) {
        'blood_glucose'    => await _plugin.queryBloodGlucose(since, to),
        'blood_pressure'   => await _plugin.queryBloodPressure(since, to),
        'insulin_delivery' => await _plugin.queryInsulinDelivery(since, to),
        'nutrition'        => await _plugin.queryNutrition(since, to),
        'water_intake'    => await _plugin.queryWaterIntake(since, to),
        'sleep_apnea'     => await _plugin.querySleepApnea(since, to),
        'floors_climbed'  => await _plugin.queryFloorsClimbed(since, to),
        'energy_score'    => await _plugin.queryEnergyScore(since, to),
        'body_temperature'=> await _plugin.queryBodyTemperature(since, to),
        'skin_temperature'=> await _plugin.querySkinTemperature(since, to),
        'heart_rhythm'    => await _plugin.queryIrregularHeartRhythm(since, to),
        _ => <HealthRecord>[],
      };
      _log('$name → ${records.length} record(s)');
      for (final r in records.take(5)) {
        _log('  $name ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
      }
    } catch (e) {
      _log('$name error: $e');
    }
  }

  Future<void> _queryQuantityList(String label, List<String> types) async {
    final to    = DateTime.now();
    final since = to.subtract(const Duration(days: 30));
    var total = 0;
    for (final t in types) {
      try {
        final rs = await _plugin.queryQuantity(t, since, to);
        total += rs.length;
        for (final r in rs.take(2)) {
          _log('  $t ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
        }
      } catch (e) {
        _log('$t error: $e');
      }
    }
    _log('$label → $total record(s) / ${types.length} types');
  }

  Future<void> _queryGroup(String group) async {
    final to    = DateTime.now();
    final since = to.subtract(const Duration(days: 30));
    try {
      switch (group) {
        case 'q_body':              await _queryQuantityList('신체측정', QuantityType.body);
        case 'q_activity_gait':     await _queryQuantityList('보행·활동', _gaitActivityTypes);
        case 'q_workout_attached':  await _queryQuantityList('운동 부속(효과점수·수중)', QuantityType.workoutAttached);
        case 'q_diagnostic':        await _queryQuantityList('SpO2·HRV 30d(진단)', QuantityType.diagnostic);
        case 'q_cardio':            await _queryQuantityList('심혈관', _cardioTypes);
        case 'q_respiratory':       await _queryQuantityList('호흡', _respiratoryTypes);
        case 'q_metabolic':         await _queryQuantityList('대사·기타', _metabolicTypes);
        case 'categories':
          var total = 0;
          for (final t in _lifestyleCategoryTypes) {
            final rs = await _plugin.queryCategory(t, since, to);
            total += rs.length;
            for (final r in rs.take(2)) {
              _log('  $t ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
            }
          }
          _log('categories → $total record(s) / ${_lifestyleCategoryTypes.length} types');
        case 'categories_cardio':
          var total = 0;
          for (final t in CategoryType.cardioEvents) {
            final rs = await _plugin.queryCategory(t, since, to);
            total += rs.length;
            for (final r in rs.take(5)) {
              _log('  $t ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
            }
          }
          _log('categories_cardio → $total record(s) / ${CategoryType.cardioEvents.length} types');
        case 'symptoms':
          var total = 0;
          for (final t in SymptomType.all) {
            final rs = await _plugin.querySymptom(t, since, to);
            total += rs.length;
            for (final r in rs.take(2)) {
              _log('  $t ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
            }
          }
          _log('symptoms → $total record(s) / ${SymptomType.all.length} types');
        case 'menstrual':
          final rs = await _plugin.queryMenstrualFlow(since, to);
          _log('menstrual_flow → ${rs.length} record(s)');
          for (final r in rs.take(5)) {
            _log('  menstrual ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
          }
        case 'mind':
          final rs = await _plugin.queryStateOfMind(since, to);
          _log('state_of_mind → ${rs.length} record(s)');
          for (final r in rs.take(5)) {
            _log('  mind ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
          }
        case 'ecg':
          final rs = await _plugin.queryEcg(since, to);
          _log('ecg → ${rs.length} record(s)');
          for (final r in rs.take(5)) {
            _log('  ecg ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
          }
        case 'reproductive':
          var total = 0;
          for (final t in ReproductiveType.all) {
            final rs = await _plugin.queryReproductive(t, since, to);
            total += rs.length;
            for (final r in rs.take(2)) {
              _log('  $t ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
            }
          }
          _log('reproductive → $total record(s) / ${ReproductiveType.all.length} types');
        case 'workout_route':
          final rs = await _plugin.queryWorkoutRoutes(since, to);
          _log('workout_route → ${rs.length} record(s)');
          for (final r in rs.take(3)) {
            _log('  route ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
          }
        case 'clinical':
          var total = 0;
          for (final t in ClinicalType.all) {
            final rs = await _plugin.queryClinical(t, since, to);
            total += rs.length;
            for (final r in rs.take(2)) {
              _log('  $t ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
            }
          }
          _log('clinical → $total record(s) / ${ClinicalType.all.length} types (entitlement 필요)');
        case 'medication':
          final rs = await _plugin.queryMedication(since, to);
          _log('medication → ${rs.length} record(s) (iOS 26+)');
          for (final r in rs.take(5)) {
            _log('  medication ${_fmtMs(r.timestamp)}\n${_prettyRecord(r)}');
          }
      }
    } catch (e) {
      _log('$group error: $e');
    }
  }

  void _toggleLoop() {
    if (_loopRunning) {
      _loopTimer?.cancel();
      setState(() => _loopRunning = false);
      _log('5-min loop stopped');
      return;
    }

    setState(() => _loopRunning = true);
    _log('5-min loop started');

    // Fire immediately, then align to next wall-clock 5-min boundary.
    _queryMetric();

    final now        = DateTime.now();
    final msInCycle  = (now.minute % 5) * 60000 + now.second * 1000 + now.millisecond;
    final msToNext   = 5 * 60000 - msInCycle;
    _loopTimer = Timer(Duration(milliseconds: msToNext), () {
      _queryMetric();
      _loopTimer = Timer.periodic(const Duration(minutes: 5), (_) => _queryMetric());
    });
  }

  Future<void> _copyLastLog() async {
    if (_logs.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _logs.first));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied last log to clipboard')),
      );
    }
  }

  /// 전체 로그를 한 덩어리로 클립보드 복사 — 다른 앱(메일/노트/메시지/AirDrop)으로 옮겨 PC에서 분석.
  Future<void> _copyAllLogs() async {
    if (_logs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No logs to copy')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${ordered.length} logs (${text.length} chars)')),
      );
    }
  }

  String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtMs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${d.month}/${d.day} ${_fmt(d)}';
  }

  /// envelope(공통 7필드) 전체 + 파싱된 value(=valueJson)를 함께 보여준다.
  /// 기존 _prettyJson 은 valueJson 만 떼서 출력했지만, 29개 dataType 모두
  /// 동일한 envelope 으로 감싸 온다는 점을 demo 에서도 그대로 노출하려고 교체.
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
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy last log',
            onPressed: _copyLastLog,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Copy ALL logs',
            onPressed: _copyAllLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(available: _available, connected: _connected, permitted: _permitted),
          const Divider(height: 1),
          // 버튼 영역: 최대 화면 42% 까지만 차지하고 그 이상은 자체 스크롤.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.42,
            ),
            child: SingleChildScrollView(
              child: _ButtonGrid(
                available: _available,
                connected: _connected,
                loopRunning: _loopRunning,
                onConnect: _connect,
                onRequestPermission: _requestPermission,
                onQueryMetric: _queryMetric,
                onQueryExercise: _queryExercise,
                onQueryHourly: _queryHourly,
                onQueryDaily: _queryDaily,
                onQueryWeight: _queryWeight,
                onToggleLoop: _toggleLoop,
                onQueryByName: _queryListByName,
                onQueryGroup: _queryGroup,
              ),
            ),
          ),
          const Divider(height: 1),
          // 로그 영역: 남은 공간 전체 + 자체 스크롤.
          Expanded(
            child: _logs.isEmpty
                ? const Center(child: Text('No logs yet', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    separatorBuilder: (_, _) => const Divider(height: 8),
                    itemBuilder: (_, i) => SelectableText(
                      _logs[i],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _chip('Available', available),
          _chip('Connected', connected),
          _chip('Permitted', permitted),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on) => Chip(
        label: Text('$label: ${on ? '✓' : '✗'}'),
        backgroundColor: on ? Colors.green.shade100 : Colors.red.shade100,
      );
}

class _ButtonGrid extends StatelessWidget {
  final bool available, connected, loopRunning;
  final VoidCallback onConnect, onRequestPermission;
  final VoidCallback onQueryMetric, onQueryExercise;
  final VoidCallback onQueryHourly, onQueryDaily, onQueryWeight, onToggleLoop;
  final Future<void> Function(String) onQueryByName;
  final Future<void> Function(String) onQueryGroup;

  const _ButtonGrid({
    required this.available,
    required this.connected,
    required this.loopRunning,
    required this.onConnect,
    required this.onRequestPermission,
    required this.onQueryMetric,
    required this.onQueryExercise,
    required this.onQueryHourly,
    required this.onQueryDaily,
    required this.onQueryWeight,
    required this.onToggleLoop,
    required this.onQueryByName,
    required this.onQueryGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _section('연결 · 권한', [
            FilledButton(onPressed: onConnect, child: const Text('Connect')),
            FilledButton(onPressed: onRequestPermission, child: const Text('Request Permission')),
            FilledButton.tonal(
              onPressed: onToggleLoop,
              child: Text(loopRunning ? 'Stop 5-min Loop' : 'Start 5-min Loop'),
            ),
          ]),

          // ═══════════════════ 비운동 데이터 ═══════════════════
          _groupHeader('비운동 데이터'),

          _platformHeader('공통 (Android + iOS)'),
          _section('기본지표', [
            OutlinedButton(onPressed: onQueryMetric, child: const Text('Metric (걸음·칼로리·거리·심박·SpO2)')),
            OutlinedButton(onPressed: onQueryHourly, child: const Text('Hourly Summary')),
            OutlinedButton(onPressed: onQueryDaily,  child: const Text('Daily Summary')),
            OutlinedButton(onPressed: () => onQueryByName('floors_climbed'), child: const Text('층수')),
          ]),
          _section('수면', [
            // '수면 단계 (1 day)' 버튼 제거 — iOS 에서 수면 단계는 Apple Watch 자동 추적 전용이라 워치 없이 무의미.
            OutlinedButton(onPressed: () => onQueryByName('sleep_apnea'),  child: const Text('수면무호흡')),
          ]),
          _section('신체·체성분', [
            OutlinedButton(onPressed: onQueryWeight, child: const Text('체중·체성분 (30 day)')),
          ]),
          _section('대사·혈액', [
            OutlinedButton(onPressed: () => onQueryByName('blood_glucose'),  child: const Text('혈당 (식사관계·검체·인슐린·투여약 동반)')),
            OutlinedButton(onPressed: () => onQueryByName('blood_pressure'), child: const Text('혈압')),
            OutlinedButton(onPressed: () => onQueryByName('nutrition'),      child: const Text('영양·탄수화물·칼로리')),
            OutlinedButton(onPressed: () => onQueryByName('water_intake'),   child: const Text('물 섭취')),
          ]),
          _section('체온', [
            OutlinedButton(onPressed: () => onQueryByName('body_temperature'), child: const Text('체온')),
            OutlinedButton(onPressed: () => onQueryByName('skin_temperature'), child: const Text('피부 온도')),
          ]),
          _section('심혈관', [
            OutlinedButton(onPressed: () => onQueryByName('heart_rhythm'), child: const Text('불규칙 심장리듬')),
          ]),

          _platformHeader('Android 전용'),
          _section('정신·기타', [
            OutlinedButton(onPressed: () => onQueryByName('energy_score'), child: const Text('에너지 점수')),
          ]),

          _platformHeader('iOS 전용'),
          _section('신체측정', [
            OutlinedButton(onPressed: () => onQueryGroup('q_body'), child: const Text('허리둘레·기초체온 등')),
          ]),
          _section('보행·활동', [
            OutlinedButton(onPressed: () => onQueryGroup('q_activity_gait'), child: const Text('보행속도·계단·러닝/자전거 지표')),
          ]),
          _section('심혈관', [
            OutlinedButton(onPressed: () => onQueryGroup('q_cardio'),          child: const Text('걷기HR평균·HR회복·AFib·VO2max')),
            OutlinedButton(onPressed: () => onQueryGroup('ecg'),               child: const Text('ECG')),
            OutlinedButton(onPressed: () => onQueryGroup('categories_cardio'), child: const Text('고/저 심박 이벤트')),
            OutlinedButton(onPressed: () => onQueryGroup('q_diagnostic'),      child: const Text('SpO2·HRV 30d 진단')),
          ]),
          _section('호흡', [
            OutlinedButton(onPressed: () => onQueryGroup('q_respiratory'), child: const Text('호흡수·흡입기')),
          ]),
          _section('대사·기타', [
            OutlinedButton(onPressed: () => onQueryByName('insulin_delivery'), child: const Text('인슐린(IU + basal/bolus)')),
            OutlinedButton(onPressed: () => onQueryGroup('q_metabolic'),       child: const Text('휴식에너지·EDA·알코올·낙상')),
            OutlinedButton(onPressed: () => onQueryGroup('clinical'),          child: const Text('임상기록 (FHIR · entitlement 필요)')),
            OutlinedButton(onPressed: () => onQueryGroup('medication'),        child: const Text('투여약 (iOS 26+)')),
          ]),
          // 환경·청력 섹션 제거 — 사용자 keep 리스트에서 자외선·소음·헤드폰음량·청력검사 모두 빠짐.
          _section('정신·기타', [
            OutlinedButton(onPressed: () => onQueryGroup('categories'), child: const Text('마음챙김·양치·손씻기')),
            OutlinedButton(onPressed: () => onQueryGroup('symptoms'),   child: Text('증상 (${SymptomType.all.length})')),
            OutlinedButton(onPressed: () => onQueryGroup('mind'),       child: const Text('마음 상태')),
          ]),
          _section('생식·건강', [
            OutlinedButton(onPressed: () => onQueryGroup('menstrual'),    child: const Text('생리주기 흐름')),
            OutlinedButton(onPressed: () => onQueryGroup('reproductive'), child: const Text('생리주기 상세')),
          ]),

          // ═══════════════════ 운동 데이터 ═══════════════════
          _groupHeader('운동 데이터'),

          _platformHeader('공통 (Android + iOS)'),
          _section('운동', [
            OutlinedButton(onPressed: onQueryExercise, child: const Text('운동 세션 (1 day)')),
          ]),

          _platformHeader('iOS 전용'),
          _section('운동', [
            OutlinedButton(onPressed: () => onQueryGroup('workout_route'),      child: const Text('운동경로 GPS')),
            OutlinedButton(onPressed: () => onQueryGroup('q_workout_attached'), child: const Text('운동 효과점수·수중깊이·수온(iOS 16/18+)')),
          ]),

          _platformHeader('Android 전용'),
          _note('운동 세션 JSON 내 필드로 제공 (거리·종목·속도·파워·케이던스·VO2max·수영로그·경로 등) — 별도 쿼리 없음'),

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

  /// 비운동/운동 같은 최상위 그룹 헤더.
  Widget _groupHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 2),
        child: Row(children: [
          const Expanded(child: Divider(thickness: 2, color: Colors.teal)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.teal),
            ),
          ),
          const Expanded(child: Divider(thickness: 2, color: Colors.teal)),
        ]),
      );

  /// 공통/Android전용/iOS전용 같은 플랫폼 sub-헤더.
  Widget _platformHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 10, left: 4),
        child: Text(
          '▸ $title',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
        ),
      );

  /// 카테고리가 비어있을 때의 안내 문구.
  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, left: 16, right: 8, bottom: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
        ),
      );
}

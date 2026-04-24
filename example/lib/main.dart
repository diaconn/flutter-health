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

  Future<void> _queryMetric() async {
    final to   = DateTime.now();
    final from = to.subtract(const Duration(minutes: 5));
    try {
      final record = await _plugin.queryMetric(from, to);
      if (record == null) {
        _log('queryMetric → null');
      } else {
        _log('metric [${_fmt(from)}–${_fmt(to)}]\n${_prettyJson(record.valueJson)}');
      }
    } catch (e) {
      _log('queryMetric error: $e');
    }
  }

  Future<void> _querySleep() async {
    final to    = DateTime.now();
    final since = to.subtract(const Duration(days: 1));
    try {
      final records = await _plugin.queryEndedSleepSessions(since, to);
      _log('queryEndedSleepSessions → ${records.length} session(s)');
      for (final r in records) {
        _log('  sleep ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}\n${_prettyJson(r.valueJson)}');
      }
    } catch (e) {
      _log('queryEndedSleepSessions error: $e');
    }
  }

  Future<void> _queryExercise() async {
    final to    = DateTime.now();
    final since = to.subtract(const Duration(days: 1));
    try {
      final records = await _plugin.queryEndedExerciseSessions(since, to);
      _log('queryEndedExerciseSessions → ${records.length} session(s)');
      for (final r in records) {
        _log('  exercise ${_fmtMs(r.timestamp)}–${_fmtMs(r.endTimestamp)}\n${_prettyJson(r.valueJson)}');
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
      _log('queryHourlySummary [${_fmt(hourStart)}]\n${record == null ? 'null' : _prettyJson(record.valueJson)}');
    } catch (e) {
      _log('queryHourlySummary error: $e');
    }
  }

  Future<void> _queryDaily() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    try {
      final record = await _plugin.queryDailySummary(yesterday);
      _log('queryDailySummary [${yesterday.toIso8601String().substring(0, 10)}]\n${record == null ? 'null' : _prettyJson(record.valueJson)}');
    } catch (e) {
      _log('queryDailySummary error: $e');
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
        const SnackBar(content: Text('Copied to clipboard')),
      );
    }
  }

  String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtMs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${d.month}/${d.day} ${_fmt(d)}';
  }

  String _prettyJson(String raw) {
    try {
      final obj = jsonDecode(raw);
      return const JsonEncoder.withIndent('  ').convert(obj);
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
          _ButtonGrid(
            available: _available,
            connected: _connected,
            loopRunning: _loopRunning,
            onConnect: _connect,
            onRequestPermission: _requestPermission,
            onQueryMetric: _queryMetric,
            onQuerySleep: _querySleep,
            onQueryExercise: _queryExercise,
            onQueryHourly: _queryHourly,
            onQueryDaily: _queryDaily,
            onToggleLoop: _toggleLoop,
          ),
          const Divider(height: 1),
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
  final VoidCallback onQueryMetric, onQuerySleep, onQueryExercise;
  final VoidCallback onQueryHourly, onQueryDaily, onToggleLoop;

  const _ButtonGrid({
    required this.available,
    required this.connected,
    required this.loopRunning,
    required this.onConnect,
    required this.onRequestPermission,
    required this.onQueryMetric,
    required this.onQuerySleep,
    required this.onQueryExercise,
    required this.onQueryHourly,
    required this.onQueryDaily,
    required this.onToggleLoop,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(onPressed: onConnect, child: const Text('Connect')),
          FilledButton(onPressed: onRequestPermission, child: const Text('Request Permission')),
          OutlinedButton(onPressed: onQueryMetric, child: const Text('Metric (5 min)')),
          OutlinedButton(onPressed: onQuerySleep, child: const Text('Sleep (1 day)')),
          OutlinedButton(onPressed: onQueryExercise, child: const Text('Exercise (1 day)')),
          OutlinedButton(onPressed: onQueryHourly, child: const Text('Hourly Summary')),
          OutlinedButton(onPressed: onQueryDaily, child: const Text('Daily Summary')),
          FilledButton.tonal(
            onPressed: onToggleLoop,
            child: Text(loopRunning ? 'Stop 5-min Loop' : 'Start 5-min Loop'),
          ),
        ],
      ),
    );
  }
}

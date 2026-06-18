# flutter_health

삼성헬스(Android) 및 Apple HealthKit(iOS) 데이터를 Flutter 앱에서 조회하는 사내 전용 플러그인.

diaconn-aid-android / diaconn-aid-ios의 수집 스키마와 완벽히 호환되어 서버(`/aid/health-records/sync`)에 동일 JSON을 전송할 수 있습니다.

---

## 설치

`pubspec.yaml`에 path 의존성으로 추가합니다.

```yaml
dependencies:
  flutter_health:
    path: ../flutter_health   # 실제 경로로 조정
```

---

## 플랫폼 설정

### Android

`android/app/build.gradle` (또는 `.kts`)에서 `minSdk`를 **29** 이상으로 설정하세요.

```groovy
android {
    defaultConfig {
        minSdk = 29
    }
}
```

삼성헬스 앱이 설치된 기기에서만 데이터 조회가 가능합니다.

### iOS

**Minimum deployment target: iOS 18.0**

1. `ios/Runner/Info.plist`에 사용 목적 문구를 추가합니다.

```xml
<key>NSHealthShareUsageDescription</key>
<string>심박수·걸음·수면·운동·체중 데이터를 읽어 혈당 변화와의 상관관계를 분석합니다.</string>
```

2. `ios/Runner/Runner.entitlements` (없으면 생성)에 HealthKit 권한을 추가합니다.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.healthkit</key>
    <true/>
</dict>
</plist>
```

3. Xcode → Target → Signing & Capabilities → **+** → **HealthKit** 추가 (또는 `project.pbxproj`에 `CODE_SIGN_ENTITLEMENTS` 설정).

---

## 기본 사용법

```dart
import 'package:flutter_health/flutter_health.dart';

final health = FlutterHealth();

// 가용성 확인
final available = await health.isAvailable();

// SDK 연결 (Android: HealthDataStore 초기화)
await health.connect();

// 권한 요청
await health.requestPermission();

// 10분 격자 버킷 지표 조회 (심박·걸음·거리·칼로리)
final now = DateTime.now();
final beats = await health.queryHeartRate(now.subtract(Duration(minutes: 15)), now);
for (final r in beats) {
  print(r.valueJson);  // HeartRateIntervalValue JSON
}
```

---

## API

| 메서드 | 설명 |
|---|---|
| `isAvailable()` | 삼성헬스 앱 설치 여부(Android) / HealthKit 가용성(iOS) 확인 |
| `connect()` | SDK 연결. Android는 HealthDataStore 초기화, iOS는 즉시 true |
| `disconnect()` | 연결 해제 |
| `isPermissionGranted()` | 권한 부여 여부 확인 |
| `requestPermission()` | 권한 요청 UI 표시 |
| `queryHeartRate(since, to)` | 심박수 — 벽시계 10분 격자 버킷(avg/min/max, bpm) 목록. 완료된(닫힌) 칸만 |
| `querySteps(since, to)` | 걸음 수 — 벽시계 10분 격자 버킷(count) 합 목록. 완료된 칸만 |
| `queryDistance(since, to)` | 이동 거리 — 벽시계 10분 격자 버킷(distance, m) 합 목록. 완료된 칸만 |
| `queryCalories(since, to)` | 소비 칼로리 — 벽시계 10분 격자 버킷(total/active, kcal) 합 목록. 완료된 칸만 |
| `queryStepsDaily(date)` | 당일 누적 걸음 수(count) 1건 — 자정~수집 시점 누적 |
| `queryEndedSleepSessions(since, to)` | 구간 내 종료된 수면 세션 목록 |
| `queryEndedExerciseSessions(since, to)` | 구간 내 종료된 운동 세션 목록 |
| `queryHourlySummary(hourStart, hourEnd)` | 1시간 집계 (HR·걸음·칼로리·거리) |
| `queryDailySummary(date)` | 1일 집계 (HR·걸음·칼로리·거리·수면·운동) |
| `queryWeights(since, to)` | 구간 내 모든 체중 측정 목록 최신순 (weight·BMI·체지방률) |

> 모든 list 반환 쿼리(`queryWeights`, `queryBloodGlucose`, `queryStepSegments` 등)는 **최신순(timestamp 내림차순)** 으로 정렬되어 반환됩니다.

---

## HealthRecord 구조

모든 쿼리 메서드는 `HealthRecord`를 반환합니다.

```dart
class HealthRecord {
  final String dataType;    // "heart_rate_interval" | "steps_interval" | "distance_interval" | "calories_interval" | "steps_daily" | "sleep" | "exercise" | "hourly_summary" | "daily_summary" | "weight" ...
  final int timestamp;      // UTC epoch ms (구간 시작)
  final int endTimestamp;   // UTC epoch ms (구간 종료)
  final String tzOffset;    // "+09:00" 형식
  final String source;      // "samsung_health" | "apple_health"
  final String valueJson;   // 타입별 JSON 문자열
  final int createdAt;      // 플러그인 생성 시각 (UTC epoch ms)
}
```

`valueJson`을 타입드 모델로 파싱하는 편의 getter도 제공합니다.

```dart
record.asHeartRateInterval // HeartRateIntervalValue?
record.asStepsInterval     // StepsIntervalValue?
record.asDistanceInterval  // DistanceIntervalValue?
record.asCaloriesInterval  // CaloriesIntervalValue?
record.asStepsDaily        // StepsDailyValue?
record.asSleep             // SleepValue?
record.asExercise       // ExerciseValue?
record.asHourlySummary  // HourlySummaryValue?
record.asDailySummary   // DailySummaryValue?
record.asWeight         // WeightValue?
```

---

## 10분 루프 구현 가이드 (호스트 앱)

플러그인은 스케줄링을 하지 않습니다. 호스트 앱에서 아래 패턴으로 구현하세요.
지표(심박·걸음·거리·칼로리)는 **벽시계 10분 격자 버킷**으로 들어오며, **완료된(닫힌) 칸만** 반환됩니다.
같은 칸을 다시 받아도 서버 UNIQUE(member, data_type, start_dttm) + on conflict 가 흡수하므로 안전합니다.

```dart
Timer? _loopTimer;

void startHealthLoop() {
  _collect();   // 즉시 1회 수집

  // 다음 10분 벽시계 경계까지 대기 후 periodic 시작
  final now = DateTime.now();
  final msInCycle = (now.minute % 10) * 60000 + now.second * 1000 + now.millisecond;
  final msToNext  = 10 * 60000 - msInCycle;

  _loopTimer = Timer(Duration(milliseconds: msToNext), () {
    _collect();
    _loopTimer = Timer.periodic(const Duration(minutes: 10), (_) => _collect());
  });
}

Future<void> _collect() async {
  final to   = DateTime.now();
  // 직전 닫힌 10분 칸을 확실히 포함하도록 약간 넓게(재수집은 서버가 dedup).
  final from = to.subtract(const Duration(minutes: 15));
  // 5개는 독립 쿼리라 동시에 던진다.
  final results = await Future.wait([
    health.queryHeartRate(from, to),
    health.querySteps(from, to),
    health.queryDistance(from, to),
    health.queryCalories(from, to),
    health.queryStepsDaily(to), // 당일 누적 걸음
  ]);
  final records = results.expand((r) => r).toList();
  // 서버 전송 또는 로컬 DB 저장
}
```

### 시간별·일별 요약 트리거 조건

```dart
// 매 사이클에서 호출
Future<void> _checkSummaries() async {
  final now = DateTime.now();

  // 시간별: 매 시간 5분 이후, 아직 저장되지 않은 경우
  if (now.minute >= 5) {
    final prevHourStart = DateTime(now.year, now.month, now.day, now.hour - 1);
    final prevHourEnd   = prevHourStart.add(const Duration(hours: 1));
    if (!await _hourlySummaryExists(prevHourStart)) {
      final r = await health.queryHourlySummary(prevHourStart, prevHourEnd);
      if (r != null) await _saveAndSync(r);
    }
  }

  // 일별: 새벽 4시 이후, 전날 요약이 없는 경우
  if (now.hour >= 4) {
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (!await _dailySummaryExists(yesterday)) {
      final r = await health.queryDailySummary(yesterday);
      if (r != null) await _saveAndSync(r);
    }
  }
}
```

### 수면·운동 세션 조회

```dart
// 매 사이클마다 최근 5분 범위로 조회
final sessions = await health.queryEndedSleepSessions(from, to);
```

---

## 중복 방지

플러그인은 중복 방지를 수행하지 않습니다. 호스트 앱 DB에 `(dataType, timestamp)` 복합 UNIQUE 인덱스로 구성하세요.

---

## 플랫폼별 특이사항

| 항목 | Android | iOS |
|---|---|---|
| source | `samsung_health` | `apple_health` |
| 백그라운드 정확한 5분 루프 | WorkManager로 구현 가능 | OS 재량 (`BGAppRefreshTask`) — 정확도 보장 불가 |
| 운동 종목 (`exerciseType`) | `PredefinedExerciseType` 이름 소문자화(예: `table_tennis`,`bench_press`), 비운동/UNDEFINED만 `other` | `HKWorkoutActivityType` case 이름 snake_case(예: `cycling`,`table_tennis`), 비운동/미상 `other` — 동의어 통합·표시명은 코드테이블 |
| 거리 | 모든 활동 포함 | 걷기·달리기만 (`distanceWalkingRunning`) |
| 체중 BMI / 체지방률 | BODY_COMPOSITION에 포함된 경우 동반 반환 | 항상 null (`.bodyMass`만 조회) |

---

## 라이선스

사내 전용. 외부 배포 금지.

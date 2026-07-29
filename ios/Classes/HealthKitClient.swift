import Foundation
import HealthKit
import os

/// Apple HealthKit 데이터 래퍼 (diaconn-aid-ios/HealthKitClient.swift 포팅 — diaconn 의존성 제거).
///
/// AppTime → Date() 직접 사용, AppLogger → os.Logger, HealthRecord → 로컬 struct
final class HealthKitClient: @unchecked Sendable {

    static func isAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// 이미 권한 흐름을 거쳤는지 확인한다 (부분 허용 포함).
    /// HealthKit은 READ 허용 여부를 앱에 직접 노출하지 않으므로,
    /// 권한 다이얼로그를 다시 띄울 필요가 없는 상태(.unnecessary)를 "granted"로 간주한다.
    func isPermissionGranted() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                continuation.resume(returning: status == .unnecessary)
            }
        }
    }

    /// 권한 UI를 표시한다. 사용자가 다이얼로그를 처리하면 true 반환.
    func requestPermission() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("requestPermission: health data unavailable")
            return false
        }
        let types = readTypes
        logger.info("requestPermission: requesting \(types.count) read types")
        try await store.requestAuthorization(toShare: [], read: types)
        logger.info("requestPermission: requestAuthorization completed")
        return true
    }

    /// since 를 격자 경계로 내려 완료된(닫힌, endDate<=to) 10분 버킷만 (start,end,stats) 로 반환. 진행 중 칸은 제외(부분 집계 방지).
    /// heart(avg/min/max)·steps·distance·calories 가 공유 — 호출처가 stats 에서 sum/avg 를 꺼낸다.
    private func queryGridBuckets(_ identifier: HKQuantityTypeIdentifier, options: HKStatisticsOptions, since: Date, to: Date) async -> [(start: Date, end: Date, stats: HKStatistics)] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let secs = Double(Self.bucketMinutes * 60)
        // since 를 10분 격자 경계로 내린 gridStart — 아래 collection 의 anchorDate 이자 predicate 시작점으로 함께 쓴다(버킷 전체 구간을 집계해 부분 집계 방지).
        let gridStart = Date(timeIntervalSince1970: floor(since.timeIntervalSince1970 / secs) * secs)
        guard gridStart < to else { return [] }
        // .strictStartDate 는 경계 가로지른 샘플을 누락 → 기본 overlap 으로 Apple 건강 UI 와 일치.
        let predicate = HKQuery.predicateForSamples(withStart: gridStart, end: to, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: qt,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: gridStart,
                intervalComponents: DateComponents(minute: Self.bucketMinutes)
            )
            query.initialResultsHandler = { _, collection, _ in
                var out: [(start: Date, end: Date, stats: HKStatistics)] = []
                collection?.enumerateStatistics(from: gridStart, to: to) { stats, _ in
                    guard stats.endDate <= to else { return } // 완료된 칸만
                    out.append((start: stats.startDate, end: stats.endDate, stats: stats))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// 심박수를 **벽시계 10분 격자 버킷**(예: 09:00~09:10)별 평균/최소/최대(bpm)로 반환.
    func queryHeartRate(since: Date, to: Date) async -> [HealthRecord] {
        let unit = HKUnit(from: "count/min")
        let buckets = await queryGridBuckets(.heartRate, options: [.discreteAverage, .discreteMin, .discreteMax], since: since, to: to)
        let tz = currentTzOffset()
        let createdAt = toMs(Date())
        return buckets.compactMap { b in
            func intOf(_ q: HKQuantity?) -> Int? {
                guard let d = q?.doubleValue(for: unit), d > 0 else { return nil }
                return Int(d)
            }
            guard let avg = intOf(b.stats.averageQuantity()) else { return nil } // 그 칸에 심박 샘플 없으면 스킵
            let value = HeartRateIntervalValue(avg: avg, min: intOf(b.stats.minimumQuantity()), max: intOf(b.stats.maximumQuantity()))
            return HealthRecord(dataType: Self.dataTypeHeartRateInterval, timestamp: toMs(b.start), endTimestamp: toMs(b.end), tzOffset: tz, source: Self.source, valueJson: encodeToJson(value), createdAt: createdAt)
        }
    }

    /// 걸음 수를 **벽시계 10분 격자 버킷**별 합(steps_interval)으로 반환. 양 플랫폼 공통.
    /// HKStatistics 가 iPhone·워치 여러 소스를 자동 중복 제거한다.
    /// 저장 방식 차이: 삼성은 걸음을 1분 정수로 나눠 둬 10분 칸 합이 건강앱 하루 총합과 딱 맞지만,
    /// 애플은 구간 덩어리라 칸 경계에서 쪼개져 생긴 소수점을 아래 Int 변환에서 버려 iOS 칸 합이 건강앱보다 몇 걸음 적을 수 있다(항상 같거나 적음, 격자 방식 정상 오차).
    func querySteps(since: Date, to: Date) async -> [HealthRecord] {
        let buckets = await queryGridBuckets(.stepCount, options: .cumulativeSum, since: since, to: to)
        let tz = currentTzOffset()
        let createdAt = toMs(Date())
        return buckets.compactMap { b in
            guard let c = b.stats.sumQuantity()?.doubleValue(for: .count()), c > 0 else { return nil }
            let value = StepsIntervalValue(count: Int(c))
            return HealthRecord(dataType: Self.dataTypeStepsInterval, timestamp: toMs(b.start), endTimestamp: toMs(b.end), tzOffset: tz, source: Self.source, valueJson: encodeToJson(value), createdAt: createdAt)
        }
    }

    /// 이동 거리를 **벽시계 10분 격자 버킷**별 합(distance_interval, m)으로 반환.
    func queryDistance(since: Date, to: Date) async -> [HealthRecord] {
        let buckets = await queryGridBuckets(.distanceWalkingRunning, options: .cumulativeSum, since: since, to: to)
        let tz = currentTzOffset()
        let createdAt = toMs(Date())
        return buckets.compactMap { b in
            guard let m = b.stats.sumQuantity()?.doubleValue(for: .meter()), m > 0 else { return nil }
            let value = DistanceIntervalValue(distance: m)
            return HealthRecord(dataType: Self.dataTypeDistanceInterval, timestamp: toMs(b.start), endTimestamp: toMs(b.end), tzOffset: tz, source: Self.source, valueJson: encodeToJson(value), createdAt: createdAt)
        }
    }

    /// 활동 소비 칼로리를 **벽시계 10분 격자 버킷**별 합(calories_interval, active=활동 소비, kcal)으로 반환.
    /// 기초대사 포함 총소비는 하루가 지나야 확정되므로 daily_summary 에만 둔다.
    func queryCalories(since: Date, to: Date) async -> [HealthRecord] {
        let activeB = await queryGridBuckets(.activeEnergyBurned, options: .cumulativeSum, since: since, to: to)
        let bucketMs = Int64(Self.bucketMinutes * 60_000)
        let tz = currentTzOffset()
        let createdAt = toMs(Date())
        return activeB.compactMap { b in
            guard let active = b.stats.sumQuantity()?.doubleValue(for: .kilocalorie()), active > 0 else { return nil }
            let value = CaloriesIntervalValue(active: active)
            return HealthRecord(dataType: Self.dataTypeCaloriesInterval, timestamp: toMs(b.start), endTimestamp: toMs(b.start) + bucketMs, tzOffset: tz, source: Self.source, valueJson: encodeToJson(value), createdAt: createdAt)
        }
    }

    /// 구간들을 합친 전체 길이. 겹친 부분은 한 번만 센다(폰·워치가 같은 시간을 각각 기록해도 두 배가 안 되게).
    /// 사이가 [bridgeGapMs] 보다 벌어지면 따로 센다. 단위는 넣은 값과 같다.
    private static func mergedSpanMs(_ intervals: [(start: Int64, end: Int64)], bridgeGapMs: Int64 = 0) -> Int64 {
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: Int64 = 0
        var curStart = sorted[0].start
        var curEnd = sorted[0].end
        for iv in sorted.dropFirst() {
            if iv.start - curEnd > bridgeGapMs {
                total += curEnd - curStart
                curStart = iv.start
                curEnd = iv.end
            } else {
                curEnd = max(curEnd, iv.end)
            }
        }
        return total + (curEnd - curStart)
    }

    private static let sleepStageInBed = 0 // 애플 단계 번호 — 0 in_bed / 1 asleep_unspecified / 2 awake / 3 asleep_core / 4 asleep_deep / 5 asleep_rem
    private static let sleepStageAwake = 2
    private static let sleepSessionGapMs: Int64 = 60 * 60_000 // 이만큼 벌어지면 다른 잠으로 본다. 서버도 같은 값이라 한쪽만 바꾸면 안 맞는다

    private struct SleepFragment { // 수면 기록 한 조각. 이 조각들을 모아 하나의 잠으로 묶는다
        let start: Int64
        let end: Int64
        let stage: Int
    }

    /// 수면 조각을 한 번의 잠끼리 묶는다(1시간 넘게 벌어지면 다른 잠).
    /// in_bed 도 같이 묶어서, 폰의 긴 in_bed 가 워치 단계 두 뭉치를 이어 주면 한 잠이 된다.
    private static func sleepSessions(_ fragments: [SleepFragment]) -> [[SleepFragment]] {
        let valid = fragments.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !valid.isEmpty else { return [] }
        var sessions: [[SleepFragment]] = []
        var cur: [SleepFragment] = []
        var curEnd = Int64.min
        for f in valid {
            if !cur.isEmpty, f.start - curEnd > sleepSessionGapMs {
                sessions.append(cur)
                cur = []
                curEnd = Int64.min
            }
            cur.append(f)
            curEnd = max(curEnd, f.end)
        }
        sessions.append(cur)
        return sessions
    }

    /// 하루의 수면시간·취침시간(분). 서버와 같은 방식이다. 기록을 한 번의 잠끼리 묶은 뒤:
    /// - 수면시간 = 잠의 처음~끝에서 awake 만 뺀 값. 중간에 기록이 빈 구간은 잤다고 본다(애플 건강 앱과 같음).
    /// - 처음~끝은 단계 기록으로만 정한다. in_bed 는 잠을 이어 주기만 하고 구간을 넓히지 않는다.
    ///   단계 기록이 없는 밤(폰만 쓴 경우)은 in_bed 가 곧 수면시간.
    /// - 취침시간 = in_bed 구간을 합친 값.
    /// 자정을 넘긴 밤은 자르지 않고 잠이 끝난 날에 전체를 넣는다. 겹친 구간은 한 번만 센다.
    /// 수면은 애플이 합계를 안 줘서 직접 계산한다. 요약 숫자 전용이고 원본 기록은 따로 보낸다.
    private func querySleepSummaryMinutes(since: Date, to: Date) async -> (asleep: Int?, inBed: Int?) {
        guard HKObjectType.categoryType(forIdentifier: .sleepAnalysis) != nil else { return (nil, nil) }
        let fetchSince = Calendar.current.date(byAdding: .day, value: -1, to: since) ?? since // 밤잠은 자정을 넘기니까 하루 앞부터 가져온다(잠이 잘리지 않게)
        let predicate = HKQuery.predicateForSamples(withStart: fetchSince, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return (nil, nil) }
        let sinceMs = toMs(since)
        let toMsBound = toMs(to)

        var asleepMin = 0
        var inBedMin = 0
        let fragments = samples.map { SleepFragment(start: toMs($0.startDate), end: toMs($0.endDate), stage: $0.value) }
        for session in Self.sleepSessions(fragments) {
            let stages = session.filter { $0.stage != Self.sleepStageInBed } // in_bed 를 뺀 나머지가 단계 기록(awake·모르는 값 포함)
            let inBedUnion = Self.mergedSpanMs(session.filter { $0.stage == Self.sleepStageInBed }.map { (start: $0.start, end: $0.end) })
            guard let spanStart = stages.map(\.start).min(), let spanEnd = stages.map(\.end).max() else {
                guard let end = session.map(\.end).max(), end >= sinceMs, end < toMsBound else { continue } // 단계 기록이 없고 in_bed 만 있는 밤 — 그 시간이 수면시간이자 취침시간
                asleepMin += Int(inBedUnion / 60_000)
                inBedMin += Int(inBedUnion / 60_000)
                continue
            }
            guard spanEnd >= sinceMs, spanEnd < toMsBound else { continue } // 잠이 끝난 시각이 오늘 안일 때만 오늘로 센다
            let awakeUnion = Self.mergedSpanMs(stages.filter { $0.stage == Self.sleepStageAwake }.map { (start: $0.start, end: $0.end) })
            asleepMin += Int(((spanEnd - spanStart) - awakeUnion) / 60_000) // 서버도 잠 하나씩 분으로 버린 뒤 더한다
            inBedMin += Int(inBedUnion / 60_000)
        }
        return (asleep: asleepMin > 0 ? asleepMin : nil, inBed: inBedMin > 0 ? inBedMin : nil)
    }

    /// iOS 수면(raw) — sleepAnalysis 샘플 1건 = 단계 조각 1행(각 uuid). 병합 없이 그대로 전달하고, 세션 합성·정규화는 서버가 한다.
    /// 단계값은 애플 원시 분류(HKCategoryValueSleepAnalysis) 그대로: in_bed/asleep_unspecified/awake/asleep_core/asleep_deep/asleep_rem.
    /// 조회 창 정책: 밤잠이 자정을 걸치므로 호출자는 수면을 36h 창으로 조회한다(종료시각 누락 방지). 다른 타입은 24h.
    private func buildSleepStageRecord(_ sample: HKSample, tz: String) -> HealthRecord? {
        guard let s = sample as? HKCategorySample,
              let stage = Self.sleepStageString(s.value) else { return nil }
        return HealthRecord(
            dataType: Self.dataTypeSleep,
            timestamp: toMs(s.startDate),
            endTimestamp: toMs(s.endDate),
            tzOffset: tz,
            source: Self.source,
            valueJson: encodeToJson(SleepStageValue(stage: stage, stageValue: s.value)),
            createdAt: toMs(Date()),
            uid: s.uuid.uuidString
        )
    }

    /// HKCategoryValueSleepAnalysis rawValue → 애플 원시 단계 문자열. iOS 16+ 심볼 참조를 피하려 rawValue 로 직접 매핑.
    private static func sleepStageString(_ raw: Int) -> String? {
        switch raw {
        case 0: return "in_bed"
        case 1: return "asleep_unspecified"
        case 2: return "awake"
        case 3: return "asleep_core"
        case 4: return "asleep_deep"
        case 5: return "asleep_rem"
        default: return nil
        }
    }

    func queryEndedExerciseSessions(since: Date, to: Date) async -> [HealthRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        var records: [HealthRecord] = []
        for workout in workouts {
            if let r = await buildExerciseRecord(workout, tz: tz) {
                records.append(r)
            }
        }
        return records
    }

    /// 하루 운동 요약(개수·시간·칼로리). 애플 건강 앱과 같은 방식으로 센다.
    /// - 개수와 칼로리는 기록 그대로 센다. 워치와 다른 앱이 같은 운동을 각각 기록하면 2개로 나온다.
    ///   애플 건강 앱도 겹친 운동을 각각 한 줄로 보여준다.
    /// - 시간만 겹친 부분을 한 번만 센다. 운동은 애플이 합계를 내주지 않아 겹친 기록이 전부 그대로 오는데,
    ///   그냥 더하면 실제 시계보다 시간이 늘어나기 때문이다.
    /// 서버로 보내는 원본 운동 기록은 건드리지 않고, 이 요약 숫자에만 적용한다. Android 도 같은 규칙이다.
    private func summarizeExercise(_ sessions: [HealthRecord]) -> (count: Int?, totalMin: Int?, totalCalories: Double?) {
        guard !sessions.isEmpty else { return (nil, nil, nil) }
        let minuteSlots = sessions.map { r -> (start: Int64, end: Int64) in // 각 운동을 "시작한 분부터 몇 분간"으로 바꿔 합치면 겹친 분은 한 번만 남는다
            let startMin = r.timestamp / 60_000
            return (start: startMin, end: startMin + (r.endTimestamp - r.timestamp) / 60_000)
        }
        let mins = Int(Self.mergedSpanMs(minuteSlots)) // 넣은 단위가 분이라 그대로 분이다
        let kcals = sessions.compactMap { (try? jsonDecoder.decode(ExerciseValue.self, from: Data($0.valueJson.utf8)))?.calories }
        return (sessions.count, mins > 0 ? mins : nil, kcals.isEmpty ? nil : kcals.reduce(0.0, +))
    }

    /// HKWorkout → 공통 필드(종목·시간·칼로리·심박·거리)만 추출.
    private func buildExerciseRecord(_ workout: HKWorkout, tz: String) async -> HealthRecord? {
        let startMs = toMs(workout.startDate)
        let endMs = toMs(workout.endDate)
        let durationMin = Int((endMs - startMs) / 60000)
        guard durationMin > 0 else { return nil }

        let bpm = HKUnit(from: "count/min")

        var v = ExerciseValue(exerciseType: mapWorkoutType(workout.workoutActivityType))
        v.duration = durationMin

        // 칼로리·HR·거리 (statistics)
        // 수동 입력 운동은 statistics(for:) 가 nil 이라 totalEnergyBurned 로 폴백. 워치 운동은 statistics 가 채워져 폴백을 안 타므로 두 값을 겹쳐 세지 않는다.
        v.calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            ?? workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        let hrStats = workout.statistics(for: HKQuantityType(.heartRate))
        v.heartRateAvg = (hrStats?.averageQuantity()?.doubleValue(for: bpm)).map(Int.init)
        v.heartRateMax = (hrStats?.maximumQuantity()?.doubleValue(for: bpm)).map(Int.init)
        v.heartRateMin = (hrStats?.minimumQuantity()?.doubleValue(for: bpm)).map(Int.init)
        // 거리 기반 운동(running·walking·cycling·swimming)만 채워지고, 비거리 운동은 nil.
        v.distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            ?? workout.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
            ?? workout.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity()?.doubleValue(for: .meter())

        return HealthRecord(
            dataType: Self.dataTypeExercise,
            timestamp: startMs,
            endTimestamp: endMs,
            tzOffset: tz,
            source: Self.source,
            valueJson: encodeToJson(v),
            createdAt: toMs(Date()),
            uid: workout.uuid.uuidString
        )
    }

    func queryHourlySummary(from hourStart: Date, to hourEnd: Date) async -> HealthRecord? {
        async let hrStats = queryHeartRateStats(from: hourStart, to: hourEnd)
        // 정시(HH:00) 경계로 시간별 합산 — 경계를 걸친 샘플은 HKStatisticsCollectionQuery 가 시간 비례로 쪼개고, 여러 소스 중복은 자동 제거한다.
        let hourInterval = DateComponents(hour: 1)
        async let stepsTotal = querySumBucketed(.stepCount, unit: .count(), bucketStart: hourStart, interval: hourInterval)
        async let activeKcalQ = querySumBucketed(.activeEnergyBurned, unit: .kilocalorie(), bucketStart: hourStart, interval: hourInterval)
        async let activeTimeMinQ = querySumBucketed(.appleExerciseTime, unit: .minute(), bucketStart: hourStart, interval: hourInterval)
        async let distanceTotal = querySumBucketed(.distanceWalkingRunning, unit: .meter(), bucketStart: hourStart, interval: hourInterval)

        let hr = await hrStats
        let st = await stepsTotal
        let activeKcal = await activeKcalQ
        let exTimeMin = await activeTimeMinQ
        let dist = await distanceTotal

        // 요약이 담는 지표가 전부 nil 이면(빈 봉투) 레코드 미생성 — hourly/daily·양 OS 동일 규칙
        if hr.avg == nil && st == nil && activeKcal == nil && exTimeMin == nil && dist == nil {
            return nil
        }

        let hourLabel = hourFormatter.string(from: hourStart)

        let value = HourlySummaryValue(
            hour: hourLabel,
            heartRateAvg: hr.avg,
            heartRateMin: hr.min,
            heartRateMax: hr.max,
            stepsTotal: st.map { Int($0) },
            caloriesActiveTotal: activeKcal,
            activeTimeTotal: exTimeMin.map { Int($0) },
            distanceTotal: dist
        )
        return HealthRecord(
            dataType: Self.dataTypeHourlySummary,
            timestamp: toMs(hourStart),
            endTimestamp: toMs(hourEnd) - 1,
            tzOffset: currentTzOffset(),
            source: Self.source,
            valueJson: encodeToJson(value),
            createdAt: toMs(Date())
        )
    }

    func queryDailySummary(date: Date) async -> HealthRecord? {
        let cal = Calendar.current
        guard let dayStart = cal.dateInterval(of: .day, for: date)?.start,
              let dayEnd = cal.dateInterval(of: .day, for: date)?.end else { return nil }

        async let hrStats = queryHeartRateStats(from: dayStart, to: dayEnd)
        // 자정 경계로 하루 합산 — 경계를 걸친 샘플은 시간 비례로 쪼개고 여러 소스 중복은 제거해 Apple 건강 UI 와 일치.
        let dayInterval = DateComponents(day: 1)
        async let stepsTotal = querySumBucketed(.stepCount, unit: .count(), bucketStart: dayStart, interval: dayInterval)
        async let caloriesActive = querySumBucketed(.activeEnergyBurned, unit: .kilocalorie(), bucketStart: dayStart, interval: dayInterval)
        async let caloriesBasal = querySumBucketed(.basalEnergyBurned, unit: .kilocalorie(), bucketStart: dayStart, interval: dayInterval)
        async let activeTimeMin = querySumBucketed(.appleExerciseTime, unit: .minute(), bucketStart: dayStart, interval: dayInterval)
        async let distanceTotal = querySumBucketed(.distanceWalkingRunning, unit: .meter(), bucketStart: dayStart, interval: dayInterval)
        // 수면시간·취침시간 — 애플 건강 앱의 "수면시간"·"취침 시간"과 같은 뜻이다.
        async let sleepSummary = querySleepSummaryMinutes(since: dayStart, to: dayEnd)
        async let exerciseQuery = queryEndedExerciseSessions(since: dayStart, to: dayEnd)

        let hr = await hrStats
        let st = await stepsTotal
        let activeKcal = await caloriesActive
        let basalKcal = await caloriesBasal
        let exTimeMin = await activeTimeMin
        let dist = await distanceTotal
        // total = active + basal (둘 중 하나만 있으면 그것만, 둘 다 nil 이면 nil)
        let totalKcal: Double? = (activeKcal == nil && basalKcal == nil) ? nil : (activeKcal ?? 0) + (basalKcal ?? 0)

        let sleep = await sleepSummary
        // 개수는 기록 그대로, 시간만 겹친 부분을 한 번만 센다(요약 숫자만. 원본 기록은 그대로 보낸다).
        let (exerciseCount, exerciseTotalMin, exerciseTotalCalories) = summarizeExercise(await exerciseQuery)

        // 요약이 담는 지표가 전부 nil 이면(빈 봉투) 레코드 미생성 — hourly/daily·양 OS 동일 규칙
        if hr.avg == nil && st == nil && totalKcal == nil && exTimeMin == nil && dist == nil
            && sleep.asleep == nil && sleep.inBed == nil && exerciseCount == nil {
            return nil
        }

        let dateString = dateFormatter.string(from: dayStart)

        let value = DailySummaryValue(
            date: dateString,
            heartRateAvg: hr.avg,
            heartRateMin: hr.min,
            heartRateMax: hr.max,
            stepsTotal: st.map { Int($0) },
            caloriesTotal: totalKcal,
            caloriesActiveTotal: activeKcal,
            activeTimeTotal: exTimeMin.map { Int($0) },
            distanceTotal: dist,
            sleepDuration: sleep.asleep,
            inBedDuration: sleep.inBed,
            exerciseCount: exerciseCount,
            exerciseTotalMin: exerciseTotalMin,
            exerciseTotalCalories: exerciseTotalCalories
        )
        return HealthRecord(
            dataType: Self.dataTypeDailySummary,
            timestamp: toMs(dayStart),
            endTimestamp: toMs(dayEnd) - 1,
            tzOffset: currentTzOffset(),
            source: Self.source,
            valueJson: encodeToJson(value),
            createdAt: toMs(Date())
        )
    }

    /// 체중, BMI, 체지방률을 각자 독립 타입으로 per-sample 조회(HealthKit 원천 1:1) — 3종 동시(직렬 대기 방지).
    func queryWeights(since: Date, to: Date) async -> [HealthRecord] {
        async let weight         = queryWeight(since: since, to: to)
        async let bmi            = queryBmi(since: since, to: to)
        async let bodyFatPercent = queryBodyFatPercent(since: since, to: to)
        var out = await weight
        out += await bmi
        out += await bodyFatPercent
        return out
    }

    /// 체중(bodyMass, kg) 단일 조회 — iOS 성분별 체성분 피드(queryChanges 2-a)용.
    func queryWeight(since: Date, to: Date) async -> [HealthRecord] {
        return await queryQuantitySamples(.bodyMass, unit: weightUnit, dataType: Self.dataTypeWeight, since: since, to: to) { kg, _ in kg > 0 ? WeightValue(weight: kg) : nil }
    }

    /// BMI(bodyMassIndex) 단일 조회 — iOS 성분별 체성분 피드(queryChanges 2-a)용.
    func queryBmi(since: Date, to: Date) async -> [HealthRecord] {
        return await queryQuantitySamples(.bodyMassIndex, unit: .count(), dataType: Self.dataTypeBmi, since: since, to: to) { v, _ in v > 0 ? QuantitySampleValue(value: v, unit: "kg/m²") : nil }
    }

    /// 체지방률(bodyFatPercentage) 단일 조회 — .percent()=분수(0~1)라 100배해 %. iOS 성분별 체성분 피드용.
    func queryBodyFatPercent(since: Date, to: Date) async -> [HealthRecord] {
        return await queryQuantitySamples(.bodyFatPercentage, unit: .percent(), dataType: Self.dataTypeBodyFatPercentage, since: since, to: to) { v, _ in v > 0 ? QuantitySampleValue(value: v * 100, unit: "%") : nil }
    }

    func queryBloodGlucose(since: Date, to: Date) async -> [HealthRecord] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else { return [] }
        let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci)) // mg/dL
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: qt, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        let now = toMs(Date())
        return samples.compactMap { sample in
            let glucose = sample.quantity.doubleValue(for: unit)
            guard glucose > 0 else { return nil }
            var mealStatus: String? = nil
            if let mealTime = sample.metadata?[HKMetadataKeyBloodGlucoseMealTime] as? Int {
                switch mealTime {
                case 1: mealStatus = "before_meal"  // preprandial
                case 2: mealStatus = "after_meal"   // postprandial
                default: break
                }
            }
            let value = BloodGlucoseValue(
                glucose: glucose,
                mealStatus: mealStatus,
                insulinInjected: nil,
                medicationTaken: nil
            )
            return HealthRecord(
                dataType: Self.dataTypeBloodGlucose,
                timestamp: toMs(sample.startDate),
                endTimestamp: toMs(sample.endDate),
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: now,
                uid: sample.uuid.uuidString
            )
        }
    }

    /// iOS 전용. 인슐린 투여(`HKQuantityTypeIdentifierInsulinDelivery`, IU) 샘플 + 메타키
    /// `HKMetadataKeyInsulinDeliveryReason` (1=Basal, 2=Bolus) 를 함께 평탄화해 반환.
    /// 메타 누락 시 reason=nil. iOS 11+ 가용 식별자.
    func queryInsulinDelivery(since: Date, to: Date) async -> [HealthRecord] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else { return [] }
        let unit = HKUnit.internationalUnit()
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: qt, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        let now = toMs(Date())
        return samples.compactMap { sample -> HealthRecord? in
            let dose = sample.quantity.doubleValue(for: unit)
            guard dose > 0 else { return nil }
            var reason: String? = nil
            if let r = sample.metadata?[HKMetadataKeyInsulinDeliveryReason] as? Int {
                switch r {
                case 1: reason = "basal"
                case 2: reason = "bolus"
                default: break
                }
            }
            let value = InsulinDeliveryValue(dose: dose, reason: reason)
            return HealthRecord(
                dataType: Self.dataTypeInsulinDelivery,
                timestamp: toMs(sample.startDate),
                endTimestamp: toMs(sample.endDate),
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: now,
                uid: sample.uuid.uuidString
            )
        }
    }

    func queryBloodPressure(since: Date, to: Date) async -> [HealthRecord] {
        guard let correlationType = HKCorrelationType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let mmHg = HKUnit.millimeterOfMercury()
        return await withCheckedContinuation { continuation in
            let query = HKCorrelationQuery(type: correlationType, predicate: predicate, samplePredicates: nil) { [weak self] _, correlations, _ in
                guard let self = self else { continuation.resume(returning: []); return }
                let tz = self.currentTzOffset()
                let now = self.toMs(Date())
                let records: [HealthRecord] = (correlations ?? []).compactMap { correlation in
                    guard let sys = correlation.objects(for: systolicType).first as? HKQuantitySample,
                          let dia = correlation.objects(for: diastolicType).first as? HKQuantitySample else { return nil }
                    let value = BloodPressureValue(
                        systolic: sys.quantity.doubleValue(for: mmHg),
                        diastolic: dia.quantity.doubleValue(for: mmHg),
                        mean: nil,
                        pulseRate: nil,
                        medicationTaken: nil
                    )
                    return HealthRecord(
                        dataType: Self.dataTypeBloodPressure,
                        timestamp: self.toMs(correlation.startDate),
                        endTimestamp: self.toMs(correlation.endDate),
                        tzOffset: tz,
                        source: Self.source,
                        valueJson: self.encodeToJson(value),
                        createdAt: now,
                        // 변경 피드가 systolic 컴포넌트를 앵커로 삭제 감지 → deletedObjects=systolic uuid. 저장 uid도 systolic 컴포넌트로 맞춰 삭제 매칭.
                        uid: sys.uuid.uuidString
                    )
                }
                continuation.resume(returning: records)
            }
            self.store.execute(query)
        }
    }

    /// 영양 성분 스펙(19종) — queryNutrition·queryNutrient·sampleType 공유. dataType 은 앱 HealthRecord.nutritionTypesIos 와 1:1.
    static let nutritionSpecs: [(id: HKQuantityTypeIdentifier, dataType: String, unit: HKUnit, unitLabel: String)] = {
        let kcal = HKUnit.kilocalorie()
        let g = HKUnit.gram()
        let mg = HKUnit.gramUnit(with: .milli)
        let mcg = HKUnit.gramUnit(with: .micro)
        return [
            (.dietaryEnergyConsumed,      "nutrition_energy",        kcal, "kcal"), // 섭취 에너지(Apple "Dietary Energy"). 소모(CALORIES_INTERVAL)와 구분
            (.dietaryCarbohydrates,       "nutrition_carbohydrate",  g,    "g"),
            (.dietaryProtein,             "nutrition_protein",       g,    "g"),
            (.dietaryFatTotal,            "nutrition_fat",           g,    "g"),
            (.dietaryFatSaturated,        "nutrition_fat_saturated", g,    "g"),
            (.dietaryFatPolyunsaturated,  "nutrition_fat_poly",      g,    "g"),
            (.dietaryFatMonounsaturated,  "nutrition_fat_mono",      g,    "g"),
            (.dietarySugar,               "nutrition_sugar",         g,    "g"),
            (.dietaryFiber,               "nutrition_fiber",         g,    "g"),
            (.dietaryCholesterol,         "nutrition_cholesterol",   mg,   "mg"),
            (.dietarySodium,              "nutrition_sodium",        mg,   "mg"),
            (.dietaryPotassium,           "nutrition_potassium",     mg,   "mg"),
            (.dietaryCalcium,             "nutrition_calcium",       mg,   "mg"),
            (.dietaryIron,                "nutrition_iron",          mg,   "mg"),
            (.dietaryMagnesium,           "nutrition_magnesium",     mg,   "mg"),
            (.dietaryCaffeine,            "nutrition_caffeine",      mg,   "mg"),
            (.dietaryVitaminA,            "nutrition_vitamin_a",     mcg,  "mcg"),
            (.dietaryVitaminC,            "nutrition_vitamin_c",     mg,   "mg"),
            (.dietaryVitaminD,            "nutrition_vitamin_d",     mcg,  "mcg"),
        ]
    }()

    /// 전 성분(nutrition_* 19종)을 성분별로 조회 — 동시 실행(직렬 대기 방지, @unchecked Sendable 라 task group 안전).
    func queryNutrition(since: Date, to: Date) async -> [HealthRecord] {
        return await withTaskGroup(of: [HealthRecord].self) { group in
            for spec in Self.nutritionSpecs {
                group.addTask { await self.queryNutrient(spec.dataType, since: since, to: to) }
            }
            var out: [HealthRecord] = []
            for await chunk in group { out += chunk }
            return out
        }
    }

    /// 단일 성분 조회 — 성분별 변경 피드(queryChanges 2-a)가 added 구간을 완전 레코드로 대체할 때 사용.
    func queryNutrient(_ dataType: String, since: Date, to: Date) async -> [HealthRecord] {
        guard let spec = Self.nutritionSpecs.first(where: { $0.dataType == dataType }) else { return [] }
        return await queryQuantitySamples(spec.id, unit: spec.unit, dataType: spec.dataType, since: since, to: to) { v, _ in
            v > 0 ? QuantitySampleValue(value: v, unit: spec.unitLabel) : nil
        }
    }

    /// 각 수분 샘플을 그 음용의 원본 양(amount)만 담아 반환한다
    /// 반환은 표시 일관성 위해 최신순(내림차순).
    func queryWaterIntake(since: Date, to: Date) async -> [HealthRecord] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else { return [] }
        let unit = HKUnit.literUnit(with: .milli)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: qt, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        let now = toMs(Date())
        var records: [HealthRecord] = []
        for sample in samples {
            let v = sample.quantity.doubleValue(for: unit)
            guard v > 0 else { continue }
            records.append(HealthRecord(
                dataType: Self.dataTypeWaterIntake,
                timestamp: toMs(sample.startDate),
                endTimestamp: toMs(sample.endDate),
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(WaterIntakeValue(amount: v)),
                createdAt: now,
                uid: sample.uuid.uuidString
            ))
        }
        return records
    }

    /// 키(신장) — HealthKit `height` 샘플을 **cm** 로 반환 (dataType="height"). Android(UserProfile)와 단위 통일.
    func queryHeight(since: Date, to: Date) async -> [HealthRecord] {
        await queryQuantitySamples(.height, unit: HKUnit.meterUnit(with: .centi), dataType: Self.dataTypeHeight, since: since, to: to) { v, _ in
            v > 0 ? HeightValue(height: v) : nil
        }
    }

    // MARK: - 변경 피드 (수정/삭제)

    /// HKAnchoredObjectQuery 로 변경 피드(추가 샘플 + 삭제 객체 UUID + 다음 anchor)를 받는다.
    ///
    /// - anchorToken(base64) 이 있으면 그 시점 이후 **델타만**(추가/삭제), 없으면 since~to 범위 전량이 기준선.
    /// - HealthKit 의 "수정"은 구 uuid 삭제 + 신 uuid 추가로 오므로, 수정 시 신규는 upserted, 구본은 deletedUids 에 나온다.
    /// - deletedObjects 는 anchor 확립 이후 삭제분만 잡히므로 반드시 (기준선 호출 → 편집/삭제 → 재호출) 순서로 검증.
    /// - anchored 델타는 raw/부분 샘플로만 와서 저장 스키마가 불완전하다 → uid 타입은 추가분 구간을 정식 조회로 재조회해 완전 레코드로 대체한다(수면=병합 세션 / 영양=성분별 피드·해당 성분만 재조회 / 체중=weight+bmi+체지방률 / 혈당·혈압·수분=측정 전체). 운동(HKWorkout)만 그 자체로 완전해 재조회 없이 변환.
    func queryChanges(dataType: String, since: Date, to: Date, anchorToken: String?) async -> (upserted: [HealthRecord], deletedUids: [String], token: String?) {
        guard let sampleType = Self.sampleType(forDataType: dataType) else { return ([], [], nil) }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: [])
        let anchor = anchorToken.flatMap { Self.decodeAnchor($0) }
        // 1) 앵커드 쿼리로 raw 결과만 수집: 추가 샘플·삭제 uuid·다음 anchor.
        //    쿼리 콜백 안에서는 await 를 못 써서(완전 레코드 재조회는 2)에서), continuation 으로 raw 만 넘긴다.
        let (added, deletedUids, token): ([HKSample], [String], String?) = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: sampleType, predicate: predicate, anchor: anchor, limit: HKObjectQueryNoLimit) { _, addedSamples, deletedObjects, newAnchor, _ in
                let uids = (deletedObjects ?? []).map { $0.uuid.uuidString }
                let tk = newAnchor.flatMap { Self.encodeAnchor($0) }
                continuation.resume(returning: (addedSamples ?? [], uids, tk))
            }
            self.store.execute(query)
        }
        // 2-a) uid 타입 재조회 — anchored 로 감지한 added 구간을 정식 조회로 다시 읽어 완전 레코드로 대체.
        switch dataType {
        case "nutrition",
             Self.dataTypeWeight, Self.dataTypeBmi, Self.dataTypeBodyFatPercentage,
             Self.dataTypeBloodGlucose, Self.dataTypeBloodPressure, Self.dataTypeWaterIntake,
             Self.dataTypeInsulinDelivery, Self.dataTypeHeight:
            // added 비면 삭제뿐 → deletedUids·token 만 반환.
            guard let spanStart = added.map({ $0.startDate }).min() else { return ([], deletedUids, token) }
            let full: [HealthRecord]
            switch dataType {
            case Self.dataTypeWeight:            full = await queryWeight(since: spanStart, to: Date())
            case Self.dataTypeBmi:               full = await queryBmi(since: spanStart, to: Date())
            case Self.dataTypeBodyFatPercentage: full = await queryBodyFatPercent(since: spanStart, to: Date())
            case Self.dataTypeBloodGlucose:      full = await queryBloodGlucose(since: spanStart, to: Date())
            case Self.dataTypeBloodPressure:     full = await queryBloodPressure(since: spanStart, to: Date())
            case Self.dataTypeWaterIntake:       full = await queryWaterIntake(since: spanStart, to: Date())
            case Self.dataTypeInsulinDelivery:   full = await queryInsulinDelivery(since: spanStart, to: Date())
            case Self.dataTypeHeight:            full = await queryHeight(since: spanStart, to: Date())
            default:                             full = await queryNutrition(since: spanStart, to: Date()) // "nutrition" 단일 피드 구 호환(전 성분 재조회)
            }
            return (full, deletedUids, token)
        case let t where t.hasPrefix("nutrition_"):
            // 성분별 피드 — added 구간을 해당 성분만 재조회해 완전 레코드로 대체(deleted 는 그 성분 샘플 uid 그대로).
            guard let spanStart = added.map({ $0.startDate }).min() else { return ([], deletedUids, token) }
            return (await queryNutrient(t, since: spanStart, to: Date()), deletedUids, token)
        default:
            break
        }
        // 2-b) 자체 완전 레코드 타입 — 재조회 없이 raw 샘플을 그대로 변환.
        //   · 수면(sleep): iOS 는 sleepAnalysis 샘플 하나가 곧 단계 조각(각 uuid) → 병합 없이 raw 그대로(세션 합성·정규화는 서버).
        //   · 운동(exercise): HKWorkout 그 자체로 완전.
        let tz = currentTzOffset()
        var records: [HealthRecord] = []
        for sample in added {
            if dataType == Self.dataTypeSleep {
                if let r = buildSleepStageRecord(sample, tz: tz) { records.append(r) }
            } else if let workout = sample as? HKWorkout, let r = await buildExerciseRecord(workout, tz: tz) {
                records.append(r)
            }
        }
        return (records.sorted { $0.timestamp > $1.timestamp }, deletedUids, token)
    }

    /// 변경 피드 dataType → 앵커드 쿼리용 HKSampleType 매핑(지원 대상 타입만).
    private static func sampleType(forDataType dataType: String) -> HKSampleType? {
        switch dataType {
        case dataTypeSleep:         return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case dataTypeExercise:      return HKObjectType.workoutType()
        case dataTypeWeight:        return HKObjectType.quantityType(forIdentifier: .bodyMass)
        // 체성분 비대칭: Android=BODY_COMPOSITION 번들 / iOS=성분별 독립 타입(weight, bmi, body_fat_percentage 각자 피드·anchor).
        case dataTypeBmi:                return HKObjectType.quantityType(forIdentifier: .bodyMassIndex)
        case dataTypeBodyFatPercentage:  return HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        case dataTypeBloodGlucose:  return HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        case dataTypeWaterIntake:   return HKObjectType.quantityType(forIdentifier: .dietaryWater)
        // correlation 은 read set/조회에서 크래시 이슈 → systolic 컴포넌트로 변경 감지(완전값은 재조회 queryBloodPressure 가 생성).
        case dataTypeBloodPressure: return HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)
        // 인슐린 비대칭: Android=혈당 레코드 필드(insulin_injected) 동봉 / iOS=독립 타입 insulin_delivery 변경 피드(삭제 델타 확보).
        case dataTypeInsulinDelivery: return HKObjectType.quantityType(forIdentifier: .insulinDelivery)
        // 키 비대칭: Android=삼성 프로필 설정값(range 조회, 삭제 대상 아님) / iOS=독립 HealthKit 샘플 변경 피드.
        case dataTypeHeight:          return HKObjectType.quantityType(forIdentifier: .height)
        // 영양 비대칭: Android=끼니 번들(단일 "nutrition" 피드) / iOS=성분 단위 per-sample(nutrition_* 성분별 피드·anchor).
        case "nutrition": return HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        case let t where t.hasPrefix("nutrition_"):
            return nutritionSpecs.first(where: { $0.dataType == t }).flatMap { HKObjectType.quantityType(forIdentifier: $0.id) }
        default: return nil
        }
    }


    /// HKQueryAnchor ↔ base64 문자열(Dart 왕복용). NSSecureCoding 아카이빙.
    private static func encodeAnchor(_ anchor: HKQueryAnchor) -> String? {
        (try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true))?.base64EncodedString()
    }
    private static func decodeAnchor(_ token: String) -> HKQueryAnchor? {
        guard let data = Data(base64Encoded: token) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    // MARK: - Private

    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.diaconn.flutter_health", category: "HealthKitClient")
    // valueJson 키를 snake_case 로 통일(서버 t_health_log json_data 스키마 일관). 인코드/디코드 양방향 동일 전략 → round-trip 안전.
    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH"
        f.timeZone = TimeZone.current
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private func toMs(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private var readTypes: Set<HKObjectType> {
        let types: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,   // metric/daily 의 caloriesBasal
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,   // daily/hourly 의 activeTime
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
        HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.workoutType(),
        // 혈당/혈압/수분
        HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
        // ⚠️ 혈압 correlation 타입(.bloodPressure)은 requestAuthorization read set 에 넣으면 런타임 크래시한다 —
        //    권한 요청은 위 컴포넌트(systolic/diastolic)로만, correlation 은 조회(HKCorrelationQuery)용.
        HKObjectType.quantityType(forIdentifier: .insulinDelivery)!,   // 인슐린 투여(iOS) — read set 누락으로 미수집되던 것 추가
        HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
        // 영양(nutrition) 세부 영양소
        HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFatSaturated)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFatPolyunsaturated)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFatMonounsaturated)!,
        HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
        HKObjectType.quantityType(forIdentifier: .dietarySugar)!,
        HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
        HKObjectType.quantityType(forIdentifier: .dietaryCholesterol)!,
        HKObjectType.quantityType(forIdentifier: .dietarySodium)!,
        HKObjectType.quantityType(forIdentifier: .dietaryPotassium)!,
        HKObjectType.quantityType(forIdentifier: .dietaryVitaminA)!,
        HKObjectType.quantityType(forIdentifier: .dietaryVitaminC)!,
        HKObjectType.quantityType(forIdentifier: .dietaryCalcium)!,
        HKObjectType.quantityType(forIdentifier: .dietaryIron)!,
        HKObjectType.quantityType(forIdentifier: .dietaryMagnesium)!,
        HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!,
        HKObjectType.quantityType(forIdentifier: .dietaryVitaminD)!
        ]
        return types
    }

    private let weightUnit = HKUnit.gramUnit(with: .kilo)

    private func currentTzOffset() -> String {
        let seconds = TimeZone.current.secondsFromGMT()
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        let sign = seconds >= 0 ? "+" : "-"
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }

    /// 일/시 집계 전용 버킷 합산. 단순 overlap-sum 은 경계(자정/정시)를 가로지른 누적 샘플을 전량 더해 over-count 된다.
    /// HKStatisticsCollectionQuery 가 경계 샘플을 시간비례로 나누고 multi-source 를 자동 중복 제거 → Apple 건강 UI 와 일치.
    /// bucketStart 에 맞춘 단일 버킷의 합만 반환(hourly/daily summary 의 일/시 누적용).
    private func querySumBucketed(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        bucketStart: Date,
        interval: DateComponents
    ) async -> Double? {
        guard let qt = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let cal = Calendar.current
        guard let bucketEnd = cal.date(byAdding: interval, to: bucketStart) else { return nil }
        // 버킷 시작 직전에 시작해 버킷으로 이어지는 샘플까지 predicate 에 포함되도록 조회를 하루 앞에서 시작. collection 은 bucketStart 버킷만 읽으므로 안전.
        let predStart = cal.date(byAdding: .day, value: -1, to: bucketStart) ?? bucketStart
        let predicate = HKQuery.predicateForSamples(withStart: predStart, end: bucketEnd, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: qt,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: bucketStart,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, _ in
                var value: Double? = nil
                collection?.enumerateStatistics(from: bucketStart, to: bucketEnd) { stats, stop in
                    if stats.startDate == bucketStart {
                        value = stats.sumQuantity()?.doubleValue(for: unit)
                        stop.pointee = true
                    }
                }
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func queryHeartRateStats(from: Date, to: Date) async -> (avg: Int?, min: Int?, max: Int?) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil, nil)
        }
        let unit = HKUnit(from: "count/min")
        // .strictStartDate 는 자정 가로지른 샘플(수면 중 묶음)을 누락 → 기본 overlap 으로 Apple 건강 UI 와 일치.
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let options: HKStatisticsOptions = [.discreteAverage, .discreteMin, .discreteMax]
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                let avg = stats?.averageQuantity().flatMap { v -> Int? in let d = v.doubleValue(for: unit); return d > 0 ? Int(d) : nil }
                let min = stats?.minimumQuantity().flatMap { v -> Int? in let d = v.doubleValue(for: unit); return d > 0 ? Int(d) : nil }
                let max = stats?.maximumQuantity().flatMap { v -> Int? in let d = v.doubleValue(for: unit); return d > 0 ? Int(d) : nil }
                continuation.resume(returning: (avg, min, max))
            }
            store.execute(query)
        }
    }

    /// 단순 quantity 샘플들을 개별 HealthRecord 로 수집하는 범용 헬퍼.
    /// `valueBuilder` 가 nil 을 반환하면 해당 샘플은 스킵한다.
    private func queryQuantitySamples<T: Encodable>(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        dataType: String,
        since: Date,
        to: Date,
        valueBuilder: (Double, HKQuantitySample) -> T?
    ) async -> [HealthRecord] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: qt, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        let now = toMs(Date())
        return samples.compactMap { sample in
            let v = sample.quantity.doubleValue(for: unit)
            guard let value = valueBuilder(v, sample) else { return nil }
            return HealthRecord(
                dataType: dataType,
                timestamp: toMs(sample.startDate),
                endTimestamp: toMs(sample.endDate),
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: now,
                uid: sample.uuid.uuidString
            )
        }
    }

    // deprecated·.other·미래 case만 default → "other".
    private func mapWorkoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .americanFootball: return "american_football"
        case .archery: return "archery"
        case .australianFootball: return "australian_football"
        case .badminton: return "badminton"
        case .baseball: return "baseball"
        case .basketball: return "basketball"
        case .bowling: return "bowling"
        case .boxing: return "boxing"
        case .climbing: return "climbing"
        case .cricket: return "cricket"
        case .crossTraining: return "cross_training"
        case .curling: return "curling"
        case .cycling: return "cycling"
        case .dance: return "dance"
        case .elliptical: return "elliptical"
        case .equestrianSports: return "equestrian_sports"
        case .fencing: return "fencing"
        case .fishing: return "fishing"
        case .functionalStrengthTraining: return "functional_strength_training"
        case .golf: return "golf"
        case .gymnastics: return "gymnastics"
        case .handball: return "handball"
        case .hiking: return "hiking"
        case .hockey: return "hockey"
        case .hunting: return "hunting"
        case .lacrosse: return "lacrosse"
        case .martialArts: return "martial_arts"
        case .mindAndBody: return "mind_and_body"
        case .paddleSports: return "paddle_sports"
        case .racquetball: return "racquetball"
        case .rowing: return "rowing"
        case .rugby: return "rugby"
        case .running: return "running"
        case .sailing: return "sailing"
        case .skatingSports: return "skating_sports"
        case .snowSports: return "snow_sports"
        case .soccer: return "soccer"
        case .softball: return "softball"
        case .squash: return "squash"
        case .stairClimbing: return "stair_climbing"
        case .stairs: return "stairs"
        case .surfingSports: return "surfing_sports"
        case .swimming: return "swimming"
        case .tableTennis: return "table_tennis"
        case .tennis: return "tennis"
        case .trackAndField: return "track_and_field"
        case .traditionalStrengthTraining: return "traditional_strength_training"
        case .volleyball: return "volleyball"
        case .walking: return "walking"
        case .waterFitness: return "water_fitness"
        case .waterPolo: return "water_polo"
        case .waterSports: return "water_sports"
        case .wrestling: return "wrestling"
        case .yoga: return "yoga"
        case .barre: return "barre"
        case .coreTraining: return "core_training"
        case .crossCountrySkiing: return "cross_country_skiing"
        case .downhillSkiing: return "downhill_skiing"
        case .flexibility: return "flexibility"
        case .highIntensityIntervalTraining: return "high_intensity_interval_training"
        case .jumpRope: return "jump_rope"
        case .kickboxing: return "kickboxing"
        case .pilates: return "pilates"
        case .snowboarding: return "snowboarding"
        case .stepTraining: return "step_training"
        case .wheelchairWalkPace: return "wheelchair_walk_pace"
        case .wheelchairRunPace: return "wheelchair_run_pace"
        case .taiChi: return "tai_chi"
        case .mixedCardio: return "mixed_cardio"
        case .handCycling: return "hand_cycling"
        case .discSports: return "disc_sports"
        case .fitnessGaming: return "fitness_gaming"
        case .cardioDance: return "cardio_dance"
        case .socialDance: return "social_dance"
        case .pickleball: return "pickleball"
        case .swimBikeRun: return "swim_bike_run"
        case .underwaterDiving: return "underwater_diving"
        case .preparationAndRecovery: return "preparation_and_recovery"
        case .cooldown: return "cooldown"
        case .play: return "play"
        case .transition: return "transition"
        default: return "other"
        }
    }

    private func encodeToJson<T: Encodable>(_ value: T) -> String {
        guard let data = try? jsonEncoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    // MARK: - valueJson 직렬화용 Codable 구조체

    /// 심박수 10분 격자 버킷 값(bpm).
    private struct HeartRateIntervalValue: Codable {
        let avg: Int?
        let min: Int?
        let max: Int?
    }

    /// 걸음 10분 격자 버킷 값(count).
    private struct StepsIntervalValue: Codable {
        let count: Int
    }

    /// 이동 거리 10분 격자 버킷 값(m).
    private struct DistanceIntervalValue: Codable {
        let distance: Double
    }

    /// 소비 칼로리 10분 격자 버킷 값(kcal). active=활동 소비(기초대사 제외).
    private struct CaloriesIntervalValue: Codable {
        let active: Double
    }

    /// iOS 수면 단계 조각 값 — 애플 원시 분류 그대로(정규화는 서버). stage 는 문자열, stageValue 는 HKCategoryValueSleepAnalysis rawValue(0~5).
    fileprivate struct SleepStageValue: Codable {
        let stage: String
        let stageValue: Int
    }

    /// iOS·Android 공통 필드만 유지. 시작~종료 시각은 HealthRecord.timestamp/endTimestamp(envelope).
    fileprivate struct ExerciseValue: Codable {
        var exerciseType: String
        var duration: Int? = nil
        var calories: Double? = nil
        var distance: Double? = nil
        var heartRateAvg: Int? = nil
        var heartRateMax: Int? = nil
        var heartRateMin: Int? = nil
    }

    private struct HourlySummaryValue: Codable {
        let hour: String
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsTotal: Int?
        let caloriesActiveTotal: Double?    // active 만
        // 애플 "운동 시간"(appleExerciseTime) — 빠르게 걷기 이상 강도로 움직인 1분마다 적립되는 값.
        // 운동으로 기록한 시간과는 다른 값이다.
        let activeTimeTotal: Int?
        let distanceTotal: Double?
    }

    fileprivate struct WeightValue: Codable {
        let weight: Double
    }

    /// 체성분(bmi·체지방률)·영양소(nutrition_*) per-sample 공통 값 — 측정값 + 단위.
    fileprivate struct QuantitySampleValue: Codable {
        let value: Double
        let unit: String
    }

    fileprivate struct BloodGlucoseValue: Codable {
        let glucose: Double
        let mealStatus: String?
        let insulinInjected: Double?
        let medicationTaken: Bool?
    }

    fileprivate struct BloodPressureValue: Codable {
        let systolic: Double
        let diastolic: Double
        let mean: Double?
        let pulseRate: Int?
        let medicationTaken: Bool?
    }

    fileprivate struct InsulinDeliveryValue: Codable {
        let dose: Double           // IU
        let reason: String?        // "basal" | "bolus" | nil
    }

    fileprivate struct WaterIntakeValue: Codable {
        let amount: Double   // 각 음용의 원본 양(mL).
    }

    fileprivate struct HeightValue: Codable {
        let height: Double           // cm
    }

    private struct DailySummaryValue: Codable {
        let date: String
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsTotal: Int?
        let caloriesTotal: Double?         // total = basal + active
        let caloriesActiveTotal: Double?   // active 만
        // 애플 "운동 시간"(appleExerciseTime) — 빠르게 걷기 이상 강도로 움직인 1분마다 적립되는 값.
        // 운동으로 기록한 시간(exerciseTotalMin)과는 다른 값이다.
        let activeTimeTotal: Int?
        let distanceTotal: Double?
        let sleepDuration: Int?
        let inBedDuration: Int?
        let exerciseCount: Int?
        let exerciseTotalMin: Int?
        let exerciseTotalCalories: Double?
    }

    // MARK: - 상수

    static let bucketMinutes = 10
    static let dataTypeHeartRateInterval = "heart_rate_interval"
    static let dataTypeStepsInterval = "steps_interval"
    static let dataTypeDistanceInterval = "distance_interval"
    static let dataTypeCaloriesInterval = "calories_interval"
    static let dataTypeSleep = "sleep"
    static let dataTypeExercise = "exercise"
    static let dataTypeHourlySummary = "hourly_summary"
    static let dataTypeDailySummary = "daily_summary"
    static let dataTypeWeight = "weight"
    static let dataTypeBmi = "bmi"
    static let dataTypeBodyFatPercentage = "body_fat_percentage"
    static let dataTypeBloodGlucose = "blood_glucose"
    static let dataTypeBloodPressure = "blood_pressure"
    static let dataTypeInsulinDelivery = "insulin_delivery"
    static let dataTypeWaterIntake = "water_intake"
    static let dataTypeHeight = "height"
    static let source = "apple_health"
}

// MARK: - 플러그인 공유 모델

struct HealthRecord {
    let dataType: String
    let timestamp: Int64
    let endTimestamp: Int64
    let tzOffset: String
    let source: String
    let valueJson: String
    let createdAt: Int64
    /// 원본 HKSample.uuid (record 류). 집계 버킷·요약은 원본 레코드가 아니라 nil. 기본 nil 이라 빌더가 필요할 때만 채운다.
    var uid: String? = nil

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "dataType": dataType,
            "timestamp": timestamp,
            "endTimestamp": endTimestamp,
            "tzOffset": tzOffset,
            "source": source,
            "valueJson": valueJson,
            "createdAt": createdAt,
        ]
        if let uid = uid { dict["uid"] = uid }
        return dict
    }
}

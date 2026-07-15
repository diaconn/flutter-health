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

    /// 심박수를 **벽시계 10분 격자 버킷**(예: 09:00~09:10)별 평균/최소/최대(bpm)로 반환. metric 에서 분리된 독립 타입(heart_rate_interval).
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

    /// iOS 걸음은 step_segment(per-sample, queryStepSegments)로 수집(7/15 결정) → steps_interval 미수집.
    /// STEPS_INTERVAL(10분 격자)은 Android(SamsungHealthClient) 전용. querySteps 는 공용 API 라 시그니처만 유지하고 빈 리스트 반환.
    func querySteps(since: Date, to: Date) async -> [HealthRecord] { [] }

    /// 걸음 활동 구간 — stepCount 샘플을 각각 시작/종료/걸음수로 반환(iOS 전용).
    /// iPhone·워치가 동시 기록하면 시간 겹치는 샘플이 함께 옴 → sourceType 으로 구분.
    func queryStepSegments(since: Date, to: Date) async -> [HealthRecord] {
        await queryQuantitySamples(.stepCount, unit: .count(), dataType: Self.dataTypeStepSegment, since: since, to: to) { v, sample in
            let count = Int(v)
            return count > 0 ? StepSegmentValue(count: count, sourceType: Self.stepSourceType(sample)) : nil
        }
    }

    /// 기록 기기 종류를 phone|watch|tablet|other 로 정규화(기기명 대신).
    /// HKDevice 이름 또는 모델 식별자(예: "iPhone14,5", "Watch6,18")로 판별.
    private static func stepSourceType(_ sample: HKSample) -> String {
        let raw = (sample.device?.name ?? sample.sourceRevision.productType ?? "").lowercased()
        if raw.contains("watch") { return "watch" }
        if raw.contains("iphone") { return "phone" }
        if raw.contains("ipad") { return "tablet" }
        return "other"
    }

    /// 이동 거리를 **벽시계 10분 격자 버킷**별 합(distance_interval, m)으로 반환. metric 에서 분리된 독립 타입.
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

    /// 소비 칼로리를 **벽시계 10분 격자 버킷**별 합(calories_interval, total=활동+기초대사·active=활동, kcal)으로 반환.
    /// metric 에서 분리된 독립 타입. active·basal 격자를 각각 구해 버킷 시작 기준으로 병합한다.
    func queryCalories(since: Date, to: Date) async -> [HealthRecord] {
        async let activeB = queryGridBuckets(.activeEnergyBurned, options: .cumulativeSum, since: since, to: to)
        async let basalB = queryGridBuckets(.basalEnergyBurned, options: .cumulativeSum, since: since, to: to)
        // 버킷 시작(ms) → kcal 로 인덱싱. total = active + basal, 한쪽만 있는 칸도 살리려 키 합집합으로 순회.
        func kcalByStart(_ buckets: [(start: Date, end: Date, stats: HKStatistics)]) -> [Int64: Double] {
            Dictionary(uniqueKeysWithValues: buckets.compactMap { b in
                (b.stats.sumQuantity()?.doubleValue(for: .kilocalorie())).map { (toMs(b.start), $0) }
            })
        }
        let active = kcalByStart(await activeB)
        let basal = kcalByStart(await basalB)
        let bucketMs = Int64(Self.bucketMinutes * 60_000)
        let tz = currentTzOffset()
        let createdAt = toMs(Date())
        return Set(active.keys).union(basal.keys).sorted().compactMap { startMs in
            let total = (active[startMs] ?? 0) + (basal[startMs] ?? 0)
            guard total > 0 else { return nil }
            let value = CaloriesIntervalValue(total: total, active: active[startMs])
            return HealthRecord(dataType: Self.dataTypeCaloriesInterval, timestamp: startMs, endTimestamp: startMs + bucketMs, tzOffset: tz, source: Self.source, valueJson: encodeToJson(value), createdAt: createdAt)
        }
    }

    /// 당일 누적 걸음 수(steps_daily) 1건 — [date] 가 가리키는 날 자정~수집 시점 누적. metric 에서 분리된 독립 타입.
    func queryStepsDaily(date: Date) async -> [HealthRecord] {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let total = await querySumBucketed(.stepCount, unit: .count(), bucketStart: dayStart, interval: DateComponents(day: 1)), total > 0 else { return [] }
        let value = StepsDailyValue(count: Int(total))
        return [HealthRecord(dataType: Self.dataTypeStepsDaily, timestamp: toMs(dayStart), endTimestamp: toMs(Date()), tzOffset: currentTzOffset(), source: Self.source, valueJson: encodeToJson(value), createdAt: toMs(Date()))]
    }

    func queryEndedSleepSessions(since: Date, to: Date) async -> [HealthRecord] {
        guard HKObjectType.categoryType(forIdentifier: .sleepAnalysis) != nil else { return [] }
        // 조회 시작을 하루 앞당겨 밤잠 앞부분 조각까지 확보 → 세션 시작시각(session.start)이 매번 같게 잡히게 한다(Android queryEndedSleepSessions 와 동일).
        // since(36h 씩 밀리는 수집 창)부터 그대로 조회하면 since 가 그 밤 수면 도중에 걸릴 때 세션 시작이 잘려,
        // 같은 밤이 매번 다른 start_dttm 으로 저장 → UNIQUE(member,'SLEEP',start_dttm) 중복제거를 통과해 한 밤이 여러 행으로 쌓인다.
        let fetchSince = Calendar.current.date(byAdding: .day, value: -1, to: since) ?? since
        let predicate = HKQuery.predicateForSamples(withStart: fetchSince, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let sessions = groupSleepSessions(samples: samples)
        let tz = currentTzOffset()
        let sinceMs = toMs(since)
        let toMsBound = toMs(to)
        // 최신순(내림차순) 출력 — 그룹핑은 내부에서 시간순으로 처리되므로 여기서 종료 후 정렬.
        return sessions.sorted { $0.start > $1.start }.compactMap { session in
            let startMs = toMs(session.start)
            let endMs = toMs(session.end)
            // 1일 패딩으로 끌어온 더 과거 세션은 제외 — 원래 요청 창(since~to)에 "종료된" 세션만 emit(Android .filter{endTimestamp in since..to} 동형).
            guard endMs >= sinceMs && endMs <= toMsBound else { return nil }
            let durationMin = Int((endMs - startMs) / 60000)
            guard durationMin > 0 else { return nil }
            let value = SleepValue(durationMin: durationMin)
            return HealthRecord(
                dataType: Self.dataTypeSleep,
                timestamp: startMs,
                endTimestamp: endMs,
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: toMs(Date())
            )
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
        async let basalKcalQ = querySumBucketed(.basalEnergyBurned, unit: .kilocalorie(), bucketStart: hourStart, interval: hourInterval)
        async let activeTimeMinQ = querySumBucketed(.appleExerciseTime, unit: .minute(), bucketStart: hourStart, interval: hourInterval)
        async let distanceTotal = querySumBucketed(.distanceWalkingRunning, unit: .meter(), bucketStart: hourStart, interval: hourInterval)

        let hr = await hrStats
        let st = await stepsTotal
        let activeKcal = await activeKcalQ
        let basalKcal = await basalKcalQ
        let exTimeMin = await activeTimeMinQ
        let dist = await distanceTotal
        let totalKcal: Double? = (activeKcal == nil && basalKcal == nil) ? nil : (activeKcal ?? 0) + (basalKcal ?? 0)

        if hr.avg == nil && st == nil && totalKcal == nil {
            return nil
        }

        let hourLabel = hourFormatter.string(from: hourStart)

        let value = HourlySummaryValue(
            hour: hourLabel,
            heartRateAvg: hr.avg,
            heartRateMin: hr.min,
            heartRateMax: hr.max,
            stepsTotal: st.map { Int($0) },
            caloriesTotal: totalKcal,
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

        let hr = await hrStats
        let st = await stepsTotal
        let activeKcal = await caloriesActive
        let basalKcal = await caloriesBasal
        let exTimeMin = await activeTimeMin
        let dist = await distanceTotal
        // total = active + basal (둘 중 하나만 있으면 그것만, 둘 다 nil 이면 nil)
        let totalKcal: Double? = (activeKcal == nil && basalKcal == nil) ? nil : (activeKcal ?? 0) + (basalKcal ?? 0)

        let sleepSessions = await queryEndedSleepSessions(since: dayStart, to: dayEnd)
        let mainSleep = sleepSessions.max { ($0.endTimestamp - $0.timestamp) < ($1.endTimestamp - $1.timestamp) }
        let sleepDuration = mainSleep.map { Int(($0.endTimestamp - $0.timestamp) / 60000) }

        let exerciseSessions = await queryEndedExerciseSessions(since: dayStart, to: dayEnd)
        let exerciseCount = exerciseSessions.isEmpty ? nil : exerciseSessions.count
        let exerciseTotalMin = exerciseSessions.isEmpty ? nil : Int(exerciseSessions.reduce(0) { $0 + ($1.endTimestamp - $1.timestamp) } / 60000)
        let exerciseCaloriesList = exerciseSessions.compactMap {
            try? jsonDecoder.decode(ExerciseValue.self, from: Data($0.valueJson.utf8)).calories
        }
        let exerciseTotalCalories: Double? = exerciseCaloriesList.isEmpty ? nil : exerciseCaloriesList.reduce(0.0, +)

        if hr.avg == nil && st == nil && sleepDuration == nil && exerciseCount == nil {
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
            sleepDuration: sleepDuration,
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

    /// 체중·체성분 — HealthKit 원천과 1:1. 체중은 weight 타입, BMI·체지방률은
    /// 각자 독립 타입으로 per-sample 적재. 3종 동시 조회(직렬 대기 방지).
    func queryWeights(since: Date, to: Date) async -> [HealthRecord] {
        async let weight  = queryQuantitySamples(.bodyMass, unit: weightUnit, dataType: Self.dataTypeWeight, since: since, to: to) { kg, _ in kg > 0 ? WeightValue(weight: kg) : nil }
        async let bmi     = queryQuantitySamples(.bodyMassIndex, unit: .count(), dataType: Self.dataTypeBmi, since: since, to: to) { v, _ in v > 0 ? QuantitySampleValue(value: v, unit: "kg/m²") : nil }
        // bodyFat 은 .percent()=분수(0~1)라 100배해 %.
        async let bodyFat = queryQuantitySamples(.bodyFatPercentage, unit: .percent(), dataType: Self.dataTypeBodyFatPercentage, since: since, to: to) { v, _ in v > 0 ? QuantitySampleValue(value: v * 100, unit: "%") : nil }
        var out = await weight
        out += await bmi
        out += await bodyFat
        return out
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
                        uid: correlation.uuid.uuidString
                    )
                }
                continuation.resume(returning: records)
            }
            self.store.execute(query)
        }
    }

    func queryNutrition(since: Date, to: Date) async -> [HealthRecord] {
        // 원천 1:1 — HealthKit 의 영양소별 개별 샘플을 각자 독립 타입(nutrition_*)으로 per-sample emit (집계/번들 제거).
        // 건강앱 식이 에너지(섭취 에너지)와 각 영양소는 HealthKit 에서 이미 별개 수량 타입이라, 그대로 1:1 적재한다.
        let kcal = HKUnit.kilocalorie()
        let g = HKUnit.gram()
        let mg = HKUnit.gramUnit(with: .milli)
        let mcg = HKUnit.gramUnit(with: .micro)
        let specs: [(HKQuantityTypeIdentifier, String, HKUnit, String)] = [
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
        // 영양소별 쿼리를 동시 실행(직렬 대기 방지) — @unchecked Sendable 라 task group 안전. 순서 무관(레코드가 dataType/timestamp 보유).
        return await withTaskGroup(of: [HealthRecord].self) { group in
            for (id, dataType, unit, unitLabel) in specs {
                group.addTask {
                    await self.queryQuantitySamples(id, unit: unit, dataType: dataType, since: since, to: to) { v, _ in
                        v > 0 ? QuantitySampleValue(value: v, unit: unitLabel) : nil
                    }
                }
            }
            var out: [HealthRecord] = []
            for await chunk in group { out += chunk }
            return out
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
    /// - 수면·영양은 델타가 raw 조각으로만 온다(수면=단계 조각 / 영양=섭취에너지 샘플) → 추가분이 있으면 그 구간을 정식 빌더로 재조회해 완전한 레코드(수면=병합 세션 / 영양=영양소 per-sample 전체)로 반환한다.
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
        // 2-a) 수면·영양: anchored 델타는 raw 조각으로만 온다(수면=단계 조각 여러 개 / 영양=섭취에너지 샘플).
        //      added 가 있으면 그 최소 시작시각~현재를 정식 빌더로 재조회해 완전한 레코드로 대체한다
        //      (수면=30분 병합 세션 1건 / 영양=영양소별 per-sample 전체). added 가 비면 삭제뿐 → deletedUids·token 만 반환.
        if dataType == Self.dataTypeSleep || dataType == "nutrition" || dataType == "nutrition_energy" {
            guard let spanStart = added.map({ $0.startDate }).min() else { return ([], deletedUids, token) }
            let full = dataType == Self.dataTypeSleep
                ? await queryEndedSleepSessions(since: spanStart, to: Date())
                : await queryNutrition(since: spanStart, to: Date())
            return (full, deletedUids, token)
        }
        // 2-b) 그 외(운동·체중·혈당 등) 추가 샘플 → 개별 레코드. 운동은 완전 빌더 재사용, 나머지는 최소 레코드(uid+시각+원본값).
        let tz = currentTzOffset()
        let now = toMs(Date())
        var records: [HealthRecord] = []
        for sample in added {
            if let workout = sample as? HKWorkout {
                if let r = await buildExerciseRecord(workout, tz: tz) { records.append(r) }
            } else if let r = buildChangeRecord(sample, dataType: dataType, tz: tz, now: now) {
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
        case dataTypeBloodGlucose:  return HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        case dataTypeWaterIntake:   return HKObjectType.quantityType(forIdentifier: .dietaryWater)
        case dataTypeBloodPressure: return HKObjectType.correlationType(forIdentifier: .bloodPressure)
        // 영양은 섭취 에너지(대표 1종)로 처리 — 실제로는 영양소별 개별 샘플이라 각자 uid 를 가진다.
        case "nutrition", "nutrition_energy": return HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        default: return nil
        }
    }

    /// 운동 외 샘플을 최소 레코드로 변환(uid + 시작/종료 + 원본값 요약). 값 완전성보다 uid·변경신호 식별이 목적.
    private func buildChangeRecord(_ sample: HKSample, dataType: String, tz: String, now: Int64) -> HealthRecord? {
        let start = toMs(sample.startDate)
        let end = toMs(sample.endDate)
        var valueJson = "{}"
        if let cat = sample as? HKCategorySample {
            // 수면 등 카테고리 — 세션 병합 전 raw 조각(단계값+지속분)이 그대로 노출됨.
            valueJson = encodeToJson(ChangeCategoryValue(categoryValue: cat.value, durationMin: Int((end - start) / 60000)))
        } else if let q = sample as? HKQuantitySample {
            // 수량 — 단위 불일치 크래시 방지를 위해 HKQuantity.description(예 "72 count/min")을 그대로 담는다.
            valueJson = encodeToJson(ChangeQuantityValue(quantity: q.quantity.description))
        }
        return HealthRecord(dataType: dataType, timestamp: start, endTimestamp: end, tzOffset: tz, source: Self.source, valueJson: valueJson, createdAt: now, uid: sample.uuid.uuidString)
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
        //    권한 요청은 위 컴포넌트(systolic/diastolic)로만, correlation 은 조회(HKCorrelationQuery)용. (2026-06-22 실측 확인)
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
    /// bucketStart 에 맞춘 단일 버킷의 합만 반환(steps_daily·hourly/daily summary 의 일/시 누적용).
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

    private func groupSleepSessions(samples: [HKCategorySample]) -> [SleepSession] {
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        var sessions: [SleepSession] = []
        var current: SleepSession? = nil

        for sample in sortedSamples {
            let isAwake = HKCategoryValueSleepAnalysis(rawValue: sample.value) == .awake
            guard !isAwake || current != nil else { continue }

            if current == nil {
                current = SleepSession(start: sample.startDate, end: sample.endDate)
            }
            guard var session = current else { continue }

            let gapMin = sample.startDate.timeIntervalSince(session.end) / 60
            if gapMin > 30 {
                sessions.append(session)
                current = SleepSession(start: sample.startDate, end: sample.endDate)
                continue
            }

            session.end = max(session.end, sample.endDate)
            current = session
        }
        if let session = current {
            sessions.append(session)
        }
        return sessions
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

    // MARK: - 수면 세션 임시 구조체

    private struct SleepSession {
        var start: Date
        var end: Date
    }

    // MARK: - valueJson 직렬화용 Codable 구조체

    /// 심박수 10분 격자 버킷 값(bpm). metric 에서 분리된 독립 타입(heart_rate_interval).
    private struct HeartRateIntervalValue: Codable {
        let avg: Int?
        let min: Int?
        let max: Int?
    }

    /// 걸음 활동 구간 값(step_segment, iOS 전용). 개별 stepCount 샘플의 걸음수 + 기록 기기 종류.
    fileprivate struct StepSegmentValue: Codable {
        let count: Int
        let sourceType: String       // 기록 기기 종류: "phone"|"watch"|"tablet"|"other" (사용자 지정 기기명 대신 정규화)
    }

    /// 이동 거리 10분 격자 버킷 값(m). metric 에서 분리된 독립 타입(distance_interval).
    private struct DistanceIntervalValue: Codable {
        let distance: Double
    }

    /// 소비 칼로리 10분 격자 버킷 값(kcal). total=활동+기초대사, active=활동. metric 에서 분리된 독립 타입(calories_interval).
    private struct CaloriesIntervalValue: Codable {
        let total: Double
        let active: Double?
    }

    /// 당일 누적 걸음 수. metric 에서 분리된 독립 타입(steps_daily).
    private struct StepsDailyValue: Codable {
        let count: Int
    }

    fileprivate struct SleepValue: Codable {
        let durationMin: Int?
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
        let caloriesTotal: Double?          // total = basal + active
        let caloriesActiveTotal: Double?    // active 만
        let activeTimeTotal: Int?            // appleExerciseTime 분 합
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

    /// 변경 피드 — 카테고리(수면 등) raw 조각 값.
    private struct ChangeCategoryValue: Codable {
        let categoryValue: Int
        let durationMin: Int
    }

    /// 변경 피드 — 수량 샘플 원본값 문자열(단위 포함).
    private struct ChangeQuantityValue: Codable {
        let quantity: String
    }

    private struct DailySummaryValue: Codable {
        let date: String
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsTotal: Int?
        let caloriesTotal: Double?         // total = basal + active
        let caloriesActiveTotal: Double?   // active 만
        let activeTimeTotal: Int?           // appleExerciseTime 분 합
        let distanceTotal: Double?
        let sleepDuration: Int?
        let exerciseCount: Int?
        let exerciseTotalMin: Int?
        let exerciseTotalCalories: Double?
    }

    // MARK: - 상수

    static let bucketMinutes = 10
    static let dataTypeHeartRateInterval = "heart_rate_interval"
    static let dataTypeDistanceInterval = "distance_interval"
    static let dataTypeCaloriesInterval = "calories_interval"
    static let dataTypeStepsDaily = "steps_daily"
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
    static let dataTypeStepSegment = "step_segment"
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

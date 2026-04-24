import Foundation
import HealthKit
import os

/// Apple HealthKit 데이터 래퍼 (diaconn-aid-ios/HealthKitClient.swift 포팅 — diaconn 의존성 제거).
///
/// AppTime → Date() 직접 사용, AppLogger → os.Logger, HealthRecord → 로컬 struct
final class HealthKitClient {

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
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        return true
    }

    func queryMetric(from: Date, to: Date) async -> HealthRecord? {
        let dayStart = Calendar.current.startOfDay(for: to)

        async let hrStats = queryHeartRateStats(from: from, to: to)
        async let stepsInterval = querySumQuantity(.stepCount, unit: .count(), from: from, to: to)
        async let stepsDaily = querySumQuantity(.stepCount, unit: .count(), from: dayStart, to: to)
        async let caloriesInterval = querySumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: from, to: to)
        async let caloriesDaily = querySumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: dayStart, to: to)
        async let distanceInterval = querySumQuantity(.distanceWalkingRunning, unit: .meter(), from: from, to: to)
        async let distanceDaily = querySumQuantity(.distanceWalkingRunning, unit: .meter(), from: dayStart, to: to)
        async let spO2 = queryAvgQuantity(.oxygenSaturation, unit: .percent(), from: from, to: to)
        async let hrv = queryAvgQuantity(.heartRateVariabilitySDNN, unit: HKUnit(from: "ms"), from: from, to: to)

        let (hr, si, sd, ci, cd, di, dd, sp, h) = await (hrStats, stepsInterval, stepsDaily, caloriesInterval, caloriesDaily, distanceInterval, distanceDaily, spO2, hrv)

        if hr.avg == nil && si == nil && ci == nil && di == nil && sp == nil {
            return nil
        }

        let value = MetricValue(
            heartRateAvg: hr.avg,
            heartRateMin: hr.min,
            heartRateMax: hr.max,
            stepsInterval: si.map { Int($0) },
            stepsDaily: sd.map { Int($0) },
            caloriesInterval: ci,
            caloriesDaily: cd,
            distanceInterval: di,
            distanceDaily: dd,
            spO2: sp.map { Int($0 * 100) },
            hrv: h
        )
        return HealthRecord(
            dataType: Self.dataTypeMetric,
            timestamp: toMs(from),
            endTimestamp: toMs(to),
            tzOffset: currentTzOffset(),
            source: Self.source,
            valueJson: encodeToJson(value),
            createdAt: toMs(Date())
        )
    }

    func queryEndedSleepSessions(since: Date, to: Date) async -> [HealthRecord] {
        guard HKObjectType.categoryType(forIdentifier: .sleepAnalysis) != nil else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let sessions = groupSleepSessions(samples: samples)
        let tz = currentTzOffset()
        return sessions.compactMap { session in
            let startMs = toMs(session.start)
            let endMs = toMs(session.end)
            let durationMin = Int((endMs - startMs) / 60000)
            guard durationMin > 0 else { return nil }
            let value = SleepValue(
                durationMin: durationMin,
                awakeMin: session.awakeMin > 0 ? session.awakeMin : nil,
                lightMin: session.lightMin > 0 ? session.lightMin : nil,
                deepMin: session.deepMin > 0 ? session.deepMin : nil,
                remMin: session.remMin > 0 ? session.remMin : nil,
                stages: session.stages.isEmpty ? nil : session.stages
            )
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
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        return workouts.compactMap { workout in
            let startMs = toMs(workout.startDate)
            let endMs = toMs(workout.endDate)
            let durationMin = Int((endMs - startMs) / 60000)
            guard durationMin > 0 else { return nil }
            let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let heartRateAvg = workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            let heartRateMax = workout.statistics(for: HKQuantityType(.heartRate))?.maximumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                ?? workout.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
            let value = ExerciseValue(
                exerciseType: mapWorkoutType(workout.workoutActivityType),
                intensity: deriveIntensity(heartRateAvg: heartRateAvg.map { Int($0) }),
                durationMin: durationMin,
                calories: calories,
                heartRateAvg: heartRateAvg.map { Int($0) },
                heartRateMax: heartRateMax.map { Int($0) },
                distance: distance
            )
            return HealthRecord(
                dataType: Self.dataTypeExercise,
                timestamp: startMs,
                endTimestamp: endMs,
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: toMs(Date())
            )
        }
    }

    func queryHourlySummary(from hourStart: Date, to hourEnd: Date) async -> HealthRecord? {
        async let hrStats = queryHeartRateStats(from: hourStart, to: hourEnd)
        async let stepsTotal = querySumQuantity(.stepCount, unit: .count(), from: hourStart, to: hourEnd)
        async let caloriesTotalKcal = querySumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: hourStart, to: hourEnd)
        async let distanceTotalM = querySumQuantity(.distanceWalkingRunning, unit: .meter(), from: hourStart, to: hourEnd)

        let (hr, st, cal, dist) = await (hrStats, stepsTotal, caloriesTotalKcal, distanceTotalM)

        if hr.avg == nil && st == nil && cal == nil {
            return nil
        }

        let hourLabel = hourFormatter.string(from: hourStart)

        let value = HourlySummaryValue(
            hour: hourLabel,
            heartRateAvg: hr.avg,
            heartRateMin: hr.min,
            heartRateMax: hr.max,
            stepsTotal: st.map { Int($0) },
            caloriesTotalKcal: cal,
            distanceTotalM: dist
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
        async let stepsTotal = querySumQuantity(.stepCount, unit: .count(), from: dayStart, to: dayEnd)
        async let caloriesTotalKcal = querySumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: dayStart, to: dayEnd)
        async let distanceTotalM = querySumQuantity(.distanceWalkingRunning, unit: .meter(), from: dayStart, to: dayEnd)

        let (hr, st, cal_total, dist) = await (hrStats, stepsTotal, caloriesTotalKcal, distanceTotalM)

        let sleepSessions = await queryEndedSleepSessions(since: dayStart, to: dayEnd)
        let mainSleep = sleepSessions.max { ($0.endTimestamp - $0.timestamp) < ($1.endTimestamp - $1.timestamp) }
        let sleepDurationMin = mainSleep.map { Int(($0.endTimestamp - $0.timestamp) / 60000) }
        let sleepValue = mainSleep.flatMap { try? jsonDecoder.decode(SleepValue.self, from: Data($0.valueJson.utf8)) }

        let exerciseSessions = await queryEndedExerciseSessions(since: dayStart, to: dayEnd)
        let exerciseCount = exerciseSessions.isEmpty ? nil : exerciseSessions.count
        let exerciseTotalMin = exerciseSessions.isEmpty ? nil : Int(exerciseSessions.reduce(0) { $0 + ($1.endTimestamp - $1.timestamp) } / 60000)
        let exerciseCaloriesList = exerciseSessions.compactMap {
            try? jsonDecoder.decode(ExerciseValue.self, from: Data($0.valueJson.utf8)).calories
        }
        let exerciseTotalCalories: Double? = exerciseCaloriesList.isEmpty ? nil : exerciseCaloriesList.reduce(0.0, +)

        if hr.avg == nil && st == nil && sleepDurationMin == nil && exerciseCount == nil {
            return nil
        }

        let dateString = dateFormatter.string(from: dayStart)

        let value = DailySummaryValue(
            date: dateString,
            heartRateAvg: hr.avg,
            heartRateMin: hr.min,
            heartRateMax: hr.max,
            stepsTotal: st.map { Int($0) },
            caloriesTotalKcal: cal_total,
            distanceTotalM: dist,
            sleepDurationMin: sleepDurationMin,
            sleepDeepMin: sleepValue?.deepMin,
            sleepRemMin: sleepValue?.remMin,
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

    // MARK: - Private

    private let store = HKHealthStore()
    private let logger = Logger(subsystem: "com.diaconn.flutter_health", category: "HealthKitClient")
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

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

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.workoutType()
    ]

    private func currentTzOffset() -> String {
        let seconds = TimeZone.current.secondsFromGMT()
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        let sign = seconds >= 0 ? "+" : "-"
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }

    private func querySumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        await queryStatistics(identifier, options: .cumulativeSum, unit: unit, from: from, to: to) { $0.sumQuantity() }
    }

    private func queryAvgQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        await queryStatistics(identifier, options: .discreteAverage, unit: unit, from: from, to: to) { $0.averageQuantity() }
    }

    private func queryHeartRateStats(from: Date, to: Date) async -> (avg: Int?, min: Int?, max: Int?) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil, nil)
        }
        let unit = HKUnit(from: "count/min")
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
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

    private func queryStatistics(
        _ identifier: HKQuantityTypeIdentifier,
        options: HKStatisticsOptions,
        unit: HKUnit,
        from: Date,
        to: Date,
        valueExtractor: @escaping (HKStatistics) -> HKQuantity?
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                let value = stats.flatMap { valueExtractor($0)?.doubleValue(for: unit) }
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func groupSleepSessions(samples: [HKCategorySample]) -> [SleepSession] {
        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        var sessions: [SleepSession] = []
        var current: SleepSession? = nil

        for sample in sortedSamples {
            let stageStr = mapSleepStage(sample.value)
            guard stageStr != "awake" || current != nil else { continue }

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
            let durationMin = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
            switch stageStr {
            case "awake": session.awakeMin += durationMin
            case "light": session.lightMin += durationMin
            case "deep": session.deepMin += durationMin
            case "rem": session.remMin += durationMin
            default: break
            }
            let sStartMs = toMs(sample.startDate)
            let sEndMs = toMs(sample.endDate)
            session.stages.append(SleepStageValue(stage: stageStr, startMs: sStartMs, endMs: sEndMs))
            current = session
        }
        if let session = current {
            sessions.append(session)
        }
        return sessions
    }

    private func mapSleepStage(_ value: Int) -> String {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else { return "light" }
        switch stage {
        case .awake: return "awake"
        case .asleepCore: return "light"
        case .asleepREM: return "rem"
        case .asleepDeep: return "deep"
        case .asleepUnspecified, .inBed: return "light"
        @unknown default: return "light"
        }
    }

    private func mapWorkoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "walking"
        case .running: return "running"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: return "strength_training"
        case .yoga, .mindAndBody: return "yoga"
        case .elliptical: return "elliptical"
        case .dance, .danceInspiredTraining, .socialDance, .barre: return "dance"
        default: return "other"
        }
    }

    private func deriveIntensity(heartRateAvg: Int?) -> String? {
        guard let hr = heartRateAvg else { return nil }
        switch hr {
        case ..<100: return "low"
        case 100..<140: return "medium"
        default: return "high"
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
        var awakeMin: Int = 0
        var lightMin: Int = 0
        var deepMin: Int = 0
        var remMin: Int = 0
        var stages: [SleepStageValue] = []
    }

    // MARK: - valueJson 직렬화용 Codable 구조체

    private struct MetricValue: Codable {
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsInterval: Int?
        let stepsDaily: Int?
        let caloriesInterval: Double?
        let caloriesDaily: Double?
        let distanceInterval: Double?
        let distanceDaily: Double?
        let spO2: Int?
        let hrv: Double?
    }

    private struct SleepStageValue: Codable {
        let stage: String
        let startMs: Int64
        let endMs: Int64
    }

    fileprivate struct SleepValue: Codable {
        let durationMin: Int?
        let awakeMin: Int?
        let lightMin: Int?
        let deepMin: Int?
        let remMin: Int?
        let stages: [SleepStageValue]?
    }

    fileprivate struct ExerciseValue: Codable {
        let exerciseType: String
        let intensity: String?
        let durationMin: Int?
        let calories: Double?
        let heartRateAvg: Int?
        let heartRateMax: Int?
        let distance: Double?
    }

    private struct HourlySummaryValue: Codable {
        let hour: String
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsTotal: Int?
        let caloriesTotalKcal: Double?
        let distanceTotalM: Double?
    }

    private struct DailySummaryValue: Codable {
        let date: String
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsTotal: Int?
        let caloriesTotalKcal: Double?
        let distanceTotalM: Double?
        let sleepDurationMin: Int?
        let sleepDeepMin: Int?
        let sleepRemMin: Int?
        let exerciseCount: Int?
        let exerciseTotalMin: Int?
        let exerciseTotalCalories: Double?
    }

    // MARK: - 상수

    static let dataTypeMetric = "metric"
    static let dataTypeSleep = "sleep"
    static let dataTypeExercise = "exercise"
    static let dataTypeHourlySummary = "hourly_summary"
    static let dataTypeDailySummary = "daily_summary"
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

    func toDictionary() -> [String: Any] {
        return [
            "dataType": dataType,
            "timestamp": timestamp,
            "endTimestamp": endTimestamp,
            "tzOffset": tzOffset,
            "source": source,
            "valueJson": valueJson,
            "createdAt": createdAt,
        ]
    }
}

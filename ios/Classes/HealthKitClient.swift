import Foundation
import HealthKit
import CoreLocation
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

        // 복약(iOS 26+)은 일반 read set 에 넣으면 크래시 → per-object 권한을 따로 요청한다.
        // 사용자가 약별로 허용해야 queryMedication 이 읽을 수 있고, 실패/취소해도 전체 흐름은 성공 처리.
        if #available(iOS 26.0, *) {
            do {
                try await store.requestPerObjectReadAuthorization(for: HKObjectType.userAnnotatedMedicationType(), predicate: nil)
                logger.info("requestPermission: medication per-object auth completed")
            } catch {
                logger.info("requestPermission: medication per-object auth skipped/failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    func queryMetric(from: Date, to: Date) async -> HealthRecord? {
        let dayStart = Calendar.current.startOfDay(for: to)
        let dayInterval = DateComponents(day: 1)

        async let hrStats = queryHeartRateStats(from: from, to: to)
        async let stepsInterval = querySumQuantity(.stepCount, unit: .count(), from: from, to: to)
        // *Daily(오늘 누적)는 자정 기준 버킷 합(querySumBucketed)으로 over-count 를 막는다.
        // *Interval(임의 구간)은 버킷이 안 맞아 querySumQuantity 를 그대로 쓴다.
        async let stepsDaily = querySumBucketed(.stepCount, unit: .count(), bucketStart: dayStart, interval: dayInterval)
        async let activeInterval = querySumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: from, to: to)
        async let activeDaily = querySumBucketed(.activeEnergyBurned, unit: .kilocalorie(), bucketStart: dayStart, interval: dayInterval)
        async let basalInterval = querySumQuantity(.basalEnergyBurned, unit: .kilocalorie(), from: from, to: to)
        async let basalDaily = querySumBucketed(.basalEnergyBurned, unit: .kilocalorie(), bucketStart: dayStart, interval: dayInterval)
        async let distanceInterval = querySumQuantity(.distanceWalkingRunning, unit: .meter(), from: from, to: to)
        async let distanceDaily = querySumBucketed(.distanceWalkingRunning, unit: .meter(), bucketStart: dayStart, interval: dayInterval)
        async let spO2 = queryAvgQuantity(.oxygenSaturation, unit: .percent(), from: from, to: to)
        async let hrv = queryAvgQuantity(.heartRateVariabilitySDNN, unit: HKUnit(from: "ms"), from: from, to: to)

        // 한 번에 await 하면 타입체커가 못 풀어 개별 await.
        let hr = await hrStats
        let si = await stepsInterval
        let sd = await stepsDaily
        let ai = await activeInterval
        let ad = await activeDaily
        let bi = await basalInterval
        let bd = await basalDaily
        let di = await distanceInterval
        let dd = await distanceDaily
        let sp = await spO2
        let h = await hrv

        // total = basal + active (둘 중 하나만 있으면 그것만, 둘 다 nil 이면 nil)
        func sumOptional(_ a: Double?, _ b: Double?) -> Double? {
            if a == nil && b == nil { return nil }
            return (a ?? 0) + (b ?? 0)
        }
        let totalInterval = sumOptional(ai, bi)
        let totalDaily = sumOptional(ad, bd)

        if hr.avg == nil && si == nil && ai == nil && bi == nil && di == nil && sp == nil {
            return nil
        }

        let value = MetricValue(
            heartRateAvg: hr.avg,
            heartRateMin: hr.min,
            heartRateMax: hr.max,
            stepsInterval: si.map { Int($0) },
            stepsDaily: sd.map { Int($0) },
            caloriesInterval: totalInterval,
            caloriesDaily: totalDaily,
            caloriesActiveInterval: ai,
            caloriesActiveDaily: ad,
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
        var records: [HealthRecord] = []
        for workout in workouts {
            if let r = await buildExerciseRecord(workout, tz: tz) {
                records.append(r)
            }
        }
        return records
    }

    /// HKWorkout 의 statistics·events·activities·metadata·device·route 를 한 레코드로 통합.
    private func buildExerciseRecord(_ workout: HKWorkout, tz: String) async -> HealthRecord? {
        let startMs = toMs(workout.startDate)
        let endMs = toMs(workout.endDate)
        let durationMin = Int((endMs - startMs) / 60000)
        guard durationMin > 0 else { return nil }

        let bpm = HKUnit(from: "count/min")
        let mPerSec = HKUnit.meter().unitDivided(by: HKUnit.second())
        let cpm = HKUnit(from: "count/min")
        let watt = HKUnit.watt()

        var v = ExerciseValue(exerciseType: mapWorkoutType(workout.workoutActivityType))
        v.durationMin = durationMin

        // 칼로리·HR·거리·걸음 (statistics)
        // 수동 추가 워크아웃은 statistics(for:) 가 nil → totalEnergyBurned 로 폴백 (워치는 statistics 가 채워져 이중계산 없음).
        v.calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            ?? workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        let hrStats = workout.statistics(for: HKQuantityType(.heartRate))
        v.heartRateAvg = (hrStats?.averageQuantity()?.doubleValue(for: bpm)).map(Int.init)
        v.heartRateMax = (hrStats?.maximumQuantity()?.doubleValue(for: bpm)).map(Int.init)
        v.heartRateMin = (hrStats?.minimumQuantity()?.doubleValue(for: bpm)).map(Int.init)
        v.intensity = deriveIntensity(heartRateAvg: v.heartRateAvg)
        v.distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
            ?? workout.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
            ?? workout.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity()?.doubleValue(for: .meter())
        if let steps = workout.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count()) {
            v.count = Int(steps)
            v.countType = "step"
        }

        // 파워/케이던스/속도 (iOS 16+/17+) — 모달리티별
        if #available(iOS 16.0, *) {
            let runPow = workout.statistics(for: HKQuantityType(.runningPower))
            let runSpd = workout.statistics(for: HKQuantityType(.runningSpeed))
            v.maxPower = runPow?.maximumQuantity()?.doubleValue(for: watt)
            v.meanPower = runPow?.averageQuantity()?.doubleValue(for: watt)
            v.maxSpeed = runSpd?.maximumQuantity()?.doubleValue(for: mPerSec)
            v.meanSpeed = runSpd?.averageQuantity()?.doubleValue(for: mPerSec)
        }
        if #available(iOS 17.0, *) {
            // 자전거 파워가 더 일반적이라 RunningPower 결과보다 우선
            if let cycPow = workout.statistics(for: HKQuantityType(.cyclingPower)) {
                v.maxPower = cycPow.maximumQuantity()?.doubleValue(for: watt) ?? v.maxPower
                v.meanPower = cycPow.averageQuantity()?.doubleValue(for: watt) ?? v.meanPower
            }
            if let cycSpd = workout.statistics(for: HKQuantityType(.cyclingSpeed)) {
                v.maxSpeed = cycSpd.maximumQuantity()?.doubleValue(for: mPerSec) ?? v.maxSpeed
                v.meanSpeed = cycSpd.averageQuantity()?.doubleValue(for: mPerSec) ?? v.meanSpeed
            }
            if let cad = workout.statistics(for: HKQuantityType(.cyclingCadence)) {
                v.maxCadence = cad.maximumQuantity()?.doubleValue(for: cpm)
                v.meanCadence = cad.averageQuantity()?.doubleValue(for: cpm)
            }
        }

        // metadata 매핑
        let md = workout.metadata ?? [:]
        v.altitudeGain = (md[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
        v.altitudeLoss = (md[HKMetadataKeyElevationDescended] as? HKQuantity)?.doubleValue(for: .meter())
        v.isIndoor = md[HKMetadataKeyIndoorWorkout] as? Bool
        // 문자열 단위 파서는 NSException 위험 → 빌더 API 로 MET 단위 구성.
        let metsUnit = HKUnit.kilocalorie().unitDivided(
            by: HKUnit.hour().unitMultiplied(by: HKUnit.gramUnit(with: .kilo))
        )
        v.averageMets = (md[HKMetadataKeyAverageMETs] as? HKQuantity)?.doubleValue(for: metsUnit)
        if let cond = md[HKMetadataKeyWeatherCondition] as? Int {
            v.weatherCondition = mapWeatherCondition(cond)
        }
        v.weatherTemperature = (md[HKMetadataKeyWeatherTemperature] as? HKQuantity)?.doubleValue(for: .degreeCelsius())
        // percent() 는 0~1 분율 → %(0~100)로 변환.
        v.weatherHumidity = (md[HKMetadataKeyWeatherHumidity] as? HKQuantity)
            .map { $0.doubleValue(for: HKUnit.percent()) * 100 }

        // 수영 metadata
        let poolLen = (md[HKMetadataKeyLapLength] as? HKQuantity)?.doubleValue(for: .meter())
        let swimLoc = (md[HKMetadataKeySwimmingLocationType] as? Int).flatMap(mapSwimmingLocation)
        let swimStr = (md[HKMetadataKeySwimmingStrokeStyle] as? Int).flatMap(mapSwimmingStroke)
        if poolLen != nil || swimLoc != nil || swimStr != nil {
            v.swimming = ExerciseSwimmingInfo(
                poolLength: poolLen.map { Int($0) },
                poolLengthUnit: poolLen != nil ? "m" : nil,
                totalDistance: nil,
                totalDurationSec: nil,
                locationType: swimLoc,
                strokeStyle: swimStr
            )
        }

        // events (HKWorkoutEvent)
        if let evs = workout.workoutEvents, !evs.isEmpty {
            v.events = evs.map { ev in
                ExerciseEventValue(
                    type: mapWorkoutEventType(ev.type),
                    startMs: Int64(ev.dateInterval.start.timeIntervalSince1970 * 1000),
                    endMs: Int64(ev.dateInterval.end.timeIntervalSince1970 * 1000),
                    metadata: nil
                )
            }
        }

        // activities (iOS 16+ HKWorkoutActivity)
        if #available(iOS 16.0, *) {
            let acts = workout.workoutActivities
            if !acts.isEmpty {
                v.activities = acts.map { act in
                    let actStart = act.startDate
                    let actEnd = act.endDate ?? workout.endDate
                    let actDurMin = Int(actEnd.timeIntervalSince(actStart) / 60)
                    let actCal = act.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                    let actDist = act.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
                        ?? act.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter())
                        ?? act.statistics(for: HKQuantityType(.distanceSwimming))?.sumQuantity()?.doubleValue(for: .meter())
                    let actIsIndoor = act.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
                    return ExerciseActivityValue(
                        activityType: mapWorkoutType(act.workoutConfiguration.activityType),
                        startMs: Int64(actStart.timeIntervalSince1970 * 1000),
                        endMs: Int64(actEnd.timeIntervalSince1970 * 1000),
                        durationMin: actDurMin,
                        calories: actCal,
                        distance: actDist,
                        isIndoor: actIsIndoor
                    )
                }
            }
        }

        // device
        if let d = workout.device {
            v.device = ExerciseDeviceValue(
                name: d.name,
                manufacturer: d.manufacturer,
                model: d.model,
                hardwareVersion: d.hardwareVersion,
                firmwareVersion: d.firmwareVersion,
                softwareVersion: d.softwareVersion,
                localIdentifier: d.localIdentifier,
                udiDeviceIdentifier: d.udiDeviceIdentifier
            )
        }

        // route (async, 워크아웃당 1회 round-trip) + min/max altitude 도 GPS 에서 산출
        if let points = await fetchRoutePointsForWorkout(workout), !points.isEmpty {
            v.route = points
            let alts = points.compactMap { $0.altitude }
            if !alts.isEmpty {
                v.maxAltitude = alts.max()
                v.minAltitude = alts.min()
            }
        }

        return HealthRecord(
            dataType: Self.dataTypeExercise,
            timestamp: startMs,
            endTimestamp: endMs,
            tzOffset: tz,
            source: Self.source,
            valueJson: encodeToJson(v),
            createdAt: toMs(Date())
        )
    }

    /// HKWorkout 에 첨부된 모든 HKWorkoutRoute 를 합쳐 평탄화된 좌표 배열 반환. 없으면 nil.
    private func fetchRoutePointsForWorkout(_ workout: HKWorkout) async -> [ExerciseRoutePointValue]? {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let routes = try? await descriptor.result(for: store), !routes.isEmpty else { return nil }
        var all: [ExerciseRoutePointValue] = []
        for route in routes {
            let locs = await fetchRouteLocations(route)
            for loc in locs {
                all.append(ExerciseRoutePointValue(
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    altitude: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
                    accuracy: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil,
                    timestampMs: Int64(loc.timestamp.timeIntervalSince1970 * 1000)
                ))
            }
        }
        return all.isEmpty ? nil : all
    }

    /// HKWorkoutEventType → 문자열 매핑 (Android 패턴과 통일).
    private func mapWorkoutEventType(_ t: HKWorkoutEventType) -> String {
        switch t {
        case .pause: return "pause"
        case .resume: return "resume"
        case .lap: return "lap"
        case .marker: return "marker"
        case .motionPaused: return "motionPaused"
        case .motionResumed: return "motionResumed"
        case .segment: return "segment"
        case .pauseOrResumeRequest: return "pauseOrResumeRequest"
        @unknown default: return "unknown"
        }
    }

    /// HKWeatherCondition rawValue → snake_case 문자열 매핑.
    /// rawValue 정의: HealthKit `HKMetadataEnums.h:208~237` (None=0 ~ Tornado=27).
    private func mapWeatherCondition(_ raw: Int) -> String? {
        switch raw {
        case 0: return nil          // None — 데이터 없음
        case 1: return "clear"
        case 2: return "fair"
        case 3: return "partly_cloudy"
        case 4: return "mostly_cloudy"
        case 5: return "cloudy"
        case 6: return "foggy"
        case 7: return "haze"
        case 8: return "windy"
        case 9: return "blustery"
        case 10: return "smoky"
        case 11: return "dust"
        case 12: return "snow"
        case 13: return "hail"
        case 14: return "sleet"
        case 15: return "freezing_drizzle"
        case 16: return "freezing_rain"
        case 17: return "mixed_rain_and_hail"
        case 18: return "mixed_rain_and_snow"
        case 19: return "mixed_rain_and_sleet"
        case 20: return "mixed_snow_and_sleet"
        case 21: return "drizzle"
        case 22: return "scattered_showers"
        case 23: return "showers"
        case 24: return "thunderstorms"
        case 25: return "tropical_storm"
        case 26: return "hurricane"
        case 27: return "tornado"
        default: return nil
        }
    }

    /// HKSwimmingLocationType rawValue → 문자열.
    private func mapSwimmingLocation(_ raw: Int) -> String? {
        switch raw {
        case 1: return "Pool"
        case 2: return "OpenWater"
        default: return nil
        }
    }

    /// HKSwimmingStrokeStyle rawValue → 문자열.
    private func mapSwimmingStroke(_ raw: Int) -> String? {
        switch raw {
        case 0: return "Unknown"
        case 1: return "Mixed"
        case 2: return "Freestyle"
        case 3: return "Backstroke"
        case 4: return "Breaststroke"
        case 5: return "Butterfly"
        case 6: return "Kickboard"
        default: return nil
        }
    }

    func queryHourlySummary(from hourStart: Date, to hourEnd: Date) async -> HealthRecord? {
        async let hrStats = queryHeartRateStats(from: hourStart, to: hourEnd)
        // 정시 기준 버킷 합산 — 경계 샘플을 시간비례로 나누고 중복 제거.
        let hourInterval = DateComponents(hour: 1)
        async let stepsTotal = querySumBucketed(.stepCount, unit: .count(), bucketStart: hourStart, interval: hourInterval)
        async let activeKcalQ = querySumBucketed(.activeEnergyBurned, unit: .kilocalorie(), bucketStart: hourStart, interval: hourInterval)
        async let basalKcalQ = querySumBucketed(.basalEnergyBurned, unit: .kilocalorie(), bucketStart: hourStart, interval: hourInterval)
        async let activeTimeMinQ = querySumBucketed(.appleExerciseTime, unit: .minute(), bucketStart: hourStart, interval: hourInterval)
        async let distanceTotalM = querySumBucketed(.distanceWalkingRunning, unit: .meter(), bucketStart: hourStart, interval: hourInterval)

        let hr = await hrStats
        let st = await stepsTotal
        let activeKcal = await activeKcalQ
        let basalKcal = await basalKcalQ
        let exTimeMin = await activeTimeMinQ
        let dist = await distanceTotalM
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
            caloriesTotalKcal: totalKcal,
            caloriesActiveTotalKcal: activeKcal,
            activeTimeTotalMin: exTimeMin.map { Int($0) },
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
        // 자정 기준 버킷 합산 — 경계 샘플을 시간비례로 나누고 중복 제거해 Apple 건강 UI 와 일치.
        let dayInterval = DateComponents(day: 1)
        async let stepsTotal = querySumBucketed(.stepCount, unit: .count(), bucketStart: dayStart, interval: dayInterval)
        async let caloriesActive = querySumBucketed(.activeEnergyBurned, unit: .kilocalorie(), bucketStart: dayStart, interval: dayInterval)
        async let caloriesBasal = querySumBucketed(.basalEnergyBurned, unit: .kilocalorie(), bucketStart: dayStart, interval: dayInterval)
        async let activeTimeMin = querySumBucketed(.appleExerciseTime, unit: .minute(), bucketStart: dayStart, interval: dayInterval)
        async let distanceTotalM = querySumBucketed(.distanceWalkingRunning, unit: .meter(), bucketStart: dayStart, interval: dayInterval)

        let hr = await hrStats
        let st = await stepsTotal
        let activeKcal = await caloriesActive
        let basalKcal = await caloriesBasal
        let exTimeMin = await activeTimeMin
        let dist = await distanceTotalM
        // total = active + basal (둘 중 하나만 있으면 그것만, 둘 다 nil 이면 nil)
        let totalKcal: Double? = (activeKcal == nil && basalKcal == nil) ? nil : (activeKcal ?? 0) + (basalKcal ?? 0)

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
            caloriesTotalKcal: totalKcal,
            caloriesActiveTotalKcal: activeKcal,
            activeTimeTotalMin: exTimeMin.map { Int($0) },
            distanceTotalM: dist,
            sleepDurationMin: sleepDurationMin,
            sleepDeepMin: sleepValue?.deepMin,
            sleepRemMin: sleepValue?.remMin,
            sleepLightMin: sleepValue?.lightMin,
            sleepAwakeMin: sleepValue?.awakeMin,
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

    func queryWeights(since: Date, to: Date) async -> [HealthRecord] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: qt, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        let now = toMs(Date())
        return samples.compactMap { sample in
            let kg = sample.quantity.doubleValue(for: weightUnit)
            guard kg > 0 else { return nil }
            // HealthKit의 .bodyMass 샘플에는 BMI/체지방률이 포함되지 않음.
            // 별도 .bodyMassIndex / .bodyFatPercentage 쿼리가 필요해 의도적으로 nil 유지.
            let value = WeightValue(weight: kg, bmi: nil, bodyFat: nil)
            return HealthRecord(
                dataType: Self.dataTypeWeight,
                timestamp: toMs(sample.startDate),
                endTimestamp: toMs(sample.endDate),
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: now
            )
        }
    }

    func queryBloodGlucose(since: Date, to: Date) async -> [HealthRecord] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else { return [] }
        let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci)) // mg/dL
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: qt, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
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
                measurementType: nil,
                sampleSourceType: nil,
                mealTimeMs: nil,
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
                createdAt: now
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
            sortDescriptors: [SortDescriptor(\.startDate)]
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
                createdAt: now
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
                        createdAt: now
                    )
                }
                continuation.resume(returning: records)
            }
            self.store.execute(query)
        }
    }

    func queryNutrition(since: Date, to: Date) async -> [HealthRecord] {
        // HKCorrelationType.food 는 '앱이 식사로 묶어 저장한 묶음'만 잡아 수동 입력 개별 영양소를 놓친다.
        // → 영양소별로 일자별 합산(HKStatisticsCollectionQuery)해 하루 1레코드로 반환 (집계라 mealType/title 은 nil).
        let kcal = HKUnit.kilocalorie()
        let g = HKUnit.gram()
        let mg = HKUnit.gramUnit(with: .milli)
        let mcg = HKUnit.gramUnit(with: .micro)

        async let caloriesS     = dailyNutrientSeries(.dietaryEnergyConsumed, unit: kcal, since: since, to: to)
        async let totalFatS     = dailyNutrientSeries(.dietaryFatTotal, unit: g, since: since, to: to)
        async let saturatedFatS = dailyNutrientSeries(.dietaryFatSaturated, unit: g, since: since, to: to)
        async let polyFatS      = dailyNutrientSeries(.dietaryFatPolyunsaturated, unit: g, since: since, to: to)
        async let monoFatS      = dailyNutrientSeries(.dietaryFatMonounsaturated, unit: g, since: since, to: to)
        async let carbohydrateS = dailyNutrientSeries(.dietaryCarbohydrates, unit: g, since: since, to: to)
        async let fiberS        = dailyNutrientSeries(.dietaryFiber, unit: g, since: since, to: to)
        async let sugarS        = dailyNutrientSeries(.dietarySugar, unit: g, since: since, to: to)
        async let proteinS      = dailyNutrientSeries(.dietaryProtein, unit: g, since: since, to: to)
        async let cholesterolS  = dailyNutrientSeries(.dietaryCholesterol, unit: mg, since: since, to: to)
        async let sodiumS       = dailyNutrientSeries(.dietarySodium, unit: mg, since: since, to: to)
        async let potassiumS    = dailyNutrientSeries(.dietaryPotassium, unit: mg, since: since, to: to)
        async let vitaminAS     = dailyNutrientSeries(.dietaryVitaminA, unit: mcg, since: since, to: to)
        async let vitaminCS     = dailyNutrientSeries(.dietaryVitaminC, unit: mg, since: since, to: to)
        async let calciumS      = dailyNutrientSeries(.dietaryCalcium, unit: mg, since: since, to: to)
        async let ironS         = dailyNutrientSeries(.dietaryIron, unit: mg, since: since, to: to)

        let calories = await caloriesS
        let totalFat = await totalFatS
        let saturatedFat = await saturatedFatS
        let polyFat = await polyFatS
        let monoFat = await monoFatS
        let carbohydrate = await carbohydrateS
        let fiber = await fiberS
        let sugar = await sugarS
        let protein = await proteinS
        let cholesterol = await cholesterolS
        let sodium = await sodiumS
        let potassium = await potassiumS
        let vitaminA = await vitaminAS
        let vitaminC = await vitaminCS
        let calcium = await calciumS
        let iron = await ironS

        // 데이터가 하나라도 있는 날짜의 합집합
        var dayKeys = Set<Date>()
        for m in [calories, totalFat, saturatedFat, polyFat, monoFat, carbohydrate, fiber, sugar,
                  protein, cholesterol, sodium, potassium, vitaminA, vitaminC, calcium, iron] {
            dayKeys.formUnion(m.keys)
        }

        let tz = currentTzOffset()
        let now = toMs(Date())
        let cal = Calendar.current
        return dayKeys.sorted().map { day in
            let value = NutritionValue(
                mealType: nil,
                title: nil,
                calories: calories[day],
                totalFat: totalFat[day],
                saturatedFat: saturatedFat[day],
                polysaturatedFat: polyFat[day],
                monosaturatedFat: monoFat[day],
                transFat: nil,
                carbohydrate: carbohydrate[day],
                dietaryFiber: fiber[day],
                sugar: sugar[day],
                protein: protein[day],
                cholesterol: cholesterol[day],
                sodium: sodium[day],
                potassium: potassium[day],
                vitaminA: vitaminA[day],
                vitaminC: vitaminC[day],
                calcium: calcium[day],
                iron: iron[day]
            )
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day).map { toMs($0) - 1 } ?? toMs(day)
            return HealthRecord(
                dataType: Self.dataTypeNutrition,
                timestamp: toMs(day),
                endTimestamp: dayEnd,
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: now
            )
        }
    }

    /// 영양소 한 종류를 [자정 anchored 1일 버킷]으로 합산해 (일자 시작 → 합) 맵으로 반환.
    /// standalone 샘플을 직접 합산하므로 건강앱 수동 입력도 포착. 합이 0인 날은 제외.
    private func dailyNutrientSeries(_ id: HKQuantityTypeIdentifier, unit: HKUnit, since: Date, to: Date) async -> [Date: Double] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        let anchor = Calendar.current.startOfDay(for: since)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: [])
        let interval = DateComponents(day: 1)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: qt,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, _ in
                var out: [Date: Double] = [:]
                collection?.enumerateStatistics(from: anchor, to: to) { stats, _ in
                    // stats.startDate 는 이미 자정 anchored 버킷 시작 → startOfDay 재계산 불필요(값 동일).
                    if let s = stats.sumQuantity()?.doubleValue(for: unit), s > 0 {
                        out[stats.startDate] = s
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    func queryWaterIntake(since: Date, to: Date) async -> [HealthRecord] {
        await queryQuantitySamples(.dietaryWater, unit: .literUnit(with: .milli), dataType: Self.dataTypeWaterIntake, since: since, to: to) { v in
            v > 0 ? WaterIntakeValue(amount: v) : nil
        }
    }

    func queryFloorsClimbed(since: Date, to: Date) async -> [HealthRecord] {
        await queryQuantitySamples(.flightsClimbed, unit: .count(), dataType: Self.dataTypeFloorsClimbed, since: since, to: to) { v in
            v > 0 ? FloorsClimbedValue(floor: v) : nil
        }
    }

    func queryBodyTemperature(since: Date, to: Date) async -> [HealthRecord] {
        await queryQuantitySamples(.bodyTemperature, unit: .degreeCelsius(), dataType: Self.dataTypeBodyTemperature, since: since, to: to) { v in
            v > 0 ? BodyTemperatureValue(temperature: v) : nil
        }
    }

    /// iOS 는 수면 중 손목 온도(.appleSleepingWristTemperature)로 피부 온도를 근사한다.
    func querySkinTemperature(since: Date, to: Date) async -> [HealthRecord] {
        await queryQuantitySamples(.appleSleepingWristTemperature, unit: .degreeCelsius(), dataType: Self.dataTypeSkinTemperature, since: since, to: to) { v in
            v > 0 ? SkinTemperatureValue(temperature: v, min: nil, max: nil) : nil
        }
    }

    private func fetchRouteLocations(_ route: HKWorkoutRoute) async -> [CLLocation] {
        await withCheckedContinuation { continuation in
            var all: [CLLocation] = []
            var resumed = false
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let locations = locations { all.append(contentsOf: locations) }
                if (done || error != nil) && !resumed {
                    resumed = true
                    continuation.resume(returning: all)
                }
            }
            self.store.execute(query)
        }
    }

    /// 특수: 복약 이벤트(medication, iOS 26+). 복용 상태/용량을 수집한다. 약 이름은 미포함.
    @available(iOS 26.0, *)
    func queryMedication(since: Date, to: Date) async -> [HealthRecord] {
        let type = HKObjectType.medicationDoseEventType()
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        return await withCheckedContinuation { continuation in
            var resumed = false
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { [weak self] _, samples, _ in
                guard let self = self else {
                    if !resumed { resumed = true; continuation.resume(returning: []) }
                    return
                }
                let tz = self.currentTzOffset()
                let now = self.toMs(Date())
                let records: [HealthRecord] = (samples as? [HKMedicationDoseEvent] ?? []).map { ev in
                    let value = MedicationValue(
                        logStatus: self.mapDoseLogStatus(ev.logStatus),
                        scheduleType: ev.scheduleType == .schedule ? "scheduled" : "as_needed",
                        doseQuantity: ev.doseQuantity,
                        unit: ev.unit.unitString,
                        scheduledDate: ev.scheduledDate.map { self.toMs($0) }
                    )
                    return HealthRecord(
                        dataType: Self.dataTypeMedication,
                        timestamp: self.toMs(ev.startDate),
                        endTimestamp: self.toMs(ev.endDate),
                        tzOffset: tz,
                        source: Self.source,
                        valueJson: self.encodeToJson(value),
                        createdAt: now
                    )
                }
                if !resumed { resumed = true; continuation.resume(returning: records) }
            }
            self.store.execute(query)
        }
    }

    @available(iOS 26.0, *)
    private func mapDoseLogStatus(_ s: HKMedicationDoseEvent.LogStatus) -> String {
        switch s {
        case .notInteracted: return "not_interacted"
        case .notificationNotSent: return "notification_not_sent"
        case .snoozed: return "snoozed"
        case .taken: return "taken"
        case .skipped: return "skipped"
        case .notLogged: return "not_logged"
        @unknown default: return "unknown"
        }
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

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,   // metric/daily 의 caloriesBasal
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,   // daily/hourly 의 activeTime
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.workoutType(),
        // 혈당/혈압/수분/계단/체온/피부온도
        HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
        HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
        HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
        HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
        HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
        HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)!,
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
        HKObjectType.quantityType(forIdentifier: .dietaryIron)!
        ]
        // 복약(iOS 26+)은 일반 read set 에 넣으면 크래시 → 여기서 제외하고
        // requestPermission() 에서 per-object 권한으로 따로 요청한다(없으면 queryMedication 빈 결과).
        types.insert(HKSeriesType.workoutRoute())   // 운동 세션의 GPS 경로 읽기용
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

    private func querySumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        await queryStatistics(identifier, options: .cumulativeSum, unit: unit, from: from, to: to) { $0.sumQuantity() }
    }

    private func queryAvgQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        await queryStatistics(identifier, options: .discreteAverage, unit: unit, from: from, to: to) { $0.averageQuantity() }
    }

    /// 일/시 집계 전용 버킷 합산. 단순 overlap-sum 은 경계(자정/정시)를 가로지른 누적 샘플을 전량 더해 over-count 된다.
    /// HKStatisticsCollectionQuery 가 경계 샘플을 시간비례로 나누고 multi-source 를 자동 중복 제거 → Apple 건강 UI 와 일치.
    /// bucketStart 에 맞춘 단일 버킷의 합만 반환. (임의 구간엔 부적용 → querySumQuantity 사용)
    private func querySumBucketed(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        bucketStart: Date,
        interval: DateComponents
    ) async -> Double? {
        guard let qt = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let cal = Calendar.current
        guard let bucketEnd = cal.date(byAdding: interval, to: bucketStart) else { return nil }
        // leading 크로서(버킷 시작 직전 시작) 포함하도록 predicate 를 하루 앞에서 시작. collection 은 bucketStart 버킷만 읽으므로 안전.
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

    private func queryStatistics(
        _ identifier: HKQuantityTypeIdentifier,
        options: HKStatisticsOptions,
        unit: HKUnit,
        from: Date,
        to: Date,
        valueExtractor: @escaping (HKStatistics) -> HKQuantity?
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        // .strictStartDate 는 자정 가로지른 샘플을 누락 → 기본 overlap 으로 Apple 건강 UI 와 합산 일치.
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, stats, _ in
                let value = stats.flatMap { valueExtractor($0)?.doubleValue(for: unit) }
                continuation.resume(returning: value)
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
        valueBuilder: (Double) -> T?
    ) async -> [HealthRecord] {
        guard let qt = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: to, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: qt, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let tz = currentTzOffset()
        let now = toMs(Date())
        return samples.compactMap { sample in
            let v = sample.quantity.doubleValue(for: unit)
            guard let value = valueBuilder(v) else { return nil }
            return HealthRecord(
                dataType: dataType,
                timestamp: toMs(sample.startDate),
                endTimestamp: toMs(sample.endDate),
                tzOffset: tz,
                source: Self.source,
                valueJson: encodeToJson(value),
                createdAt: now
            )
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
        let caloriesActiveInterval: Double?
        let caloriesActiveDaily: Double?
        let distanceInterval: Double?
        let distanceDaily: Double?
        let spO2: Int?
        let hrv: Double?
    }

    fileprivate struct SleepStageValue: Codable {
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

    fileprivate struct ExerciseRoutePointValue: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let accuracy: Double?
        let timestampMs: Int64
    }

    fileprivate struct ExerciseSwimmingInfo: Codable {
        let poolLength: Int?
        let poolLengthUnit: String?
        let totalDistance: Double?
        let totalDurationSec: Int?
        let locationType: String?      // "Pool" | "OpenWater"
        let strokeStyle: String?       // "Unknown"|"Mixed"|"Freestyle"|"Backstroke"|"Breaststroke"|"Butterfly"|"Kickboard"
    }

    fileprivate struct ExerciseEventValue: Codable {
        let type: String               // "pause"|"resume"|"lap"|"marker"|"segment"|"motionPaused"|"motionResumed"|"pauseOrResumeRequest"
        let startMs: Int64
        let endMs: Int64
        let metadata: String?          // JSON string (optional metadata)
    }

    fileprivate struct ExerciseActivityValue: Codable {
        let activityType: String
        let startMs: Int64
        let endMs: Int64
        let durationMin: Int?
        let calories: Double?
        let distance: Double?
        let isIndoor: Bool?
    }

    fileprivate struct ExerciseDeviceValue: Codable {
        let name: String?
        let manufacturer: String?
        let model: String?
        let hardwareVersion: String?
        let firmwareVersion: String?
        let softwareVersion: String?
        let localIdentifier: String?
        let udiDeviceIdentifier: String?
    }

    /// Swift 타입체커가 30+ 파라미터 init 을 풀지 못해 var + nil 기본값 으로 정의.
    /// 사용 패턴: `var v = ExerciseValue(exerciseType: t); v.calories = ...; v.heartRate... = ...`
    fileprivate struct ExerciseValue: Codable {
        var exerciseType: String
        var intensity: String? = nil
        var durationMin: Int? = nil
        var calories: Double? = nil
        var heartRateAvg: Int? = nil
        var heartRateMax: Int? = nil
        var heartRateMin: Int? = nil
        var distance: Double? = nil
        var altitudeGain: Double? = nil
        var altitudeLoss: Double? = nil
        var maxAltitude: Double? = nil
        var minAltitude: Double? = nil
        var count: Int? = nil
        var countType: String? = nil
        var maxSpeed: Double? = nil
        var meanSpeed: Double? = nil
        var maxCadence: Double? = nil
        var meanCadence: Double? = nil
        var maxPower: Double? = nil
        var meanPower: Double? = nil
        var route: [ExerciseRoutePointValue]? = nil
        var swimming: ExerciseSwimmingInfo? = nil
        var events: [ExerciseEventValue]? = nil
        var activities: [ExerciseActivityValue]? = nil
        var isIndoor: Bool? = nil
        var averageMets: Double? = nil
        var weatherCondition: String? = nil
        var weatherTemperature: Double? = nil
        var weatherHumidity: Double? = nil
        var device: ExerciseDeviceValue? = nil
    }

    private struct HourlySummaryValue: Codable {
        let hour: String
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsTotal: Int?
        let caloriesTotalKcal: Double?          // total = basal + active
        let caloriesActiveTotalKcal: Double?    // active 만
        let activeTimeTotalMin: Int?            // appleExerciseTime 분 합
        let distanceTotalM: Double?
    }

    fileprivate struct WeightValue: Codable {
        let weight: Double
        let bmi: Double?
        let bodyFat: Double?
    }

    fileprivate struct BloodGlucoseValue: Codable {
        let glucose: Double
        let measurementType: String?
        let sampleSourceType: String?
        let mealTimeMs: Int64?
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

    fileprivate struct NutritionValue: Codable {
        let mealType: String?
        let title: String?
        let calories: Double?
        let totalFat: Double?
        let saturatedFat: Double?
        let polysaturatedFat: Double?
        let monosaturatedFat: Double?
        let transFat: Double?
        let carbohydrate: Double?
        let dietaryFiber: Double?
        let sugar: Double?
        let protein: Double?
        let cholesterol: Double?
        let sodium: Double?
        let potassium: Double?
        let vitaminA: Double?
        let vitaminC: Double?
        let calcium: Double?
        let iron: Double?
    }

    fileprivate struct WaterIntakeValue: Codable {
        let amount: Double
    }

    fileprivate struct FloorsClimbedValue: Codable {
        let floor: Double
    }

    fileprivate struct BodyTemperatureValue: Codable {
        let temperature: Double
    }

    fileprivate struct SkinTemperatureValue: Codable {
        let temperature: Double?
        let min: Double?
        let max: Double?
    }

    fileprivate struct MedicationValue: Codable {
        let logStatus: String
        let scheduleType: String
        let doseQuantity: Double?
        let unit: String?
        let scheduledDate: Int64?
    }

    private struct DailySummaryValue: Codable {
        let date: String
        let heartRateAvg: Int?
        let heartRateMin: Int?
        let heartRateMax: Int?
        let stepsTotal: Int?
        let caloriesTotalKcal: Double?         // total = basal + active
        let caloriesActiveTotalKcal: Double?   // active 만
        let activeTimeTotalMin: Int?           // appleExerciseTime 분 합
        let distanceTotalM: Double?
        let sleepDurationMin: Int?
        let sleepDeepMin: Int?
        let sleepRemMin: Int?
        let sleepLightMin: Int?                // Apple Core 단계 포함 (Core→light 매핑)
        let sleepAwakeMin: Int?                // 수면 중 깬 시간 합
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
    static let dataTypeWeight = "weight"
    static let dataTypeBloodGlucose = "blood_glucose"
    static let dataTypeBloodPressure = "blood_pressure"
    static let dataTypeInsulinDelivery = "insulin_delivery"
    static let dataTypeNutrition = "nutrition"
    static let dataTypeWaterIntake = "water_intake"
    static let dataTypeFloorsClimbed = "floors_climbed"
    static let dataTypeBodyTemperature = "body_temperature"
    static let dataTypeSkinTemperature = "skin_temperature"
    static let dataTypeMedication = "medication"
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

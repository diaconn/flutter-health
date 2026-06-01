package com.diaconn.flutter_health

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import com.diaconn.flutter_health.models.HealthRecord
import com.samsung.android.sdk.health.data.HealthDataService
import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.data.AggregateOperation
import com.samsung.android.sdk.health.data.data.HealthDataPoint
import com.samsung.android.sdk.health.data.data.entries.ExerciseSession
import com.samsung.android.sdk.health.data.data.entries.SleepSession
import com.samsung.android.sdk.health.data.permission.AccessType
import com.samsung.android.sdk.health.data.permission.Permission
import com.samsung.android.sdk.health.data.request.AggregateRequest
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.InstantTimeFilter
import com.samsung.android.sdk.health.data.request.LocalDateFilter
import com.samsung.android.sdk.health.data.request.LocalTimeFilter
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class SamsungHealthClient(private val context: Context) {

    /** 삼성헬스가 설치되어 있고 API 29+ 인지 확인한다. */
    fun isAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return runCatching {
            context.packageManager.getPackageInfo(SAMSUNG_HEALTH_PACKAGE, 0)
            true
        }.getOrDefault(false)
    }

    /** 삼성헬스에 연결한다. 이미 연결된 경우 즉시 true 반환. */
    suspend fun connect(): Boolean {
        if (store != null) return true
        return runCatching {
            val newStore = HealthDataService.getStore(context)
            newStore.getGrantedPermissions(REQUIRED_PERMISSIONS)
            store = newStore
            true
        }.onFailure { Log.w(TAG, "삼성헬스 연결 실패", it) }.getOrDefault(false)
    }

    /** 연결을 해제한다. */
    fun disconnect() {
        store = null
    }

    /** 권한이 하나 이상 부여되어 있는지 확인한다. 부분 허용도 true 반환. */
    suspend fun isPermissionGranted(): Boolean {
        val s = store ?: return false
        return runCatching {
            s.getGrantedPermissions(REQUIRED_PERMISSIONS).isNotEmpty()
        }.onFailure { Log.w(TAG, "권한 확인 실패", it) }.getOrDefault(false)
    }

    /** 삼성헬스 권한 UI를 표시한다. 하나 이상 허용 시 true 반환. */
    suspend fun requestPermission(activity: Activity): Boolean {
        val s = store ?: return false
        return runCatching {
            s.requestPermissions(REQUIRED_PERMISSIONS, activity).isNotEmpty()
        }.onFailure { Log.w(TAG, "권한 요청 실패", it) }.getOrDefault(false)
    }

    /**
     * [from]~[to] 구간의 건강 지표를 집계하여 "metric" HealthRecord를 반환한다.
     * 모든 데이터가 없으면 null 반환.
     */
    suspend fun queryMetric(from: Long, to: Long): HealthRecord? = coroutineScope {
        val s = store ?: return@coroutineScope null
        val zone = ZoneId.systemDefault()
        val localFilter = LocalTimeFilter.of(from.toLocalDateTime(), to.toLocalDateTime())
        val instantFilter = InstantTimeFilter.of(Instant.ofEpochMilli(from), Instant.ofEpochMilli(to))
        val dayStartMs = LocalDate.now(zone).atStartOfDay(zone).toInstant().toEpochMilli()
        val dayFilter = LocalTimeFilter.of(dayStartMs.toLocalDateTime(), to.toLocalDateTime())

        val hrD = async { readHeartRateStats(s, instantFilter) }
        val siD = async { aggregateSteps(s, localFilter) }
        val sdD = async { aggregateSteps(s, dayFilter) }
        val ciD = async { aggregateCalories(s, localFilter) }
        val cdD = async { aggregateCalories(s, dayFilter) }
        val caiD = async { aggregateActiveCalories(s, localFilter) }
        val cadD = async { aggregateActiveCalories(s, dayFilter) }
        val diD = async { aggregateDistance(s, localFilter) }
        val ddD = async { aggregateDistance(s, dayFilter) }
        val spD = async { readSpO2Avg(s, instantFilter) }

        val hrStats = hrD.await()
        val stepsInterval = siD.await()
        val stepsDaily = sdD.await()
        val caloriesInterval = ciD.await()
        val caloriesDaily = cdD.await()
        val caloriesActiveInterval = caiD.await()
        val caloriesActiveDaily = cadD.await()
        val distanceInterval = diD.await()
        val distanceDaily = ddD.await()
        val spO2 = spD.await()

        if (hrStats.avg == null && stepsInterval == null && caloriesInterval == null && distanceInterval == null && spO2 == null) {
            return@coroutineScope null
        }

        HealthRecord(
            dataType = DATA_TYPE_METRIC,
            timestamp = from,
            endTimestamp = to,
            tzOffset = currentTzOffset(),
            source = SOURCE,
            valueJson = json.encodeToString(MetricValue(
                heartRateAvg = hrStats.avg,
                heartRateMin = hrStats.min,
                heartRateMax = hrStats.max,
                stepsInterval = stepsInterval,
                stepsDaily = stepsDaily,
                caloriesInterval = caloriesInterval,
                caloriesDaily = caloriesDaily,
                caloriesActiveInterval = caloriesActiveInterval,
                caloriesActiveDaily = caloriesActiveDaily,
                distanceInterval = distanceInterval,
                distanceDaily = distanceDaily,
                spO2 = spO2,
                hrv = null
            )),
            createdAt = System.currentTimeMillis(),
        )
    }

    /** [since]~[to] 구간에 종료된 수면 세션 목록을 반환한다. */
    suspend fun queryEndedSleepSessions(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            // 수면은 보통 자정을 걸쳐서 일어나므로(예: 23:00 ~ 07:00) 시작 시각을 하루 앞당겨 넉넉히 가져온 뒤,
            // 종료 시각이 원래 요청 범위(since~to) 안인 것만 남긴다.
            val sinceLocal = since.toLocalDateTime().minusDays(1)
            val toLocal = to.toLocalDateTime()
            val filter = LocalTimeFilter.of(sinceLocal, toLocal)
            val request = DataTypes.SLEEP.readDataRequestBuilder.setLocalTimeFilter(filter).build()
            s.readData(request).dataList
                .mapNotNull { buildSleepRecord(it) }
                .filter { it.endTimestamp in since..to }
        }.onFailure { Log.e(TAG, "수면 세션 조회 실패", it) }.getOrDefault(emptyList())
    }

    /** [since]~[to] 구간에 종료된 운동 세션 목록을 반환한다. */
    suspend fun queryEndedExerciseSessions(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            val sinceLocal = since.toLocalDateTime()
            val toLocal = to.toLocalDateTime()
            val filter = LocalTimeFilter.of(sinceLocal, toLocal)
            val request = DataTypes.EXERCISE.readDataRequestBuilder.setLocalTimeFilter(filter).build()
            s.readData(request).dataList
                .mapNotNull { buildExerciseRecord(it) }
                .filter { it.endTimestamp in since..to }
        }.onFailure { Log.e(TAG, "운동 세션 조회 실패", it) }.getOrDefault(emptyList())
    }

    /**
     * [hourStartMs]~[hourEndMs] 구간의 시간별 집계를 반환한다.
     * 데이터가 없으면 null 반환.
     */
    suspend fun queryHourlySummary(hourStartMs: Long, hourEndMs: Long): HealthRecord? = coroutineScope {
        val s = store ?: return@coroutineScope null
        val zone = ZoneId.systemDefault()
        val localFilter = LocalTimeFilter.of(hourStartMs.toLocalDateTime(), hourEndMs.toLocalDateTime())
        val instantFilter = InstantTimeFilter.of(Instant.ofEpochMilli(hourStartMs), Instant.ofEpochMilli(hourEndMs))

        val hrD = async { readHeartRateStats(s, instantFilter) }
        val stD = async { aggregateSteps(s, localFilter) }
        val caD = async { aggregateCalories(s, localFilter) }
        val caaD = async { aggregateActiveCalories(s, localFilter) }
        val atD = async { aggregateActiveTime(s, localFilter) }
        val diD = async { aggregateDistance(s, localFilter) }

        val hrStats = hrD.await()
        val stepsTotal = stD.await()
        val caloriesTotalKcal = caD.await()
        val caloriesActiveTotalKcal = caaD.await()
        val activeTimeTotalMin = atD.await()
        val distanceTotalM = diD.await()

        if (hrStats.avg == null && stepsTotal == null && caloriesTotalKcal == null &&
            caloriesActiveTotalKcal == null && activeTimeTotalMin == null && distanceTotalM == null) {
            return@coroutineScope null
        }

        val hourLabel = Instant.ofEpochMilli(hourStartMs)
            .atZone(zone)
            .format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH"))

        HealthRecord(
            dataType = DATA_TYPE_HOURLY_SUMMARY,
            timestamp = hourStartMs,
            endTimestamp = hourEndMs,
            tzOffset = currentTzOffset(),
            source = SOURCE,
            valueJson = json.encodeToString(HourlySummaryValue(
                hour = hourLabel,
                heartRateAvg = hrStats.avg,
                heartRateMin = hrStats.min,
                heartRateMax = hrStats.max,
                stepsTotal = stepsTotal,
                caloriesTotalKcal = caloriesTotalKcal,
                caloriesActiveTotalKcal = caloriesActiveTotalKcal,
                activeTimeTotalMin = activeTimeTotalMin,
                distanceTotalM = distanceTotalM
            )),
            createdAt = System.currentTimeMillis(),
        )
    }

    /**
     * [date] 하루 전체의 일별 집계를 반환한다.
     * 데이터가 없으면 null 반환.
     */
    suspend fun queryDailySummary(date: LocalDate): HealthRecord? = coroutineScope {
        val s = store ?: return@coroutineScope null
        val zone = ZoneId.systemDefault()
        val dayStartMs = date.atStartOfDay(zone).toInstant().toEpochMilli()
        val dayEndMs = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() - 1
        val localFilter = LocalTimeFilter.of(dayStartMs.toLocalDateTime(), dayEndMs.toLocalDateTime())
        val instantFilter = InstantTimeFilter.of(Instant.ofEpochMilli(dayStartMs), Instant.ofEpochMilli(dayEndMs))

        val hrD = async { readHeartRateStats(s, instantFilter) }
        val stD = async { aggregateSteps(s, localFilter) }
        val caD = async { aggregateCalories(s, localFilter) }
        val caaD = async { aggregateActiveCalories(s, localFilter) }
        val atD = async { aggregateActiveTime(s, localFilter) }
        val diD = async { aggregateDistance(s, localFilter) }
        val sleepD = async { queryEndedSleepSessions(dayStartMs, dayEndMs) }
        val exerciseD = async { queryEndedExerciseSessions(dayStartMs, dayEndMs) }

        val hrStats = hrD.await()
        val stepsTotal = stD.await()
        val caloriesTotalKcal = caD.await()
        val caloriesActiveTotalKcal = caaD.await()
        val activeTimeTotalMin = atD.await()
        val distanceTotalM = diD.await()
        val sleepSessions = sleepD.await()
        val exerciseSessions = exerciseD.await()

        val mainSleep = sleepSessions.maxByOrNull { it.endTimestamp - it.timestamp }
        val sleepDurationMin = mainSleep?.let { (it.endTimestamp - it.timestamp) / 60000 }?.toInt()
        val sleepValue = mainSleep?.let { runCatching { json.decodeFromString<SleepValue>(it.valueJson) }.getOrNull() }

        val exerciseCount = exerciseSessions.size.takeIf { it > 0 }
        val exerciseTotalMin = exerciseSessions.sumOf { (it.endTimestamp - it.timestamp) / 60000 }.toInt().takeIf { it > 0 }
        val exerciseTotalCalories = exerciseSessions.mapNotNull {
            runCatching { json.decodeFromString<ExerciseValue>(it.valueJson).calories }.getOrNull()
        }.reduceOrNull { acc, d -> acc + d }

        if (hrStats.avg == null && stepsTotal == null && sleepDurationMin == null && exerciseCount == null) {
            return@coroutineScope null
        }

        HealthRecord(
            dataType = DATA_TYPE_DAILY_SUMMARY,
            timestamp = dayStartMs,
            endTimestamp = dayEndMs,
            tzOffset = currentTzOffset(),
            source = SOURCE,
            valueJson = json.encodeToString(DailySummaryValue(
                date = date.format(DateTimeFormatter.ISO_LOCAL_DATE),
                heartRateAvg = hrStats.avg,
                heartRateMin = hrStats.min,
                heartRateMax = hrStats.max,
                stepsTotal = stepsTotal,
                caloriesTotalKcal = caloriesTotalKcal,
                caloriesActiveTotalKcal = caloriesActiveTotalKcal,
                activeTimeTotalMin = activeTimeTotalMin,
                distanceTotalM = distanceTotalM,
                sleepDurationMin = sleepDurationMin,
                sleepDeepMin = sleepValue?.deepMin,
                sleepRemMin = sleepValue?.remMin,
                sleepLightMin = sleepValue?.lightMin,
                sleepAwakeMin = sleepValue?.awakeMin,
                exerciseCount = exerciseCount,
                exerciseTotalMin = exerciseTotalMin,
                exerciseTotalCalories = exerciseTotalCalories
            )),
            createdAt = System.currentTimeMillis(),
        )
    }

    /**
     * [since]~[to] 구간 내 모든 체중(BODY_COMPOSITION) 레코드를 시간순으로 반환한다.
     * weight가 0인 샘플은 제외. 실패 시 빈 리스트 반환.
     */
    suspend fun queryWeights(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            val filter = InstantTimeFilter.of(Instant.ofEpochMilli(since), Instant.ofEpochMilli(to))
            val request = DataTypes.BODY_COMPOSITION.readDataRequestBuilder
                .setInstantTimeFilter(filter).build()
            val tz = currentTzOffset()
            val now = System.currentTimeMillis()
            s.readData(request).dataList
                .sortedBy { it.startTime?.toEpochMilli() ?: 0L }
                .mapNotNull { point ->
                    val weight = point.getValueOrDefault(DataType.BodyCompositionType.WEIGHT, 0f)
                    if (weight <= 0f) return@mapNotNull null

                    fun bcf(field: com.samsung.android.sdk.health.data.data.Field<Float>): Double? =
                        point.getValueOrDefault(field, 0f).let { if (it > 0f) it.toDouble() else null }

                    val height = bcf(DataType.BodyCompositionType.HEIGHT)
                    val bmi = bcf(DataType.BodyCompositionType.BODY_MASS_INDEX)
                    val bodyFat = bcf(DataType.BodyCompositionType.BODY_FAT)
                    val bodyFatMass = bcf(DataType.BodyCompositionType.BODY_FAT_MASS)
                    val fatFree = bcf(DataType.BodyCompositionType.FAT_FREE)
                    val fatFreeMass = bcf(DataType.BodyCompositionType.FAT_FREE_MASS)
                    val skeletalMuscle = bcf(DataType.BodyCompositionType.SKELETAL_MUSCLE)
                    val skeletalMuscleMass = bcf(DataType.BodyCompositionType.SKELETAL_MUSCLE_MASS)
                    val muscleMass = bcf(DataType.BodyCompositionType.MUSCLE_MASS)
                    val totalBodyWater = bcf(DataType.BodyCompositionType.TOTAL_BODY_WATER)
                    val basalMetabolicRate = point
                        .getValueOrDefault(DataType.BodyCompositionType.BASAL_METABOLIC_RATE, 0)
                        .takeIf { it > 0 }

                    val startMs = point.startTime?.toEpochMilli() ?: since
                    val endMs = point.endTime?.toEpochMilli() ?: startMs

                    HealthRecord(
                        dataType = DATA_TYPE_WEIGHT,
                        timestamp = startMs,
                        endTimestamp = endMs,
                        tzOffset = tz,
                        source = SOURCE,
                        valueJson = json.encodeToString(WeightValue(
                            weight = weight.toDouble(),
                            height = height,
                            bmi = bmi,
                            bodyFat = bodyFat,
                            bodyFatMass = bodyFatMass,
                            fatFree = fatFree,
                            fatFreeMass = fatFreeMass,
                            skeletalMuscle = skeletalMuscle,
                            skeletalMuscleMass = skeletalMuscleMass,
                            muscleMass = muscleMass,
                            totalBodyWater = totalBodyWater,
                            basalMetabolicRate = basalMetabolicRate
                        )),
                        createdAt = now,
                    )
                }
        }.onFailure { Log.e(TAG, "체중 조회 실패", it) }.getOrDefault(emptyList())
    }

    /** [since]~[to] 구간 내 모든 혈당 측정 목록. */
    suspend fun queryBloodGlucose(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.BLOOD_GLUCOSE, "혈당") { point, startMs, endMs, tz, now ->
            val glucose = runCatching { point.getValue(DataType.BloodGlucoseType.GLUCOSE_LEVEL) }.getOrNull()
                ?: point.getValueOrDefault(DataType.BloodGlucoseType.GLUCOSE_LEVEL, 0f)
            if (glucose <= 0f) return@readPoints null
            val measurementType = runCatching { point.getValue(DataType.BloodGlucoseType.MEASUREMENT_TYPE) }
                .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase()
            val sampleSourceType = runCatching { point.getValue(DataType.BloodGlucoseType.SAMPLE_SOURCE_TYPE) }
                .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase()
            val mealTime = runCatching { point.getValue(DataType.BloodGlucoseType.MEAL_TIME) }
                .getOrNull()?.toEpochMilli()?.takeIf { it > 0L }
            val mealStatus = runCatching { point.getValue(DataType.BloodGlucoseType.MEAL_STATUS) }
                .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase()
            val insulin = runCatching { point.getValue(DataType.BloodGlucoseType.INSULIN_INJECTED) }
                .getOrNull()?.let { if (it > 0f) it.toDouble() else null }
            val medication = runCatching { point.getValue(DataType.BloodGlucoseType.MEDICATION_TAKEN) }
                .getOrNull()
            val series = runCatching { point.getValue(DataType.BloodGlucoseType.SERIES_DATA) }
                .getOrNull()?.takeIf { it.isNotEmpty() }?.map {
                    BloodGlucoseSeriesEntry(
                        glucose = it.glucose.toDouble(),
                        timestampMs = it.timestamp.toEpochMilli()
                    )
                }

            HealthRecord(
                dataType = DATA_TYPE_BLOOD_GLUCOSE,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(BloodGlucoseValue(
                    glucose = glucose.toDouble(),
                    measurementType = measurementType,
                    sampleSourceType = sampleSourceType,
                    mealTimeMs = mealTime,
                    mealStatus = mealStatus,
                    insulinInjected = insulin,
                    medicationTaken = medication,
                    series = series
                )),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간 내 모든 혈압 측정 목록. */
    suspend fun queryBloodPressure(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.BLOOD_PRESSURE, "혈압") { point, startMs, endMs, tz, now ->
            val systolic = runCatching { point.getValue(DataType.BloodPressureType.SYSTOLIC) }.getOrNull()
            val diastolic = runCatching { point.getValue(DataType.BloodPressureType.DIASTOLIC) }.getOrNull()
            if (systolic == null || diastolic == null || systolic <= 0f || diastolic <= 0f) return@readPoints null
            val mean = runCatching { point.getValue(DataType.BloodPressureType.MEAN) }.getOrNull()
                ?.let { if (it > 0f) it.toDouble() else null }
            val pulseRate = runCatching { point.getValue(DataType.BloodPressureType.PULSE_RATE) }.getOrNull()
                ?.takeIf { it > 0 }
            val medication = runCatching { point.getValue(DataType.BloodPressureType.MEDICATION_TAKEN) }.getOrNull()

            HealthRecord(
                dataType = DATA_TYPE_BLOOD_PRESSURE,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(BloodPressureValue(
                    systolic = systolic.toDouble(),
                    diastolic = diastolic.toDouble(),
                    mean = mean,
                    pulseRate = pulseRate,
                    medicationTaken = medication
                )),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간 내 모든 영양 기록. */
    suspend fun queryNutrition(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.NUTRITION, "영양") { point, startMs, endMs, tz, now ->
            val mealType = runCatching { point.getValue(DataType.NutritionType.MEAL_TYPE) }
                .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase()
            val title = runCatching { point.getValue(DataType.NutritionType.TITLE) }.getOrNull()
            val calories = nf(point, DataType.NutritionType.CALORIES)
            val totalFat = nf(point, DataType.NutritionType.TOTAL_FAT)
            val saturatedFat = nf(point, DataType.NutritionType.SATURATED_FAT)
            val polysaturatedFat = nf(point, DataType.NutritionType.POLYSATURATED_FAT)
            val monosaturatedFat = nf(point, DataType.NutritionType.MONOSATURATED_FAT)
            val transFat = nf(point, DataType.NutritionType.TRANS_FAT)
            val carbohydrate = nf(point, DataType.NutritionType.CARBOHYDRATE)
            val dietaryFiber = nf(point, DataType.NutritionType.DIETARY_FIBER)
            val sugar = nf(point, DataType.NutritionType.SUGAR)
            val protein = nf(point, DataType.NutritionType.PROTEIN)
            val cholesterol = nf(point, DataType.NutritionType.CHOLESTEROL)
            val sodium = nf(point, DataType.NutritionType.SODIUM)
            val potassium = nf(point, DataType.NutritionType.POTASSIUM)
            val vitaminA = nf(point, DataType.NutritionType.VITAMIN_A)
            val vitaminC = nf(point, DataType.NutritionType.VITAMIN_C)
            val calcium = nf(point, DataType.NutritionType.CALCIUM)
            val iron = nf(point, DataType.NutritionType.IRON)

            // 19개 영양 필드 중 하나라도 있으면 valid 처리 (비타민 단독 입력 등 케이스 보존).
            val anyField = listOf(
                mealType, title, calories, totalFat, saturatedFat, polysaturatedFat, monosaturatedFat,
                transFat, carbohydrate, dietaryFiber, sugar, protein, cholesterol, sodium, potassium,
                vitaminA, vitaminC, calcium, iron
            ).any { it != null }
            if (!anyField) return@readPoints null

            HealthRecord(
                dataType = DATA_TYPE_NUTRITION,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(NutritionValue(
                    mealType = mealType, title = title, calories = calories,
                    totalFat = totalFat, saturatedFat = saturatedFat,
                    polysaturatedFat = polysaturatedFat, monosaturatedFat = monosaturatedFat,
                    transFat = transFat, carbohydrate = carbohydrate, dietaryFiber = dietaryFiber,
                    sugar = sugar, protein = protein, cholesterol = cholesterol,
                    sodium = sodium, potassium = potassium,
                    vitaminA = vitaminA, vitaminC = vitaminC, calcium = calcium, iron = iron
                )),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간 내 모든 수분 섭취 기록. */
    suspend fun queryWaterIntake(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.WATER_INTAKE, "수분 섭취") { point, startMs, endMs, tz, now ->
            val amount = runCatching { point.getValue(DataType.WaterIntakeType.AMOUNT) }.getOrNull()
            if (amount == null || amount <= 0f) return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_WATER_INTAKE,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(WaterIntakeValue(amount = amount.toDouble())),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간 내 모든 수면 무호흡 기록. */
    suspend fun querySleepApnea(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.SLEEP_APNEA, "수면 무호흡") { point, startMs, endMs, tz, now ->
            val sign = runCatching { point.getValue(DataType.SleepApneaType.DETECTED_SIGN) }
                .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase() ?: return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_SLEEP_APNEA,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(SleepApneaValue(detectedSign = sign)),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간 내 모든 계단 기록. */
    suspend fun queryFloorsClimbed(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.FLOORS_CLIMBED, "계단") { point, startMs, endMs, tz, now ->
            val floor = runCatching { point.getValue(DataType.FloorsClimbedType.FLOOR) }.getOrNull()
            if (floor == null || floor <= 0f) return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_FLOORS_CLIMBED,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(FloorsClimbedValue(floor = floor.toDouble())),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간의 일별 에너지 점수 목록. ENERGY_SCORE 만 LocalDateBuilder 사용. */
    suspend fun queryEnergyScore(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            val zone = ZoneId.systemDefault()
            val startDate = Instant.ofEpochMilli(since).atZone(zone).toLocalDate()
            val endDate = Instant.ofEpochMilli(to).atZone(zone).toLocalDate()
            // 양쪽 inclusive 명시 — 2-arg 오버로드는 기본값이 불확실해 다음날 데이터까지 새는 위험 있음.
            val filter = LocalDateFilter.of(startDate, endDate, true, true)
            val request = DataTypes.ENERGY_SCORE.readDataRequestBuilder
                .setLocalDateFilter(filter).build()
            val tz = currentTzOffset()
            val now = System.currentTimeMillis()
            s.readData(request).dataList
                .sortedBy { it.startTime?.toEpochMilli() ?: 0L }
                .mapNotNull { point ->
                    val score = runCatching { point.getValue(DataType.EnergyScoreType.ENERGY_SCORE) }.getOrNull()
                    if (score == null || score <= 0f) return@mapNotNull null
                    val startMs = point.startTime?.toEpochMilli() ?: since
                    val endMs = point.endTime?.toEpochMilli() ?: startMs
                    HealthRecord(
                        dataType = DATA_TYPE_ENERGY_SCORE,
                        timestamp = startMs,
                        endTimestamp = endMs,
                        tzOffset = tz,
                        source = SOURCE,
                        valueJson = json.encodeToString(EnergyScoreValue(score = score.toDouble())),
                        createdAt = now,
                    )
                }
        }.onFailure { Log.e(TAG, "에너지 점수 조회 실패", it) }.getOrDefault(emptyList())
    }

    /** [since]~[to] 구간 내 모든 체온 측정 목록. */
    suspend fun queryBodyTemperature(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.BODY_TEMPERATURE, "체온") { point, startMs, endMs, tz, now ->
            val temp = runCatching { point.getValue(DataType.BodyTemperatureType.BODY_TEMPERATURE) }.getOrNull()
            if (temp == null || temp <= 0f) return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_BODY_TEMPERATURE,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(BodyTemperatureValue(temperature = temp.toDouble())),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간 내 모든 피부 온도 측정 목록. */
    suspend fun querySkinTemperature(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.SKIN_TEMPERATURE, "피부 온도") { point, startMs, endMs, tz, now ->
            // 피부 온도는 영하도 valid. -1000 sentinel 만 거름.
            val avg = runCatching { point.getValue(DataType.SkinTemperatureType.SKIN_TEMPERATURE) }.getOrNull()
                ?.toDouble()?.takeIf { it > -999.0 }
            val min = runCatching { point.getValue(DataType.SkinTemperatureType.MIN_SKIN_TEMPERATURE) }.getOrNull()
                ?.toDouble()?.takeIf { it > -999.0 }
            val max = runCatching { point.getValue(DataType.SkinTemperatureType.MAX_SKIN_TEMPERATURE) }.getOrNull()
                ?.toDouble()?.takeIf { it > -999.0 }
            // 피부 온도는 영하도 valid (콜드 환경). -1000 sentinel 만 거름.
            val series = runCatching { point.getValue(DataType.SkinTemperatureType.SERIES_DATA) }
                .getOrNull()?.takeIf { it.isNotEmpty() }?.map {
                    SkinTemperatureSeriesEntry(
                        temperature = it.skinTemperature.toDouble(),
                        min = it.min.toDouble().takeIf { v -> v > -999.0 },
                        max = it.max.toDouble().takeIf { v -> v > -999.0 },
                        startMs = it.startTime.toEpochMilli(),
                        endMs = it.endTime.toEpochMilli()
                    )
                }
            if (avg == null && min == null && max == null && series == null) return@readPoints null

            HealthRecord(
                dataType = DATA_TYPE_SKIN_TEMPERATURE,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(SkinTemperatureValue(
                    temperature = avg, min = min, max = max, series = series
                )),
                createdAt = now,
            )
        }

    /** [since]~[to] 구간 내 부정맥 알림 기록. */
    suspend fun queryIrregularHeartRhythm(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.IRREGULAR_HEART_RHYTHM_NOTIFICATION, "부정맥") { point, startMs, endMs, tz, now ->
            val status = runCatching { point.getValue(DataType.IrregularHeartRhythmNotificationType.STATUS) }
                .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase() ?: return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_HEART_RHYTHM,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(HeartRhythmValue(status = status)),
                createdAt = now,
            )
        }

    // --- Private ---

    @Volatile private var store: HealthDataStore? = null
    // iOS JSONEncoder 가 nil 을 키째로 omit 하는 동작과 통일 (Apple HealthKit/Google Fit/FHIR 권고 동일).
    // 기본 kotlinx.serialization 은 explicitNulls=true 라 `"key": null` 을 명시 출력 → false 로 끔.
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    private fun currentTzOffset(): String =
        OffsetDateTime.now(ZoneId.systemDefault()).offset.toString()

    private fun Long.toLocalDateTime(): LocalDateTime =
        Instant.ofEpochMilli(this).atZone(ZoneId.systemDefault()).toLocalDateTime()

    private data class HrStats(val avg: Int?, val min: Int?, val max: Int?)

    private suspend fun readHeartRateStats(s: HealthDataStore, filter: InstantTimeFilter): HrStats =
        runCatching {
            val request = DataTypes.HEART_RATE.readDataRequestBuilder.setInstantTimeFilter(filter).build()
            val values = s.readData(request).dataList
                .map { it.getValueOrDefault(DataType.HeartRateType.HEART_RATE, 0f) }
                .filter { it > 0f }
            if (values.isEmpty()) HrStats(null, null, null)
            else HrStats(
                avg = (values.sum() / values.size).toInt().takeIf { it > 0 },
                min = values.min().toInt().takeIf { it > 0 },
                max = values.max().toInt().takeIf { it > 0 }
            )
        }.onFailure { Log.e(TAG, "심박수 조회 실패", it) }.getOrDefault(HrStats(null, null, null))

    private suspend fun readSpO2Avg(s: HealthDataStore, filter: InstantTimeFilter): Int? =
        runCatching {
            val request = DataTypes.BLOOD_OXYGEN.readDataRequestBuilder.setInstantTimeFilter(filter).build()
            val values = s.readData(request).dataList
                .map { it.getValueOrDefault(DataType.BloodOxygenType.OXYGEN_SATURATION, 0f) }
                .filter { it > 0f }
            if (values.isEmpty()) null
            else (values.sum() / values.size).toInt().takeIf { it > 0 }
        }.onFailure { Log.e(TAG, "SpO2 조회 실패", it) }.getOrDefault(null)

    private suspend fun aggregateSteps(s: HealthDataStore, filter: LocalTimeFilter): Int? =
        runCatching {
            val request = DataType.StepsType.TOTAL.requestBuilder.setLocalTimeFilter(filter).build()
            s.aggregateData(request).dataList.firstOrNull()?.value?.toInt()?.takeIf { it > 0 }
        }.onFailure { Log.e(TAG, "걸음수 집계 실패", it) }.getOrDefault(null)

    private suspend fun aggregateActivityFloat(
        s: HealthDataStore,
        op: AggregateOperation<Float, AggregateRequest.LocalTimeBuilder<Float>>,
        filter: LocalTimeFilter,
        logTag: String
    ): Double? =
        runCatching {
            s.aggregateData(op.requestBuilder.setLocalTimeFilter(filter).build())
                .dataList.firstOrNull()?.value?.let { v -> if (v > 0f) v.toDouble() else null }
        }.onFailure { Log.e(TAG, "$logTag 집계 실패", it) }.getOrDefault(null)

    private suspend fun aggregateCalories(s: HealthDataStore, filter: LocalTimeFilter): Double? =
        aggregateActivityFloat(s, DataType.ActivitySummaryType.TOTAL_CALORIES_BURNED, filter, "칼로리")

    private suspend fun aggregateDistance(s: HealthDataStore, filter: LocalTimeFilter): Double? =
        aggregateActivityFloat(s, DataType.ActivitySummaryType.TOTAL_DISTANCE, filter, "이동 거리")

    private suspend fun aggregateActiveCalories(s: HealthDataStore, filter: LocalTimeFilter): Double? =
        aggregateActivityFloat(s, DataType.ActivitySummaryType.TOTAL_ACTIVE_CALORIES_BURNED, filter, "활동 칼로리")

    private suspend fun aggregateActiveTime(s: HealthDataStore, filter: LocalTimeFilter): Int? =
        runCatching {
            s.aggregateData(DataType.ActivitySummaryType.TOTAL_ACTIVE_TIME.requestBuilder.setLocalTimeFilter(filter).build())
                .dataList.firstOrNull()?.value?.toMillis()?.div(60000L)?.toInt()?.takeIf { it > 0 }
        }.onFailure { Log.e(TAG, "활동 시간 집계 실패", it) }.getOrDefault(null)

    /** Nutrition 의 Float Field 추출 헬퍼 — 19개 필드에 반복되어 헬퍼가 정당. */
    private fun nf(point: HealthDataPoint, field: com.samsung.android.sdk.health.data.data.Field<Float>): Double? =
        runCatching { point.getValue(field) }.getOrNull()?.let { if (it > 0f) it.toDouble() else null }

    /** 신규 11종 query 함수의 공통 패턴: InstantTimeFilter 로 readData → buildBlock 으로 변환. */
    private suspend fun <T : com.samsung.android.sdk.health.data.data.DataPoint> readPoints(
        since: Long,
        to: Long,
        dataType: com.samsung.android.sdk.health.data.request.DataType.Readable<T, *>,
        logTag: String,
        buildBlock: (point: HealthDataPoint, startMs: Long, endMs: Long, tz: String, now: Long) -> HealthRecord?
    ): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            val filter = InstantTimeFilter.of(Instant.ofEpochMilli(since), Instant.ofEpochMilli(to))
            @Suppress("UNCHECKED_CAST")
            val builder = dataType.readDataRequestBuilder as
                com.samsung.android.sdk.health.data.request.ReadDataRequest.DualTimeBuilder<HealthDataPoint>
            val request = builder.setInstantTimeFilter(filter).build()
            val tz = currentTzOffset()
            val now = System.currentTimeMillis()
            s.readData(request).dataList
                .sortedBy { it.startTime?.toEpochMilli() ?: 0L }
                .mapNotNull { point ->
                    val startMs = point.startTime?.toEpochMilli() ?: since
                    val endMs = point.endTime?.toEpochMilli() ?: startMs
                    buildBlock(point, startMs, endMs, tz, now)
                }
        }.onFailure { Log.e(TAG, "$logTag 조회 실패", it) }.getOrDefault(emptyList())
    }

    private fun buildSleepRecord(point: HealthDataPoint): HealthRecord? {
        val startMs = point.startTime?.toEpochMilli() ?: return null
        val endMs = point.endTime?.toEpochMilli() ?: return null

        val sessions: List<SleepSession> =
            runCatching { point.getValue(DataType.SleepType.SESSIONS) }.getOrNull() ?: emptyList()
        val allStages: List<SleepSession.SleepStage> = sessions.flatMap { it.stages ?: emptyList() }

        val durationMs = runCatching {
            point.getValue(DataType.SleepType.DURATION)?.toMillis()
        }.getOrNull() ?: (endMs - startMs)

        fun stageDurationMin(type: DataType.SleepType.StageType): Int? =
            allStages.filter { it.stage == type }
                .sumOf { (it.endTime?.toEpochMilli() ?: 0L) - (it.startTime?.toEpochMilli() ?: 0L) }
                .div(60000L).toInt().takeIf { it > 0 }

        val stageValues = allStages.mapNotNull { stage ->
            val sStart = stage.startTime?.toEpochMilli() ?: return@mapNotNull null
            val sEnd = stage.endTime?.toEpochMilli() ?: return@mapNotNull null
            SleepStageValue(stage = mapSleepStage(stage.stage), startMs = sStart, endMs = sEnd)
        }

        return HealthRecord(
            dataType = DATA_TYPE_SLEEP,
            timestamp = startMs,
            endTimestamp = endMs,
            tzOffset = currentTzOffset(),
            source = SOURCE,
            valueJson = json.encodeToString(SleepValue(
                durationMin = (durationMs / 60000L).toInt().takeIf { it > 0 },
                awakeMin = stageDurationMin(DataType.SleepType.StageType.AWAKE),
                lightMin = stageDurationMin(DataType.SleepType.StageType.LIGHT),
                deepMin = stageDurationMin(DataType.SleepType.StageType.DEEP),
                remMin = stageDurationMin(DataType.SleepType.StageType.REM),
                stages = stageValues.takeIf { it.isNotEmpty() }
            )),
            createdAt = System.currentTimeMillis(),
        )
    }

    private fun buildExerciseRecord(point: HealthDataPoint): HealthRecord? {
        val startMs = point.startTime?.toEpochMilli() ?: return null
        val endMs = point.endTime?.toEpochMilli() ?: return null

        val sessions: List<ExerciseSession> =
            runCatching { point.getValue(DataType.ExerciseType.SESSIONS) }.getOrNull() ?: emptyList()
        val session = sessions.firstOrNull()

        val exerciseType = runCatching {
            session?.exerciseType ?: DataType.ExerciseType.PredefinedExerciseType.OTHER
        }.getOrDefault(DataType.ExerciseType.PredefinedExerciseType.OTHER)

        val durationMs = session?.duration?.toMillis() ?: (endMs - startMs)
        val heartRateAvg = session?.meanHeartRate?.let { if (it > 0f) it.toInt() else null }

        Log.d(
            TAG,
            "[운동매핑확인] 원본=${exerciseType.name}(ordinal=${exerciseType.ordinal})" +
                " → 앱값=${mapExerciseType(exerciseType)}" +
                " | 시작=${point.startTime} 종료=${point.endTime}" +
                " 지속=${durationMs / 60000}분 칼로리=${session?.calories} 거리=${session?.distance}m"
        )

        // Samsung 은 "측정 안 됨" 을 -1000 sentinel 또는 0 으로 표현한다.
        // altitude 는 음수 정상값 가능(해수면 아래)하므로 -999 초과만 valid 로 본다.
        // 다른 누적/속도/cadence/power 값은 0 이하면 측정 실패로 간주한다.
        fun Float.altitudeOrNull(): Double? = toDouble().takeIf { it > -999.0 }
        fun Float.posOrNull(): Double? = toDouble().takeIf { it > 0.0 }

        // (0,0) 은 GPS lock 전의 sentinel 좌표라 drop. 실제 적도/그리니치 교점 데이터는 의료 운동 데이터로 발생 안 함.
        val route = session?.route
            ?.filterNot { it.latitude == 0.0f && it.longitude == 0.0f }
            ?.takeIf { it.isNotEmpty() }?.map { loc ->
                ExerciseRoutePoint(
                    latitude = loc.latitude.toDouble(),
                    longitude = loc.longitude.toDouble(),
                    altitude = loc.altitude?.altitudeOrNull(),
                    accuracy = loc.accuracy?.posOrNull(),
                    timestampMs = loc.timestamp.toEpochMilli()
                )
            }

        val log = session?.log?.takeIf { it.isNotEmpty() }?.map { entry ->
            ExerciseLogPoint(
                timestampMs = entry.timestamp.toEpochMilli(),
                heartRate = entry.heartRate?.posOrNull(),
                cadence = entry.cadence?.posOrNull(),
                count = entry.count?.takeIf { it > 0 },
                power = entry.power?.posOrNull(),
                speed = entry.speed?.posOrNull()
            )
        }

        val swimming = session?.swimmingLog?.let { sw ->
            SwimmingInfo(
                poolLength = sw.poolLength.takeIf { it > 0 },
                poolLengthUnit = sw.poolLengthUnit?.takeIf { it.isNotBlank() },
                totalDistance = sw.totalDistance?.posOrNull(),
                totalDurationSec = sw.totalDuration?.seconds?.toInt()?.takeIf { it > 0 }
            )
        }

        return HealthRecord(
            dataType = DATA_TYPE_EXERCISE,
            timestamp = startMs,
            endTimestamp = endMs,
            tzOffset = currentTzOffset(),
            source = SOURCE,
            valueJson = json.encodeToString(ExerciseValue(
                exerciseType = mapExerciseType(exerciseType),
                intensity = deriveIntensity(heartRateAvg),
                durationMin = (durationMs / 60000L).toInt().takeIf { it > 0 },
                calories = session?.calories?.posOrNull(),
                heartRateAvg = heartRateAvg,
                heartRateMax = session?.maxHeartRate?.posOrNull()?.toInt(),
                heartRateMin = session?.minHeartRate?.posOrNull()?.toInt(),
                distance = session?.distance?.posOrNull(),
                altitudeGain = session?.altitudeGain?.posOrNull(),
                altitudeLoss = session?.altitudeLoss?.posOrNull(),
                maxAltitude = session?.maxAltitude?.altitudeOrNull(),
                minAltitude = session?.minAltitude?.altitudeOrNull(),
                count = session?.count?.takeIf { it > 0 },
                countType = session?.countType?.name?.takeIf { it != "UNDEFINED" }?.lowercase(),
                maxSpeed = session?.maxSpeed?.posOrNull(),
                meanSpeed = session?.meanSpeed?.posOrNull(),
                maxCadence = session?.maxCadence?.posOrNull(),
                meanCadence = session?.meanCadence?.posOrNull(),
                maxCalorieBurnRate = session?.maxCalorieBurnRate?.posOrNull(),
                meanCalorieBurnRate = session?.meanCalorieBurnRate?.posOrNull(),
                inclineDistance = session?.inclineDistance?.posOrNull(),
                declineDistance = session?.declineDistance?.posOrNull(),
                maxPower = session?.maxPower?.posOrNull(),
                meanPower = session?.meanPower?.posOrNull(),
                maxRpm = session?.maxRpm?.posOrNull(),
                meanRpm = session?.meanRpm?.posOrNull(),
                comment = session?.comment?.takeIf { it.isNotBlank() },
                customTitle = session?.customTitle?.takeIf { it.isNotBlank() },
                route = route,
                log = log,
                swimming = swimming
            )),
            createdAt = System.currentTimeMillis(),
        )
    }

    private fun mapSleepStage(stage: DataType.SleepType.StageType): String = when (stage) {
        DataType.SleepType.StageType.AWAKE -> "awake"
        DataType.SleepType.StageType.LIGHT -> "light"
        DataType.SleepType.StageType.DEEP -> "deep"
        DataType.SleepType.StageType.REM -> "rem"
        else -> "light"
    }

    private fun mapExerciseType(type: DataType.ExerciseType.PredefinedExerciseType): String = when (type) {
        DataType.ExerciseType.PredefinedExerciseType.WALKING -> "walking"
        DataType.ExerciseType.PredefinedExerciseType.RUNNING,
        DataType.ExerciseType.PredefinedExerciseType.TRACK_RUNNING -> "running"
        DataType.ExerciseType.PredefinedExerciseType.BIKING,
        DataType.ExerciseType.PredefinedExerciseType.MOUNTAIN_BIKING,
        DataType.ExerciseType.PredefinedExerciseType.STATIONARY_BIKING -> "cycling"
        DataType.ExerciseType.PredefinedExerciseType.POOL_SWIMMING,
        DataType.ExerciseType.PredefinedExerciseType.OPEN_WATER_SWIMMING -> "swimming"
        DataType.ExerciseType.PredefinedExerciseType.HIKING,
        DataType.ExerciseType.PredefinedExerciseType.BACKPACKING -> "hiking"
        DataType.ExerciseType.PredefinedExerciseType.YOGA -> "yoga"
        DataType.ExerciseType.PredefinedExerciseType.ELLIPTICAL -> "elliptical"
        DataType.ExerciseType.PredefinedExerciseType.DANCING,
        DataType.ExerciseType.PredefinedExerciseType.BALLROOM_DANCING,
        DataType.ExerciseType.PredefinedExerciseType.BALLET -> "dance"
        else -> "other"
    }

    private fun deriveIntensity(heartRateAvg: Int?): String? {
        heartRateAvg ?: return null
        return when {
            heartRateAvg < 100 -> "low"
            heartRateAvg < 140 -> "medium"
            else -> "high"
        }
    }

    // --- valueJson 직렬화용 내부 데이터 클래스 ---

    @Serializable
    private data class MetricValue(
        val heartRateAvg: Int?,
        val heartRateMin: Int?,
        val heartRateMax: Int?,
        val stepsInterval: Int?,
        val stepsDaily: Int?,
        val caloriesInterval: Double?,
        val caloriesDaily: Double?,
        val caloriesActiveInterval: Double?,
        val caloriesActiveDaily: Double?,
        val distanceInterval: Double?,
        val distanceDaily: Double?,
        val spO2: Int?,
        val hrv: Double?
    )

    @Serializable
    private data class SleepStageValue(val stage: String, val startMs: Long, val endMs: Long)

    @Serializable
    private data class SleepValue(
        val durationMin: Int?,
        val awakeMin: Int?,
        val lightMin: Int?,
        val deepMin: Int?,
        val remMin: Int?,
        val stages: List<SleepStageValue>?
    )

    @Serializable
    private data class ExerciseRoutePoint(
        val latitude: Double,
        val longitude: Double,
        val altitude: Double?,
        val accuracy: Double?,
        val timestampMs: Long
    )

    @Serializable
    private data class ExerciseLogPoint(
        val timestampMs: Long,
        val heartRate: Double?,
        val cadence: Double?,
        val count: Int?,
        val power: Double?,
        val speed: Double?
    )

    @Serializable
    private data class SwimmingInfo(
        val poolLength: Int?,
        val poolLengthUnit: String?,
        val totalDistance: Double?,
        val totalDurationSec: Int?
    )

    @Serializable
    private data class ExerciseValue(
        val exerciseType: String,
        val intensity: String?,
        val durationMin: Int?,
        val calories: Double?,
        val heartRateAvg: Int?,
        val heartRateMax: Int?,
        val heartRateMin: Int?,
        val distance: Double?,
        val altitudeGain: Double?,
        val altitudeLoss: Double?,
        val maxAltitude: Double?,
        val minAltitude: Double?,
        val count: Int?,
        val countType: String?,
        val maxSpeed: Double?,
        val meanSpeed: Double?,
        val maxCadence: Double?,
        val meanCadence: Double?,
        val maxCalorieBurnRate: Double?,
        val meanCalorieBurnRate: Double?,
        val inclineDistance: Double?,
        val declineDistance: Double?,
        val maxPower: Double?,
        val meanPower: Double?,
        val maxRpm: Double?,
        val meanRpm: Double?,
        val comment: String?,
        val customTitle: String?,
        val route: List<ExerciseRoutePoint>?,
        val log: List<ExerciseLogPoint>?,
        val swimming: SwimmingInfo?
    )

    @Serializable
    private data class HourlySummaryValue(
        val hour: String,
        val heartRateAvg: Int?,
        val heartRateMin: Int?,
        val heartRateMax: Int?,
        val stepsTotal: Int?,
        val caloriesTotalKcal: Double?,
        val caloriesActiveTotalKcal: Double?,
        val activeTimeTotalMin: Int?,
        val distanceTotalM: Double?
    )

    @Serializable
    private data class WeightValue(
        val weight: Double,
        val height: Double?,
        val bmi: Double?,
        val bodyFat: Double?,
        val bodyFatMass: Double?,
        val fatFree: Double?,
        val fatFreeMass: Double?,
        val skeletalMuscle: Double?,
        val skeletalMuscleMass: Double?,
        val muscleMass: Double?,
        val totalBodyWater: Double?,
        val basalMetabolicRate: Int?
    )

    @Serializable
    private data class DailySummaryValue(
        val date: String,
        val heartRateAvg: Int?,
        val heartRateMin: Int?,
        val heartRateMax: Int?,
        val stepsTotal: Int?,
        val caloriesTotalKcal: Double?,
        val caloriesActiveTotalKcal: Double?,
        val activeTimeTotalMin: Int?,
        val distanceTotalM: Double?,
        val sleepDurationMin: Int?,
        val sleepDeepMin: Int?,
        val sleepRemMin: Int?,
        val sleepLightMin: Int?,
        val sleepAwakeMin: Int?,
        val exerciseCount: Int?,
        val exerciseTotalMin: Int?,
        val exerciseTotalCalories: Double?
    )

    @Serializable
    private data class BloodGlucoseSeriesEntry(val glucose: Double, val timestampMs: Long)

    @Serializable
    private data class BloodGlucoseValue(
        val glucose: Double,
        val measurementType: String?,
        val sampleSourceType: String?,
        val mealTimeMs: Long?,
        val mealStatus: String?,
        val insulinInjected: Double?,
        val medicationTaken: Boolean?,
        val series: List<BloodGlucoseSeriesEntry>?
    )

    @Serializable
    private data class BloodPressureValue(
        val systolic: Double,
        val diastolic: Double,
        val mean: Double?,
        val pulseRate: Int?,
        val medicationTaken: Boolean?
    )

    @Serializable
    private data class NutritionValue(
        val mealType: String?,
        val title: String?,
        val calories: Double?,
        val totalFat: Double?,
        val saturatedFat: Double?,
        val polysaturatedFat: Double?,
        val monosaturatedFat: Double?,
        val transFat: Double?,
        val carbohydrate: Double?,
        val dietaryFiber: Double?,
        val sugar: Double?,
        val protein: Double?,
        val cholesterol: Double?,
        val sodium: Double?,
        val potassium: Double?,
        val vitaminA: Double?,
        val vitaminC: Double?,
        val calcium: Double?,
        val iron: Double?
    )

    @Serializable
    private data class WaterIntakeValue(val amount: Double)

    @Serializable
    private data class SleepApneaValue(val detectedSign: String)

    @Serializable
    private data class FloorsClimbedValue(val floor: Double)

    @Serializable
    private data class EnergyScoreValue(val score: Double)

    @Serializable
    private data class BodyTemperatureValue(val temperature: Double)

    @Serializable
    private data class SkinTemperatureSeriesEntry(
        val temperature: Double,
        val min: Double?,
        val max: Double?,
        val startMs: Long,
        val endMs: Long
    )

    @Serializable
    private data class SkinTemperatureValue(
        val temperature: Double?,
        val min: Double?,
        val max: Double?,
        val series: List<SkinTemperatureSeriesEntry>?
    )

    @Serializable
    private data class HeartRhythmValue(val status: String)

    companion object {
        const val DATA_TYPE_METRIC = "metric"
        const val DATA_TYPE_SLEEP = "sleep"
        const val DATA_TYPE_EXERCISE = "exercise"
        const val DATA_TYPE_HOURLY_SUMMARY = "hourly_summary"
        const val DATA_TYPE_DAILY_SUMMARY = "daily_summary"
        const val DATA_TYPE_WEIGHT = "weight"
        const val DATA_TYPE_BLOOD_GLUCOSE = "blood_glucose"
        const val DATA_TYPE_BLOOD_PRESSURE = "blood_pressure"
        const val DATA_TYPE_NUTRITION = "nutrition"
        const val DATA_TYPE_WATER_INTAKE = "water_intake"
        const val DATA_TYPE_SLEEP_APNEA = "sleep_apnea"
        const val DATA_TYPE_FLOORS_CLIMBED = "floors_climbed"
        const val DATA_TYPE_ENERGY_SCORE = "energy_score"
        const val DATA_TYPE_BODY_TEMPERATURE = "body_temperature"
        const val DATA_TYPE_SKIN_TEMPERATURE = "skin_temperature"
        const val DATA_TYPE_HEART_RHYTHM = "heart_rhythm"
        const val SOURCE = "samsung_health"

        private const val TAG = "FlutterHealth"
        private const val SAMSUNG_HEALTH_PACKAGE = "com.sec.android.app.shealth"

        private val REQUIRED_PERMISSIONS = setOf(
            Permission.of(DataTypes.HEART_RATE, AccessType.READ),
            Permission.of(DataTypes.STEPS, AccessType.READ),
            Permission.of(DataTypes.EXERCISE, AccessType.READ),
            Permission.of(DataTypes.SLEEP, AccessType.READ),
            Permission.of(DataTypes.BLOOD_OXYGEN, AccessType.READ),
            Permission.of(DataTypes.ACTIVITY_SUMMARY, AccessType.READ),
            Permission.of(DataTypes.BODY_COMPOSITION, AccessType.READ),
            Permission.of(DataTypes.BLOOD_GLUCOSE, AccessType.READ),
            Permission.of(DataTypes.BLOOD_PRESSURE, AccessType.READ),
            Permission.of(DataTypes.NUTRITION, AccessType.READ),
            Permission.of(DataTypes.WATER_INTAKE, AccessType.READ),
            Permission.of(DataTypes.SLEEP_APNEA, AccessType.READ),
            Permission.of(DataTypes.FLOORS_CLIMBED, AccessType.READ),
            Permission.of(DataTypes.ENERGY_SCORE, AccessType.READ),
            Permission.of(DataTypes.BODY_TEMPERATURE, AccessType.READ),
            Permission.of(DataTypes.SKIN_TEMPERATURE, AccessType.READ),
            Permission.of(DataTypes.IRREGULAR_HEART_RHYTHM_NOTIFICATION, AccessType.READ),
            Permission.of(DataTypes.EXERCISE_LOCATION, AccessType.READ),
        )
    }
}

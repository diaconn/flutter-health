package com.diaconn.flutter_health

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import com.diaconn.flutter_health.models.HealthRecord
import com.samsung.android.sdk.health.data.HealthDataService
import com.samsung.android.sdk.health.data.HealthDataStore
import com.samsung.android.sdk.health.data.data.AggregateOperation
import com.samsung.android.sdk.health.data.data.AggregatedData
import com.samsung.android.sdk.health.data.data.ChangeType
import com.samsung.android.sdk.health.data.data.HealthDataPoint
import com.samsung.android.sdk.health.data.data.entries.ExerciseSession
import com.samsung.android.sdk.health.data.permission.AccessType
import com.samsung.android.sdk.health.data.permission.Permission
import com.samsung.android.sdk.health.data.request.AggregateRequest
import com.samsung.android.sdk.health.data.request.DataType
import com.samsung.android.sdk.health.data.request.DataTypes
import com.samsung.android.sdk.health.data.request.InstantTimeFilter
import com.samsung.android.sdk.health.data.request.LocalDateFilter
import com.samsung.android.sdk.health.data.request.LocalTimeFilter
import com.samsung.android.sdk.health.data.request.LocalTimeGroup
import com.samsung.android.sdk.health.data.request.LocalTimeGroupUnit
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNamingStrategy
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
     * 심박수를 **벽시계 10분 격자 버킷**별 평균/최소/최대(bpm)로 반환(heart_rate_interval). 완료된(닫힌) 칸만.
     * steps/distance/calories 와 달리 그룹 집계로 avg/min/max 를 한 번에 못 받아, raw HEART_RATE 포인트를 격자로 직접 묶는다.
     */
    suspend fun queryHeartRate(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            // since 를 10분 격자 경계로 내림. epoch(ms)를 10분 단위로 내리면 UTC 10분 눈금인데, KST(+9:00)처럼 타임존 offset 이 10분 배수라 로컬 벽시계 10분 눈금(:00·:10·:20…)과도 일치한다.
            val gridStart = (since / BUCKET_MS) * BUCKET_MS
            if (gridStart >= to) return@runCatching emptyList<HealthRecord>()
            val filter = InstantTimeFilter.of(Instant.ofEpochMilli(gridStart), Instant.ofEpochMilli(to))
            val request = DataTypes.HEART_RATE.readDataRequestBuilder.setInstantTimeFilter(filter).build()
            // 측정 시각 기준 10분 격자 버킷으로 포인트의 HEART_RATE 값을 모은다.
            val byBucket = HashMap<Long, MutableList<Int>>()
            s.readData(request).dataList.forEach { point ->
                val v = point.getValueOrDefault(DataType.HeartRateType.HEART_RATE, 0f)
                if (v <= 0f) return@forEach
                val tMs = point.startTime?.toEpochMilli() ?: return@forEach
                val bucketStart = (tMs / BUCKET_MS) * BUCKET_MS
                byBucket.getOrPut(bucketStart) { mutableListOf() }.add(v.toInt())
            }
            val tz = currentTzOffset()
            val now = System.currentTimeMillis()
            byBucket.entries.mapNotNull { (bucketStart, values) ->
                val bucketEnd = bucketStart + BUCKET_MS
                if (bucketEnd > to || values.isEmpty()) return@mapNotNull null // 완료된 칸만
                HealthRecord(
                    dataType = DATA_TYPE_HEART_RATE_INTERVAL,
                    timestamp = bucketStart,
                    endTimestamp = bucketEnd,
                    tzOffset = tz,
                    source = SOURCE,
                    valueJson = json.encodeToString(HeartRateIntervalValue(
                        avg = (values.sum() / values.size).takeIf { it > 0 },
                        min = values.min().takeIf { it > 0 },
                        max = values.max().takeIf { it > 0 }
                    )),
                    createdAt = now,
                )
            }.sortedByDescending { it.timestamp }
        }.onFailure { Log.e(TAG, "심박수 격자 버킷 조회 실패", it) }.getOrDefault(emptyList())
    }

    /**
     * 걸음 수를 **벽시계 10분 격자 버킷**별 합(steps_interval)으로 반환한다.
     * Samsung 그룹 집계(LocalTimeGroup MINUTELY×10)로 한 번에 전 버킷을 받고, **완료된(닫힌) 칸만** 내보낸다.
     */
    suspend fun querySteps(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        val tz = currentTzOffset()
        val now = System.currentTimeMillis()
        return aggregateGrid(s, DataType.StepsType.TOTAL, since, to, "걸음 구간").mapNotNull { d ->
            val count = d.getValueOrDefault(0L).toInt().takeIf { it > 0 } ?: return@mapNotNull null
            val startMs = d.startTime.toEpochMilli()
            HealthRecord(DATA_TYPE_STEPS_INTERVAL, startMs, startMs + BUCKET_MS, tz, SOURCE,
                json.encodeToString(StepsIntervalValue(count)), now)
        }.sortedByDescending { it.timestamp }
    }

    /**
     * 이동 거리를 **벽시계 10분 격자 버킷**별 합(distance_interval, m)으로 반환한다.
     */
    suspend fun queryDistance(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        val tz = currentTzOffset()
        val now = System.currentTimeMillis()
        return aggregateGrid(s, DataType.ActivitySummaryType.TOTAL_DISTANCE, since, to, "이동 거리").mapNotNull { d ->
            val meters = d.getValueOrDefault(0f).toDouble().takeIf { it > 0.0 } ?: return@mapNotNull null
            val startMs = d.startTime.toEpochMilli()
            HealthRecord(DATA_TYPE_DISTANCE_INTERVAL, startMs, startMs + BUCKET_MS, tz, SOURCE,
                json.encodeToString(DistanceIntervalValue(meters)), now)
        }.sortedByDescending { it.timestamp }
    }

    /**
     * 소비 칼로리를 **벽시계 10분 격자 버킷**별 합(calories_interval, total=활동+기초대사·active=활동, kcal)으로 반환한다.
     * total/active 격자를 각각 받아 버킷 시작 기준으로 병합한다.
     */
    suspend fun queryCalories(since: Long, to: Long): List<HealthRecord> = coroutineScope {
        val s = store ?: return@coroutineScope emptyList()
        val totalD = async { aggregateGrid(s, DataType.ActivitySummaryType.TOTAL_CALORIES_BURNED, since, to, "칼로리") }
        val activeD = async { aggregateGrid(s, DataType.ActivitySummaryType.TOTAL_ACTIVE_CALORIES_BURNED, since, to, "활동 칼로리") }
        val activeByStart = activeD.await().associate { it.startTime.toEpochMilli() to it.getValueOrDefault(0f).toDouble() }
        val tz = currentTzOffset()
        val now = System.currentTimeMillis()
        totalD.await().mapNotNull { d ->
            val total = d.getValueOrDefault(0f).toDouble().takeIf { it > 0.0 } ?: return@mapNotNull null
            val startMs = d.startTime.toEpochMilli()
            val active = activeByStart[startMs]?.takeIf { it > 0.0 }
            HealthRecord(DATA_TYPE_CALORIES_INTERVAL, startMs, startMs + BUCKET_MS, tz, SOURCE,
                json.encodeToString(CaloriesIntervalValue(total = total, active = active)), now)
        }.sortedByDescending { it.timestamp }
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
                .sortedByDescending { it.timestamp }
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
                .sortedByDescending { it.timestamp }
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
        val caloriesTotal = caD.await()
        val caloriesActiveTotal = caaD.await()
        val activeTimeTotal = atD.await()
        val distanceTotal = diD.await()

        if (hrStats.avg == null && stepsTotal == null && caloriesTotal == null &&
            caloriesActiveTotal == null && activeTimeTotal == null && distanceTotal == null) {
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
                caloriesTotal = caloriesTotal,
                caloriesActiveTotal = caloriesActiveTotal,
                activeTimeTotal = activeTimeTotal,
                distanceTotal = distanceTotal
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
        val caloriesTotal = caD.await()
        val caloriesActiveTotal = caaD.await()
        val activeTimeTotal = atD.await()
        val distanceTotal = diD.await()
        val sleepSessions = sleepD.await()
        val exerciseSessions = exerciseD.await()

        val mainSleep = sleepSessions.maxByOrNull { it.endTimestamp - it.timestamp }
        val sleepDuration = mainSleep?.let { (it.endTimestamp - it.timestamp) / 60000 }?.toInt()

        val exerciseCount = exerciseSessions.size.takeIf { it > 0 }
        val exerciseTotalMin = exerciseSessions.sumOf { (it.endTimestamp - it.timestamp) / 60000 }.toInt().takeIf { it > 0 }
        val exerciseTotalCalories = exerciseSessions.mapNotNull {
            runCatching { json.decodeFromString<ExerciseValue>(it.valueJson).calories }.getOrNull()
        }.reduceOrNull { acc, d -> acc + d }

        if (hrStats.avg == null && stepsTotal == null && sleepDuration == null && exerciseCount == null) {
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
                caloriesTotal = caloriesTotal,
                caloriesActiveTotal = caloriesActiveTotal,
                activeTimeTotal = activeTimeTotal,
                distanceTotal = distanceTotal,
                sleepDuration = sleepDuration,
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
                .sortedByDescending { it.startTime?.toEpochMilli() ?: 0L }
                .mapNotNull { point ->
                    val value = weightValueOf(point) ?: return@mapNotNull null
                    val startMs = point.startTime?.toEpochMilli() ?: since
                    val endMs = point.endTime?.toEpochMilli() ?: startMs
                    HealthRecord(
                        dataType = DATA_TYPE_WEIGHT,
                        timestamp = startMs,
                        endTimestamp = endMs,
                        tzOffset = tz,
                        source = SOURCE,
                        valueJson = json.encodeToString(value),
                        createdAt = now,
                        uid = point.uid,
                    )
                }
        }.onFailure { Log.e(TAG, "체중 조회 실패", it) }.getOrDefault(emptyList())
    }

    /** [since]~[to] 구간 내 모든 혈당 측정 목록. */
    suspend fun queryBloodGlucose(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.BLOOD_GLUCOSE, "혈당") { point, startMs, endMs, tz, now ->
            val value = bloodGlucoseValueOf(point) ?: return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_BLOOD_GLUCOSE,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(value),
                createdAt = now,
                uid = point.uid,
            )
        }

    /** [since]~[to] 구간 내 모든 혈압 측정 목록. */
    suspend fun queryBloodPressure(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.BLOOD_PRESSURE, "혈압") { point, startMs, endMs, tz, now ->
            val value = bloodPressureValueOf(point) ?: return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_BLOOD_PRESSURE,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(value),
                createdAt = now,
                uid = point.uid,
            )
        }

    /** [since]~[to] 구간 내 모든 영양 기록. */
    suspend fun queryNutrition(since: Long, to: Long): List<HealthRecord> =
        readPoints(since, to, DataTypes.NUTRITION, "영양") { point, startMs, endMs, tz, now ->
            val value = nutritionValueOf(point) ?: return@readPoints null
            HealthRecord(
                dataType = DATA_TYPE_NUTRITION,
                timestamp = startMs,
                endTimestamp = endMs,
                tzOffset = tz,
                source = SOURCE,
                valueJson = json.encodeToString(value),
                createdAt = now,
                uid = point.uid,
            )
        }

    /** 영양 포인트 → 전체 영양소 값(19필드). 유효 필드가 하나도 없으면 null. queryNutrition·변경 피드 공용. */
    private fun nutritionValueOf(point: HealthDataPoint): NutritionValue? {
        val mealType = runCatching { point.getValue(DataType.NutritionType.MEAL_TYPE) }
            .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase()
        val title = runCatching { point.getValue(DataType.NutritionType.TITLE) }.getOrNull()
        val calories = nf(point, DataType.NutritionType.CALORIES)
        val totalFat = nf(point, DataType.NutritionType.TOTAL_FAT)
        val saturatedFat = nf(point, DataType.NutritionType.SATURATED_FAT)
        val polyunsaturatedFat = nf(point, DataType.NutritionType.POLYSATURATED_FAT)
        val monounsaturatedFat = nf(point, DataType.NutritionType.MONOSATURATED_FAT)
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
            mealType, title, calories, totalFat, saturatedFat, polyunsaturatedFat, monounsaturatedFat,
            transFat, carbohydrate, dietaryFiber, sugar, protein, cholesterol, sodium, potassium,
            vitaminA, vitaminC, calcium, iron
        ).any { it != null }
        if (!anyField) return null

        return NutritionValue(
            mealType = mealType, title = title, calories = calories,
            totalFat = totalFat, saturatedFat = saturatedFat,
            polyunsaturatedFat = polyunsaturatedFat, monounsaturatedFat = monounsaturatedFat,
            transFat = transFat, carbohydrate = carbohydrate, dietaryFiber = dietaryFiber,
            sugar = sugar, protein = protein, cholesterol = cholesterol,
            sodium = sodium, potassium = potassium,
            vitaminA = vitaminA, vitaminC = vitaminC, calcium = calcium, iron = iron
        )
    }

    /** 체성분 포인트 → weight(+bmi/체지방률) 값. weight 없으면 null. queryWeights·변경 피드 공용. */
    private fun weightValueOf(point: HealthDataPoint): WeightValue? {
        val weight = point.getValueOrDefault(DataType.BodyCompositionType.WEIGHT, 0f)
        if (weight <= 0f) return null
        fun bcf(field: com.samsung.android.sdk.health.data.data.Field<Float>): Double? =
            point.getValueOrDefault(field, 0f).let { if (it > 0f) it.toDouble() else null }
        return WeightValue(
            weight = weight.toDouble(),
            bmi = bcf(DataType.BodyCompositionType.BODY_MASS_INDEX),
            bodyFat = bcf(DataType.BodyCompositionType.BODY_FAT)
        )
    }

    /** 혈당 포인트 → 값(mmol/L→mg/dL). 유효 혈당 없으면 null. queryBloodGlucose·변경 피드 공용. */
    private fun bloodGlucoseValueOf(point: HealthDataPoint): BloodGlucoseValue? {
        val glucose = runCatching { point.getValue(DataType.BloodGlucoseType.GLUCOSE_LEVEL) }.getOrNull()
            ?: point.getValueOrDefault(DataType.BloodGlucoseType.GLUCOSE_LEVEL, 0f)
        if (glucose <= 0f) return null
        val mealStatus = runCatching { point.getValue(DataType.BloodGlucoseType.MEAL_STATUS) }
            .getOrNull()?.name?.takeIf { it != "UNDEFINED" }?.lowercase()
        val insulin = runCatching { point.getValue(DataType.BloodGlucoseType.INSULIN_INJECTED) }
            .getOrNull()?.let { if (it > 0f) it.toDouble() else null }
        val medication = runCatching { point.getValue(DataType.BloodGlucoseType.MEDICATION_TAKEN) }
            .getOrNull()
        val series = runCatching { point.getValue(DataType.BloodGlucoseType.SERIES_DATA) }
            .getOrNull()?.takeIf { it.isNotEmpty() }?.map {
                BloodGlucoseSeriesEntry(
                    glucose = it.glucose.toDouble() * MMOL_L_TO_MG_DL,
                    timestampMs = it.timestamp.toEpochMilli()
                )
            }
        return BloodGlucoseValue(
            glucose = glucose.toDouble() * MMOL_L_TO_MG_DL,
            mealStatus = mealStatus,
            insulinInjected = insulin,
            medicationTaken = medication,
            series = series
        )
    }

    /** 혈압 포인트 → 값. systolic/diastolic 없으면 null. queryBloodPressure·변경 피드 공용. */
    private fun bloodPressureValueOf(point: HealthDataPoint): BloodPressureValue? {
        val systolic = runCatching { point.getValue(DataType.BloodPressureType.SYSTOLIC) }.getOrNull()
        val diastolic = runCatching { point.getValue(DataType.BloodPressureType.DIASTOLIC) }.getOrNull()
        if (systolic == null || diastolic == null || systolic <= 0f || diastolic <= 0f) return null
        val mean = runCatching { point.getValue(DataType.BloodPressureType.MEAN) }.getOrNull()
            ?.let { if (it > 0f) it.toDouble() else null }
        val pulseRate = runCatching { point.getValue(DataType.BloodPressureType.PULSE_RATE) }.getOrNull()
            ?.takeIf { it > 0 }
        val medication = runCatching { point.getValue(DataType.BloodPressureType.MEDICATION_TAKEN) }.getOrNull()
        return BloodPressureValue(
            systolic = systolic.toDouble(),
            diastolic = diastolic.toDouble(),
            mean = mean,
            pulseRate = pulseRate,
            medicationTaken = medication
        )
    }

    /** 수분 포인트 → 값. amount 없으면 null. queryWaterIntake·변경 피드 공용. */
    private fun waterIntakeValueOf(point: HealthDataPoint): WaterIntakeValue? {
        val amount = runCatching { point.getValue(DataType.WaterIntakeType.AMOUNT) }.getOrNull()
        if (amount == null || amount <= 0f) return null
        return WaterIntakeValue(amount = amount.toDouble())
    }

    /**
     * [since]~[to] 구간 내 모든 수분 섭취 기록.
     * 반환은 표시 일관성 위해 최신순(내림차순).
     */
    suspend fun queryWaterIntake(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            val filter = InstantTimeFilter.of(Instant.ofEpochMilli(since), Instant.ofEpochMilli(to))
            val request = DataTypes.WATER_INTAKE.readDataRequestBuilder.setInstantTimeFilter(filter).build()
            val tz = currentTzOffset()
            val now = System.currentTimeMillis()

            s.readData(request).dataList.mapNotNull { point ->
                val value = waterIntakeValueOf(point) ?: return@mapNotNull null
                val startMs = point.startTime?.toEpochMilli() ?: return@mapNotNull null
                HealthRecord(
                    dataType = DATA_TYPE_WATER_INTAKE,
                    timestamp = startMs,
                    endTimestamp = point.endTime?.toEpochMilli() ?: startMs,
                    tzOffset = tz,
                    source = SOURCE,
                    valueJson = json.encodeToString(value),
                    createdAt = now,
                    uid = point.uid,
                )
            }.sortedByDescending { it.timestamp }
        }.onFailure { Log.e(TAG, "수분 섭취 조회 실패", it) }.getOrDefault(emptyList())
    }

    /**
     * 사용자 프로필에 설정된 현재 키(신장) 1건. [since]/[to] 는 프로필 값이라 무시(시간 범위 없음).
     * UserProfile.HEIGHT 는 Samsung 앱 프로필 설정값 — 체성분 측정의 HEIGHT(직접 입력 경로 없어 제거됨)와 별개.
     */
    suspend fun queryHeight(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            val request = DataTypes.USER_PROFILE.readDataRequestBuilder.build()
            val tz = currentTzOffset()
            val now = System.currentTimeMillis()
            // 프로필 값은 측정 시각·uid 가 없어 당일 자정(로컬)을 시각으로 사용 → 하루 한 행.
            // 서버 시각매칭 upsert: 같은 날 같은 값 skip / 값 변경 시 그 행 UPDATE / 날 바뀌면 새 행.
            val midnight = LocalDate.now(ZoneId.systemDefault()).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
            s.readData(request).dataList.mapNotNull { point ->
                val height = point.getValueOrDefault(DataType.UserProfileDataType.HEIGHT, 0f)
                if (height <= 0f) return@mapNotNull null
                HealthRecord(
                    dataType = DATA_TYPE_HEIGHT,
                    timestamp = midnight,
                    endTimestamp = midnight,
                    tzOffset = tz,
                    source = SOURCE,
                    // Samsung UserProfile.HEIGHT 는 cm (iOS·스키마와 통일).
                    valueJson = json.encodeToString(HeightValue(height = height.toDouble())),
                    createdAt = now,
                    // UserProfile 은 UserDataPoint(레코드 uid 없는 프로필 값) → uid 미설정(null).
                )
            }
        }.onFailure { Log.e(TAG, "키(프로필) 조회 실패", it) }.getOrDefault(emptyList())
    }

    /**
     * 변경 피드(추가·수정·삭제)를 반환한다. 앱 편집·삭제를 소스와 1:1로 반영하기 위한 경로.
     *
     * `store.readChanges` 로 [dataType] 의 변경분을 받아 UPSERT(신규·수정)/DELETE(삭제·구버전)로 분류한다.
     * - [since]~[to] = **변경시각(changeTime)** 창(데이터 자체 시각이 아니라 편집/삭제가 일어난 시각).
     *   증분 동기화 시 [since]=마지막 동기화 시각을 넘겨 그 이후 변경만 받는다(Android는 SDK에 별도 sync 커서가 없음).
     * - [pageToken] = 이어받을 시작 페이지(보통 null). **응답이 여러 페이지면 내부에서 전부 소진**해 누락 없이 모아 반환한다
     *   → 반환 [ChangeResult.pageToken] 은 항상 null(전량 소진). 안전상 [MAX_CHANGE_PAGES] 페이지까지만.
     * - 세션형(sleep/exercise)은 기존 빌더로 완전한 레코드, 그 외는 uid+시각(+영양 title) 최소 레코드로 반환.
     */
    suspend fun queryChanges(dataType: String, since: Long, to: Long, pageToken: String?): ChangeResult {
        val s = store ?: return ChangeResult(emptyList(), emptyList(), null)
        val readable = changeReadableFor(dataType) ?: return ChangeResult(emptyList(), emptyList(), null)
        return runCatching {
            val filter = InstantTimeFilter.of(Instant.ofEpochMilli(since), Instant.ofEpochMilli(to))
            val upserted = mutableListOf<HealthRecord>()
            val deleted = mutableListOf<String>()
            var nextToken: String? = pageToken
            var pages = 0
            do {
                // changedDataRequestBuilder 는 매 호출 새 빌더를 반환 → 페이지마다 새로 만들어 pageToken 만 교체.
                val builder = readable.changedDataRequestBuilder.setChangeTimeFilter(filter)
                nextToken?.let { builder.setPageToken(it) }
                val response = s.readChanges(builder.build())
                response.dataList.forEach { change ->
                    when (change.changeType) {
                        ChangeType.UPSERT -> change.upsertDataPoint?.let { p ->
                            buildChangeRecord(dataType, p)?.let { upserted.add(it) }
                        }
                        ChangeType.DELETE -> change.deleteDataUid?.let { deleted.add(it) }
                    }
                }
                nextToken = response.pageToken
                pages++
            } while (nextToken != null && pages < MAX_CHANGE_PAGES)
            if (nextToken != null) Log.w(TAG, "변경 피드 페이지 상한($MAX_CHANGE_PAGES) 도달 — 잔여 페이지 있음($dataType)")
            // 전량 소진 → 반환 token=null. 다음 증분 조회는 since=이번 to 로 호출.
            ChangeResult(upserted.sortedByDescending { it.timestamp }, deleted, null)
        }.onFailure { Log.e(TAG, "변경 피드 조회 실패($dataType)", it) }
            .getOrDefault(ChangeResult(emptyList(), emptyList(), null))
    }

    // --- Private ---

    @Volatile private var store: HealthDataStore? = null
    // iOS JSONEncoder 가 nil 을 키째로 omit 하는 동작과 통일 (Apple HealthKit/Google Fit/FHIR 권고 동일).
    // 기본 kotlinx.serialization 은 explicitNulls=true 라 `"key": null` 을 명시 출력 → false 로 끔.
    @OptIn(ExperimentalSerializationApi::class)
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        namingStrategy = JsonNamingStrategy.SnakeCase // valueJson 키 snake_case 통일(서버 json_data 스키마 일관)
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

    private suspend fun aggregateSteps(s: HealthDataStore, filter: LocalTimeFilter): Int? =
        runCatching {
            val request = DataType.StepsType.TOTAL.requestBuilder.setLocalTimeFilter(filter).build()
            s.aggregateData(request).dataList.firstOrNull()?.value?.toInt()?.takeIf { it > 0 }
        }.onFailure { Log.e(TAG, "걸음수 집계 실패", it) }.getOrDefault(null)

    /**
     * since 를 BUCKET_MS 격자 경계로 내려 [그 경계, to] 를 LocalTimeGroup(MINUTELY×BUCKET_MIN) 으로 그룹 집계한다.
     * **완료된(닫힌) 칸만**(start+BUCKET_MS <= to) 반환해 진행 중인 마지막 부분 칸을 제외한다.
     * steps_interval·distance_interval·calories_interval 이 공유하는 격자 집계 헬퍼.
     */
    private suspend fun <T : Any> aggregateGrid(
        s: HealthDataStore,
        op: AggregateOperation<T, AggregateRequest.LocalTimeBuilder<T>>,
        since: Long,
        to: Long,
        logTag: String
    ): List<AggregatedData<T>> =
        runCatching {
            val gridStart = (since / BUCKET_MS) * BUCKET_MS
            if (gridStart >= to) {
                emptyList()
            } else {
                val filter = LocalTimeFilter.of(gridStart.toLocalDateTime(), to.toLocalDateTime())
                val group = LocalTimeGroup.of(LocalTimeGroupUnit.MINUTELY, BUCKET_MIN)
                val request = op.requestBuilder.setLocalTimeFilterWithGroup(filter, group).build()
                s.aggregateData(request).dataList
                    .filter { it.startTime.toEpochMilli() + BUCKET_MS <= to } // 완료된(닫힌) 칸만
            }
        }.onFailure { Log.e(TAG, "$logTag 격자 집계 실패", it) }.getOrDefault(emptyList())

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
                .sortedByDescending { it.startTime?.toEpochMilli() ?: 0L }
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
        val durationMs = runCatching {
            point.getValue(DataType.SleepType.DURATION)?.toMillis()
        }.getOrNull() ?: (endMs - startMs)

        return HealthRecord(
            dataType = DATA_TYPE_SLEEP,
            timestamp = startMs,
            endTimestamp = endMs,
            tzOffset = currentTzOffset(),
            source = SOURCE,
            valueJson = json.encodeToString(SleepValue(
                durationMin = (durationMs / 60000L).toInt().takeIf { it > 0 }
            )),
            createdAt = System.currentTimeMillis(),
            uid = point.uid,
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

        // Samsung 은 "측정 안 됨" 을 0 으로 표현 → 0 이하는 측정 실패로 간주(null).
        fun Float.posOrNull(): Double? = toDouble().takeIf { it > 0.0 }

        return HealthRecord(
            dataType = DATA_TYPE_EXERCISE,
            timestamp = startMs,
            endTimestamp = endMs,
            tzOffset = currentTzOffset(),
            source = SOURCE,
            valueJson = json.encodeToString(ExerciseValue(
                exerciseType = mapExerciseType(exerciseType),
                duration = (durationMs / 60000L).toInt().takeIf { it > 0 },
                calories = session?.calories?.posOrNull(),
                distance = session?.distance?.posOrNull(),
                heartRateAvg = heartRateAvg,
                heartRateMax = session?.maxHeartRate?.posOrNull()?.toInt(),
                heartRateMin = session?.minHeartRate?.posOrNull()?.toInt(),
            )),
            createdAt = System.currentTimeMillis(),
            uid = point.uid,
        )
    }

    // PredefinedExerciseType(113종) → enum 이름 소문자 그대로 통과(TABLE_TENNIS→"table_tennis", 신규 자동 대응).
    private fun mapExerciseType(type: DataType.ExerciseType.PredefinedExerciseType): String = when (type) {
        DataType.ExerciseType.PredefinedExerciseType.UNDEFINED,
        DataType.ExerciseType.PredefinedExerciseType.OTHER,
        DataType.ExerciseType.PredefinedExerciseType.BREAK,
        DataType.ExerciseType.PredefinedExerciseType.COOL_DOWN,
        DataType.ExerciseType.PredefinedExerciseType.WARM_UP,
        DataType.ExerciseType.PredefinedExerciseType.TRANSITION -> "other"
        else -> type.name.lowercase()
    }

    /** 변경 피드 dataType → ChangeReadable DataType 매핑(지원 대상 타입만). */
    private fun changeReadableFor(dataType: String): DataType.ChangeReadable<HealthDataPoint>? = when (dataType) {
        DATA_TYPE_SLEEP -> DataTypes.SLEEP
        DATA_TYPE_EXERCISE -> DataTypes.EXERCISE
        DATA_TYPE_NUTRITION -> DataTypes.NUTRITION
        DATA_TYPE_BLOOD_GLUCOSE -> DataTypes.BLOOD_GLUCOSE
        DATA_TYPE_BLOOD_PRESSURE -> DataTypes.BLOOD_PRESSURE
        DATA_TYPE_WEIGHT -> DataTypes.BODY_COMPOSITION
        DATA_TYPE_WATER_INTAKE -> DataTypes.WATER_INTAKE
        else -> null
    }

    /** 변경 피드 UPSERT 데이터포인트 → HealthRecord. 정식 조회와 동일한 완전 value 빌더(valueOf) 재사용. */
    private fun buildChangeRecord(dataType: String, point: HealthDataPoint): HealthRecord? = when (dataType) {
        DATA_TYPE_SLEEP -> buildSleepRecord(point)
        DATA_TYPE_EXERCISE -> buildExerciseRecord(point)
        DATA_TYPE_NUTRITION -> nutritionValueOf(point)?.let { changeRecord(dataType, point, json.encodeToString(it)) }
        DATA_TYPE_WEIGHT -> weightValueOf(point)?.let { changeRecord(dataType, point, json.encodeToString(it)) }
        DATA_TYPE_BLOOD_GLUCOSE -> bloodGlucoseValueOf(point)?.let { changeRecord(dataType, point, json.encodeToString(it)) }
        DATA_TYPE_BLOOD_PRESSURE -> bloodPressureValueOf(point)?.let { changeRecord(dataType, point, json.encodeToString(it)) }
        DATA_TYPE_WATER_INTAKE -> waterIntakeValueOf(point)?.let { changeRecord(dataType, point, json.encodeToString(it)) }
        else -> null
    }

    /** 변경 피드 레코드 조립 — startTime 없으면 null(정식 조회와 동일 규칙). */
    private fun changeRecord(dataType: String, point: HealthDataPoint, valueJson: String): HealthRecord? {
        val startMs = point.startTime?.toEpochMilli() ?: return null
        val endMs = point.endTime?.toEpochMilli() ?: startMs
        return HealthRecord(dataType, startMs, endMs, currentTzOffset(), SOURCE, valueJson, System.currentTimeMillis(), uid = point.uid)
    }

    // --- valueJson 직렬화용 내부 데이터 클래스 ---

    /** 심박수 10분 격자 버킷 값(bpm). */
    @Serializable
    private data class HeartRateIntervalValue(
        val avg: Int?,
        val min: Int?,
        val max: Int?
    )

    /** 걸음 10분 격자 버킷 값. */
    @Serializable
    private data class StepsIntervalValue(val count: Int)

    /** 이동 거리 10분 격자 버킷 값(m). */
    @Serializable
    private data class DistanceIntervalValue(val distance: Double)

    /** 소비 칼로리 10분 격자 버킷 값(kcal). total=활동+기초대사, active=활동. */
    @Serializable
    private data class CaloriesIntervalValue(val total: Double, val active: Double? = null)


    @Serializable
    private data class SleepValue(
        val durationMin: Int?
    )

    @Serializable
    private data class ExerciseValue(
        val exerciseType: String,
        val duration: Int?,
        val calories: Double?,
        val distance: Double?,
        val heartRateAvg: Int?,
        val heartRateMax: Int?,
        val heartRateMin: Int?
    )

    @Serializable
    private data class HourlySummaryValue(
        val hour: String,
        val heartRateAvg: Int?,
        val heartRateMin: Int?,
        val heartRateMax: Int?,
        val stepsTotal: Int?,
        val caloriesTotal: Double?,
        val caloriesActiveTotal: Double?,
        val activeTimeTotal: Int?,
        val distanceTotal: Double?
    )

    @Serializable
    private data class WeightValue(
        val weight: Double,
        val bmi: Double?,
        val bodyFat: Double?
    )

    @Serializable
    private data class DailySummaryValue(
        val date: String,
        val heartRateAvg: Int?,
        val heartRateMin: Int?,
        val heartRateMax: Int?,
        val stepsTotal: Int?,
        val caloriesTotal: Double?,
        val caloriesActiveTotal: Double?,
        val activeTimeTotal: Int?,
        val distanceTotal: Double?,
        val sleepDuration: Int?,
        val exerciseCount: Int?,
        val exerciseTotalMin: Int?,
        val exerciseTotalCalories: Double?
    )

    @Serializable
    private data class BloodGlucoseSeriesEntry(val glucose: Double, val timestampMs: Long)

    @Serializable
    private data class BloodGlucoseValue(
        val glucose: Double,
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
        val polyunsaturatedFat: Double?,
        val monounsaturatedFat: Double?,
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
    private data class HeightValue(val height: Double)

    /** 변경 피드 조회 결과 홀더(플러그인 채널로 넘길 원자료). */
    data class ChangeResult(val upserted: List<HealthRecord>, val deleted: List<String>, val pageToken: String?)

    companion object {
        // 변경 피드(readChanges) 페이지 소진 상한 — 무한 루프 방지용 안전장치.
        private const val MAX_CHANGE_PAGES = 100

        // 격자 버킷 크기 (heart_rate_interval·steps_interval·distance_interval·calories_interval 공통).
        const val BUCKET_MIN = 10
        const val BUCKET_MS = BUCKET_MIN * 60 * 1000L
        const val DATA_TYPE_HEART_RATE_INTERVAL = "heart_rate_interval"
        const val DATA_TYPE_STEPS_INTERVAL = "steps_interval"
        const val DATA_TYPE_DISTANCE_INTERVAL = "distance_interval"
        const val DATA_TYPE_CALORIES_INTERVAL = "calories_interval"
        const val DATA_TYPE_SLEEP = "sleep"
        const val DATA_TYPE_EXERCISE = "exercise"
        const val DATA_TYPE_HOURLY_SUMMARY = "hourly_summary"
        const val DATA_TYPE_DAILY_SUMMARY = "daily_summary"
        const val DATA_TYPE_WEIGHT = "weight"
        const val DATA_TYPE_BLOOD_GLUCOSE = "blood_glucose"
        const val DATA_TYPE_BLOOD_PRESSURE = "blood_pressure"
        const val DATA_TYPE_NUTRITION = "nutrition"
        const val DATA_TYPE_WATER_INTAKE = "water_intake"
        const val DATA_TYPE_HEIGHT = "height"
        const val SOURCE = "samsung_health"

        // 혈당 단위 변환: Samsung SDK GLUCOSE_LEVEL raw = mmol/L → mg/dL (iOS HealthKit·스키마와 통일).
        // 1 mmol/L = 18.0182 mg/dL.
        private const val MMOL_L_TO_MG_DL = 18.0182

        private const val TAG = "FlutterHealth"
        private const val SAMSUNG_HEALTH_PACKAGE = "com.sec.android.app.shealth"

        private val REQUIRED_PERMISSIONS = setOf(
            Permission.of(DataTypes.HEART_RATE, AccessType.READ),
            Permission.of(DataTypes.STEPS, AccessType.READ),
            Permission.of(DataTypes.EXERCISE, AccessType.READ),
            Permission.of(DataTypes.SLEEP, AccessType.READ),
            Permission.of(DataTypes.ACTIVITY_SUMMARY, AccessType.READ),
            Permission.of(DataTypes.BODY_COMPOSITION, AccessType.READ),
            Permission.of(DataTypes.BLOOD_GLUCOSE, AccessType.READ),
            Permission.of(DataTypes.BLOOD_PRESSURE, AccessType.READ),
            Permission.of(DataTypes.NUTRITION, AccessType.READ),
            Permission.of(DataTypes.WATER_INTAKE, AccessType.READ),
            Permission.of(DataTypes.USER_PROFILE, AccessType.READ),
        )
    }
}

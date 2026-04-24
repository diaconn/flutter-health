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
        val diD = async { aggregateDistance(s, localFilter) }
        val ddD = async { aggregateDistance(s, dayFilter) }
        val spD = async { readSpO2Avg(s, instantFilter) }

        val hrStats = hrD.await()
        val stepsInterval = siD.await()
        val stepsDaily = sdD.await()
        val caloriesInterval = ciD.await()
        val caloriesDaily = cdD.await()
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
            val filter = InstantTimeFilter.of(Instant.ofEpochMilli(since), Instant.ofEpochMilli(to))
            val request = DataTypes.SLEEP.readDataRequestBuilder.setInstantTimeFilter(filter).build()
            s.readData(request).dataList.mapNotNull { buildSleepRecord(it) }
        }.onFailure { Log.e(TAG, "수면 세션 조회 실패", it) }.getOrDefault(emptyList())
    }

    /** [since]~[to] 구간에 종료된 운동 세션 목록을 반환한다. */
    suspend fun queryEndedExerciseSessions(since: Long, to: Long): List<HealthRecord> {
        val s = store ?: return emptyList()
        return runCatching {
            val filter = InstantTimeFilter.of(Instant.ofEpochMilli(since), Instant.ofEpochMilli(to))
            val request = DataTypes.EXERCISE.readDataRequestBuilder.setInstantTimeFilter(filter).build()
            s.readData(request).dataList.mapNotNull { buildExerciseRecord(it) }
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
        val diD = async { aggregateDistance(s, localFilter) }

        val hrStats = hrD.await()
        val stepsTotal = stD.await()
        val caloriesTotalKcal = caD.await()
        val distanceTotalM = diD.await()

        if (hrStats.avg == null && stepsTotal == null && caloriesTotalKcal == null) {
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
        val diD = async { aggregateDistance(s, localFilter) }
        val sleepD = async { queryEndedSleepSessions(dayStartMs, dayEndMs) }
        val exerciseD = async { queryEndedExerciseSessions(dayStartMs, dayEndMs) }

        val hrStats = hrD.await()
        val stepsTotal = stD.await()
        val caloriesTotalKcal = caD.await()
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
                distanceTotalM = distanceTotalM,
                sleepDurationMin = sleepDurationMin,
                sleepDeepMin = sleepValue?.deepMin,
                sleepRemMin = sleepValue?.remMin,
                exerciseCount = exerciseCount,
                exerciseTotalMin = exerciseTotalMin,
                exerciseTotalCalories = exerciseTotalCalories
            )),
            createdAt = System.currentTimeMillis(),
        )
    }

    // --- Private ---

    @Volatile private var store: HealthDataStore? = null
    private val json = Json { ignoreUnknownKeys = true }

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
                calories = session?.calories?.let { if (it > 0f) it.toDouble() else null },
                heartRateAvg = heartRateAvg,
                heartRateMax = session?.maxHeartRate?.let { if (it > 0f) it.toInt() else null },
                distance = session?.distance?.let { if (it > 0f) it.toDouble() else null }
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
    private data class ExerciseValue(
        val exerciseType: String,
        val intensity: String?,
        val durationMin: Int?,
        val calories: Double?,
        val heartRateAvg: Int?,
        val heartRateMax: Int?,
        val distance: Double?
    )

    @Serializable
    private data class HourlySummaryValue(
        val hour: String,
        val heartRateAvg: Int?,
        val heartRateMin: Int?,
        val heartRateMax: Int?,
        val stepsTotal: Int?,
        val caloriesTotalKcal: Double?,
        val distanceTotalM: Double?
    )

    @Serializable
    private data class DailySummaryValue(
        val date: String,
        val heartRateAvg: Int?,
        val heartRateMin: Int?,
        val heartRateMax: Int?,
        val stepsTotal: Int?,
        val caloriesTotalKcal: Double?,
        val distanceTotalM: Double?,
        val sleepDurationMin: Int?,
        val sleepDeepMin: Int?,
        val sleepRemMin: Int?,
        val exerciseCount: Int?,
        val exerciseTotalMin: Int?,
        val exerciseTotalCalories: Double?
    )

    companion object {
        const val DATA_TYPE_METRIC = "metric"
        const val DATA_TYPE_SLEEP = "sleep"
        const val DATA_TYPE_EXERCISE = "exercise"
        const val DATA_TYPE_HOURLY_SUMMARY = "hourly_summary"
        const val DATA_TYPE_DAILY_SUMMARY = "daily_summary"
        const val SOURCE = "samsung_health"

        private const val TAG = "FlutterHealth"
        private const val SAMSUNG_HEALTH_PACKAGE = "com.sec.android.app.shealth"

        private val REQUIRED_PERMISSIONS = setOf(
            Permission.of(DataTypes.HEART_RATE, AccessType.READ),
            Permission.of(DataTypes.STEPS, AccessType.READ),
            Permission.of(DataTypes.EXERCISE, AccessType.READ),
            Permission.of(DataTypes.SLEEP, AccessType.READ),
            Permission.of(DataTypes.BLOOD_OXYGEN, AccessType.READ),
            Permission.of(DataTypes.ACTIVITY_SUMMARY, AccessType.READ)
        )
    }
}

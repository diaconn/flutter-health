package com.diaconn.flutter_health

import android.app.Activity
import com.diaconn.flutter_health.models.toMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.LocalDate

class FlutterHealthPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var client: SamsungHealthClient
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        channel = MethodChannel(binding.binaryMessenger, "flutter_health")
        channel.setMethodCallHandler(this)
        client = SamsungHealthClient(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isAvailable" -> result.success(client.isAvailable())
            "connect" -> scope.launch {
                result.success(client.connect())
            }
            "disconnect" -> {
                client.disconnect()
                result.success(null)
            }
            "isPermissionGranted" -> scope.launch {
                result.success(client.isPermissionGranted())
            }
            "requestPermission" -> {
                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "Activity is not available", null)
                    return
                }
                scope.launch {
                    result.success(client.requestPermission(act))
                }
            }
            "queryMetric" -> {
                val from = call.argument<Number>("from")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                if (from == null || to == null) {
                    result.error("INVALID_ARGS", "from and to are required", null)
                    return
                }
                scope.launch {
                    runCatching { client.queryMetric(from, to)?.toMap() }
                        .onSuccess { result.success(it) }
                        .onFailure { result.error("QUERY_ERROR", it.message, null) }
                }
            }
            "queryEndedSleepSessions" -> {
                val since = call.argument<Number>("since")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                if (since == null || to == null) {
                    result.error("INVALID_ARGS", "since and to are required", null)
                    return
                }
                scope.launch {
                    runCatching { client.queryEndedSleepSessions(since, to).map { it.toMap() } }
                        .onSuccess { result.success(it) }
                        .onFailure { result.error("QUERY_ERROR", it.message, null) }
                }
            }
            "queryEndedExerciseSessions" -> {
                val since = call.argument<Number>("since")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                if (since == null || to == null) {
                    result.error("INVALID_ARGS", "since and to are required", null)
                    return
                }
                scope.launch {
                    runCatching { client.queryEndedExerciseSessions(since, to).map { it.toMap() } }
                        .onSuccess { result.success(it) }
                        .onFailure { result.error("QUERY_ERROR", it.message, null) }
                }
            }
            "queryHourlySummary" -> {
                val hourStart = call.argument<Number>("hourStart")?.toLong()
                val hourEnd = call.argument<Number>("hourEnd")?.toLong()
                if (hourStart == null || hourEnd == null) {
                    result.error("INVALID_ARGS", "hourStart and hourEnd are required", null)
                    return
                }
                scope.launch {
                    runCatching { client.queryHourlySummary(hourStart, hourEnd)?.toMap() }
                        .onSuccess { result.success(it) }
                        .onFailure { result.error("QUERY_ERROR", it.message, null) }
                }
            }
            "queryWeights" -> {
                val since = call.argument<Number>("since")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                if (since == null || to == null) {
                    result.error("INVALID_ARGS", "since and to are required", null)
                    return
                }
                scope.launch {
                    runCatching { client.queryWeights(since, to).map { it.toMap() } }
                        .onSuccess { result.success(it) }
                        .onFailure { result.error("QUERY_ERROR", it.message, null) }
                }
            }
            "queryDailySummary" -> {
                val isoDate = call.argument<String>("date")
                if (isoDate == null) {
                    result.error("INVALID_ARGS", "date is required", null)
                    return
                }
                val date = runCatching { LocalDate.parse(isoDate) }.getOrNull()
                if (date == null) {
                    result.error("INVALID_ARGS", "date must be ISO local date (yyyy-MM-dd)", null)
                    return
                }
                scope.launch {
                    runCatching { client.queryDailySummary(date)?.toMap() }
                        .onSuccess { result.success(it) }
                        .onFailure { result.error("QUERY_ERROR", it.message, null) }
                }
            }
            "queryBloodGlucose",
            "queryBloodPressure",
            "queryNutrition",
            "queryWaterIntake",
            "queryFloorsClimbed",
            "queryBodyTemperature" -> {
                val since = call.argument<Number>("since")?.toLong()
                val to = call.argument<Number>("to")?.toLong()
                if (since == null || to == null) {
                    result.error("INVALID_ARGS", "since and to are required", null)
                    return
                }
                scope.launch {
                    runCatching {
                        val list = when (call.method) {
                            "queryBloodGlucose" -> client.queryBloodGlucose(since, to)
                            "queryBloodPressure" -> client.queryBloodPressure(since, to)
                            "queryNutrition" -> client.queryNutrition(since, to)
                            "queryWaterIntake" -> client.queryWaterIntake(since, to)
                            "queryFloorsClimbed" -> client.queryFloorsClimbed(since, to)
                            "queryBodyTemperature" -> client.queryBodyTemperature(since, to)
                            else -> emptyList()
                        }
                        list.map { it.toMap() }
                    }.onSuccess { result.success(it) }
                     .onFailure { result.error("QUERY_ERROR", it.message, null) }
                }
            }
            else -> result.notImplemented()
        }
    }
}

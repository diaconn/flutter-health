package com.diaconn.flutter_health.models

data class HealthRecord(
    val dataType: String,
    val timestamp: Long,
    val endTimestamp: Long,
    val tzOffset: String,
    val source: String,
    val valueJson: String,
    val createdAt: Long,
)

fun HealthRecord.toMap(): Map<String, Any> = mapOf(
    "dataType" to dataType,
    "timestamp" to timestamp,
    "endTimestamp" to endTimestamp,
    "tzOffset" to tzOffset,
    "source" to source,
    "valueJson" to valueJson,
    "createdAt" to createdAt,
)

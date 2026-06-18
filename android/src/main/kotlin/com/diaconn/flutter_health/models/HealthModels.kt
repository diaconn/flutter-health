package com.diaconn.flutter_health.models

data class HealthRecord(
    val dataType: String,
    val timestamp: Long,
    val endTimestamp: Long,
    val tzOffset: String,
    val source: String,
    val valueJson: String,
    val createdAt: Long,
    // 원본 HealthDataPoint.uid (record 류). 집계 버킷(heart_rate_interval·steps_interval 등)·요약은 원본 레코드가 아니라 null.
    val uid: String? = null,
)

fun HealthRecord.toMap(): Map<String, Any> = buildMap {
    put("dataType", dataType)
    put("timestamp", timestamp)
    put("endTimestamp", endTimestamp)
    put("tzOffset", tzOffset)
    put("source", source)
    put("valueJson", valueJson)
    put("createdAt", createdAt)
    uid?.let { put("uid", it) } // null(집계)이면 키 생략
}

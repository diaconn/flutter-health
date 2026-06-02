class ExerciseLogPoint {
  final int timestampMs;
  final double? heartRate;
  final double? cadence;
  final int? count;
  final double? power;
  final double? speed;

  const ExerciseLogPoint({
    required this.timestampMs,
    this.heartRate,
    this.cadence,
    this.count,
    this.power,
    this.speed,
  });

  factory ExerciseLogPoint.fromJson(Map<String, dynamic> json) => ExerciseLogPoint(
        timestampMs: (json['timestampMs'] as num).toInt(),
        heartRate: (json['heartRate'] as num?)?.toDouble(),
        cadence: (json['cadence'] as num?)?.toDouble(),
        count: (json['count'] as num?)?.toInt(),
        power: (json['power'] as num?)?.toDouble(),
        speed: (json['speed'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'timestampMs': timestampMs,
        if (heartRate != null) 'heartRate': heartRate,
        if (cadence != null) 'cadence': cadence,
        if (count != null) 'count': count,
        if (power != null) 'power': power,
        if (speed != null) 'speed': speed,
      };
}

class SwimmingInfo {
  final int? poolLength;
  final String? poolLengthUnit;
  final double? totalDistance;
  final int? totalDurationSec;
  final String? locationType;   // "Pool" | "OpenWater"  (HKMetadataKeySwimmingLocationType)
  final String? strokeStyle;    // "Unknown" | "Mixed" | "Freestyle" | "Backstroke" |
                                // "Breaststroke" | "Butterfly" | "Kickboard"
                                //   (HKMetadataKeySwimmingStrokeStyle enum)

  const SwimmingInfo({
    this.poolLength,
    this.poolLengthUnit,
    this.totalDistance,
    this.totalDurationSec,
    this.locationType,
    this.strokeStyle,
  });

  factory SwimmingInfo.fromJson(Map<String, dynamic> json) => SwimmingInfo(
        poolLength: (json['poolLength'] as num?)?.toInt(),
        poolLengthUnit: json['poolLengthUnit'] as String?,
        totalDistance: (json['totalDistance'] as num?)?.toDouble(),
        totalDurationSec: (json['totalDurationSec'] as num?)?.toInt(),
        locationType: json['locationType'] as String?,
        strokeStyle: json['strokeStyle'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (poolLength != null) 'poolLength': poolLength,
        if (poolLengthUnit != null) 'poolLengthUnit': poolLengthUnit,
        if (totalDistance != null) 'totalDistance': totalDistance,
        if (totalDurationSec != null) 'totalDurationSec': totalDurationSec,
        if (locationType != null) 'locationType': locationType,
        if (strokeStyle != null) 'strokeStyle': strokeStyle,
      };
}

/// 운동 중 발생한 시점 이벤트 (iOS `HKWorkoutEvent`).
class ExerciseEventValue {
  /// "pause" | "resume" | "lap" | "marker" | "segment"
  /// | "motionPaused" | "motionResumed" | "pauseOrResumeRequest"
  final String type;
  final int startMs;
  final int endMs;
  /// 이벤트별 부가 metadata (JSON 문자열로 임베드)
  final String? metadata;

  const ExerciseEventValue({
    required this.type,
    required this.startMs,
    required this.endMs,
    this.metadata,
  });

  factory ExerciseEventValue.fromJson(Map<String, dynamic> json) => ExerciseEventValue(
        type: json['type'] as String,
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
        metadata: json['metadata'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'startMs': startMs,
        'endMs': endMs,
        if (metadata != null) 'metadata': metadata,
      };
}

/// 한 운동 세션 안의 개별 활동 (iOS 16+ `HKWorkoutActivity` — 트라이애슬론 등 멀티세그먼트).
class ExerciseActivityValue {
  final String activityType;
  final int startMs;
  final int endMs;
  final int? durationMin;
  final double? calories;
  final double? distance;
  final bool? isIndoor;

  const ExerciseActivityValue({
    required this.activityType,
    required this.startMs,
    required this.endMs,
    this.durationMin,
    this.calories,
    this.distance,
    this.isIndoor,
  });

  factory ExerciseActivityValue.fromJson(Map<String, dynamic> json) => ExerciseActivityValue(
        activityType: json['activityType'] as String,
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
        durationMin: (json['durationMin'] as num?)?.toInt(),
        calories: (json['calories'] as num?)?.toDouble(),
        distance: (json['distance'] as num?)?.toDouble(),
        isIndoor: json['isIndoor'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'activityType': activityType,
        'startMs': startMs,
        'endMs': endMs,
        if (durationMin != null) 'durationMin': durationMin,
        if (calories != null) 'calories': calories,
        if (distance != null) 'distance': distance,
        if (isIndoor != null) 'isIndoor': isIndoor,
      };
}

/// 운동을 기록한 디바이스 정보 (iOS `HKDevice`).
class ExerciseDeviceValue {
  final String? name;
  final String? manufacturer;
  final String? model;
  final String? hardwareVersion;
  final String? firmwareVersion;
  final String? softwareVersion;
  final String? localIdentifier;
  final String? udiDeviceIdentifier;

  const ExerciseDeviceValue({
    this.name,
    this.manufacturer,
    this.model,
    this.hardwareVersion,
    this.firmwareVersion,
    this.softwareVersion,
    this.localIdentifier,
    this.udiDeviceIdentifier,
  });

  factory ExerciseDeviceValue.fromJson(Map<String, dynamic> json) => ExerciseDeviceValue(
        name: json['name'] as String?,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        hardwareVersion: json['hardwareVersion'] as String?,
        firmwareVersion: json['firmwareVersion'] as String?,
        softwareVersion: json['softwareVersion'] as String?,
        localIdentifier: json['localIdentifier'] as String?,
        udiDeviceIdentifier: json['udiDeviceIdentifier'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (model != null) 'model': model,
        if (hardwareVersion != null) 'hardwareVersion': hardwareVersion,
        if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
        if (softwareVersion != null) 'softwareVersion': softwareVersion,
        if (localIdentifier != null) 'localIdentifier': localIdentifier,
        if (udiDeviceIdentifier != null) 'udiDeviceIdentifier': udiDeviceIdentifier,
      };
}

class ExerciseValue {
  final String exerciseType; // "walking"|"running"|"cycling"|"swimming"|"hiking"|"strength_training"|"yoga"|"elliptical"|"dance"|"other"
  final String? intensity; // "low"|"medium"|"high"
  final int? durationMin;
  final double? calories;
  final int? heartRateAvg;
  final int? heartRateMax;
  final int? heartRateMin;
  final double? distance;
  final double? altitudeGain;
  final double? altitudeLoss;
  final double? maxAltitude;
  final double? minAltitude;
  final int? count;
  final String? countType; // "stride"|"stroke"|"swing"|"repetition" — count 의 의미를 가리킴
  final double? maxSpeed;
  final double? meanSpeed;
  final double? maxCadence;
  final double? meanCadence;
  final double? maxCalorieBurnRate;
  final double? meanCalorieBurnRate;
  final double? inclineDistance;
  final double? declineDistance;
  final double? maxPower;
  final double? meanPower;
  final double? maxRpm;
  final double? meanRpm;
  final String? comment;
  final String? customTitle;
  final List<ExerciseLogPoint>? log;
  final SwimmingInfo? swimming;

  // iOS HKWorkout 부속 정보 직접 임베드.
  /// 운동 중 시점 이벤트 (pause/resume/lap/marker/segment). iOS `HKWorkoutEvent`.
  final List<ExerciseEventValue>? events;
  /// 멀티세그먼트 활동 (트라이애슬론 등). iOS 16+ `HKWorkoutActivity`.
  final List<ExerciseActivityValue>? activities;
  /// 실내 운동 여부. iOS `HKMetadataKeyIndoorWorkout`.
  final bool? isIndoor;
  /// 휴식 대비 강도 배수 (1=휴식, 8.5=러닝). iOS `HKMetadataKeyAverageMETs`.
  final double? averageMets;
  /// 측정 당시 날씨 상태. iOS `HKMetadataKeyWeatherCondition`.
  final String? weatherCondition;
  /// 측정 당시 기온 (°C). iOS `HKMetadataKeyWeatherTemperature`.
  final double? weatherTemperature;
  /// 측정 당시 습도 (%). iOS `HKMetadataKeyWeatherHumidity`.
  final double? weatherHumidity;
  /// 기록 디바이스 정보. iOS `HKDevice`.
  final ExerciseDeviceValue? device;

  const ExerciseValue({
    required this.exerciseType,
    this.intensity,
    this.durationMin,
    this.calories,
    this.heartRateAvg,
    this.heartRateMax,
    this.heartRateMin,
    this.distance,
    this.altitudeGain,
    this.altitudeLoss,
    this.maxAltitude,
    this.minAltitude,
    this.count,
    this.countType,
    this.maxSpeed,
    this.meanSpeed,
    this.maxCadence,
    this.meanCadence,
    this.maxCalorieBurnRate,
    this.meanCalorieBurnRate,
    this.inclineDistance,
    this.declineDistance,
    this.maxPower,
    this.meanPower,
    this.maxRpm,
    this.meanRpm,
    this.comment,
    this.customTitle,
    this.log,
    this.swimming,
    this.events,
    this.activities,
    this.isIndoor,
    this.averageMets,
    this.weatherCondition,
    this.weatherTemperature,
    this.weatherHumidity,
    this.device,
  });

  factory ExerciseValue.fromJson(Map<String, dynamic> json) => ExerciseValue(
        exerciseType: json['exerciseType'] as String,
        intensity: json['intensity'] as String?,
        durationMin: (json['durationMin'] as num?)?.toInt(),
        calories: (json['calories'] as num?)?.toDouble(),
        heartRateAvg: (json['heartRateAvg'] as num?)?.toInt(),
        heartRateMax: (json['heartRateMax'] as num?)?.toInt(),
        heartRateMin: (json['heartRateMin'] as num?)?.toInt(),
        distance: (json['distance'] as num?)?.toDouble(),
        altitudeGain: (json['altitudeGain'] as num?)?.toDouble(),
        altitudeLoss: (json['altitudeLoss'] as num?)?.toDouble(),
        maxAltitude: (json['maxAltitude'] as num?)?.toDouble(),
        minAltitude: (json['minAltitude'] as num?)?.toDouble(),
        count: (json['count'] as num?)?.toInt(),
        countType: json['countType'] as String?,
        maxSpeed: (json['maxSpeed'] as num?)?.toDouble(),
        meanSpeed: (json['meanSpeed'] as num?)?.toDouble(),
        maxCadence: (json['maxCadence'] as num?)?.toDouble(),
        meanCadence: (json['meanCadence'] as num?)?.toDouble(),
        maxCalorieBurnRate: (json['maxCalorieBurnRate'] as num?)?.toDouble(),
        meanCalorieBurnRate: (json['meanCalorieBurnRate'] as num?)?.toDouble(),
        inclineDistance: (json['inclineDistance'] as num?)?.toDouble(),
        declineDistance: (json['declineDistance'] as num?)?.toDouble(),
        maxPower: (json['maxPower'] as num?)?.toDouble(),
        meanPower: (json['meanPower'] as num?)?.toDouble(),
        maxRpm: (json['maxRpm'] as num?)?.toDouble(),
        meanRpm: (json['meanRpm'] as num?)?.toDouble(),
        comment: json['comment'] as String?,
        customTitle: json['customTitle'] as String?,
        log: (json['log'] as List?)
            ?.map((e) => ExerciseLogPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        swimming: json['swimming'] == null
            ? null
            : SwimmingInfo.fromJson(json['swimming'] as Map<String, dynamic>),
        events: (json['events'] as List?)
            ?.map((e) => ExerciseEventValue.fromJson(e as Map<String, dynamic>))
            .toList(),
        activities: (json['activities'] as List?)
            ?.map((e) => ExerciseActivityValue.fromJson(e as Map<String, dynamic>))
            .toList(),
        isIndoor: json['isIndoor'] as bool?,
        averageMets: (json['averageMets'] as num?)?.toDouble(),
        weatherCondition: json['weatherCondition'] as String?,
        weatherTemperature: (json['weatherTemperature'] as num?)?.toDouble(),
        weatherHumidity: (json['weatherHumidity'] as num?)?.toDouble(),
        device: json['device'] == null
            ? null
            : ExerciseDeviceValue.fromJson(json['device'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'exerciseType': exerciseType,
        if (intensity != null) 'intensity': intensity,
        if (durationMin != null) 'durationMin': durationMin,
        if (calories != null) 'calories': calories,
        if (heartRateAvg != null) 'heartRateAvg': heartRateAvg,
        if (heartRateMax != null) 'heartRateMax': heartRateMax,
        if (heartRateMin != null) 'heartRateMin': heartRateMin,
        if (distance != null) 'distance': distance,
        if (altitudeGain != null) 'altitudeGain': altitudeGain,
        if (altitudeLoss != null) 'altitudeLoss': altitudeLoss,
        if (maxAltitude != null) 'maxAltitude': maxAltitude,
        if (minAltitude != null) 'minAltitude': minAltitude,
        if (count != null) 'count': count,
        if (countType != null) 'countType': countType,
        if (maxSpeed != null) 'maxSpeed': maxSpeed,
        if (meanSpeed != null) 'meanSpeed': meanSpeed,
        if (maxCadence != null) 'maxCadence': maxCadence,
        if (meanCadence != null) 'meanCadence': meanCadence,
        if (maxCalorieBurnRate != null) 'maxCalorieBurnRate': maxCalorieBurnRate,
        if (meanCalorieBurnRate != null) 'meanCalorieBurnRate': meanCalorieBurnRate,
        if (inclineDistance != null) 'inclineDistance': inclineDistance,
        if (declineDistance != null) 'declineDistance': declineDistance,
        if (maxPower != null) 'maxPower': maxPower,
        if (meanPower != null) 'meanPower': meanPower,
        if (maxRpm != null) 'maxRpm': maxRpm,
        if (meanRpm != null) 'meanRpm': meanRpm,
        if (comment != null) 'comment': comment,
        if (customTitle != null) 'customTitle': customTitle,
        if (log != null) 'log': log!.map((e) => e.toJson()).toList(),
        if (swimming != null) 'swimming': swimming!.toJson(),
        if (events != null) 'events': events!.map((e) => e.toJson()).toList(),
        if (activities != null) 'activities': activities!.map((e) => e.toJson()).toList(),
        if (isIndoor != null) 'isIndoor': isIndoor,
        if (averageMets != null) 'averageMets': averageMets,
        if (weatherCondition != null) 'weatherCondition': weatherCondition,
        if (weatherTemperature != null) 'weatherTemperature': weatherTemperature,
        if (weatherHumidity != null) 'weatherHumidity': weatherHumidity,
        if (device != null) 'device': device!.toJson(),
      };
}

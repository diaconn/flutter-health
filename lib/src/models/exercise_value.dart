class ExerciseRoutePoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final int timestampMs;

  const ExerciseRoutePoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    required this.timestampMs,
  });

  factory ExerciseRoutePoint.fromJson(Map<String, dynamic> json) => ExerciseRoutePoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        altitude: (json['altitude'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        timestampMs: (json['timestampMs'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (altitude != null) 'altitude': altitude,
        if (accuracy != null) 'accuracy': accuracy,
        'timestampMs': timestampMs,
      };
}

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

  const SwimmingInfo({
    this.poolLength,
    this.poolLengthUnit,
    this.totalDistance,
    this.totalDurationSec,
  });

  factory SwimmingInfo.fromJson(Map<String, dynamic> json) => SwimmingInfo(
        poolLength: (json['poolLength'] as num?)?.toInt(),
        poolLengthUnit: json['poolLengthUnit'] as String?,
        totalDistance: (json['totalDistance'] as num?)?.toDouble(),
        totalDurationSec: (json['totalDurationSec'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        if (poolLength != null) 'poolLength': poolLength,
        if (poolLengthUnit != null) 'poolLengthUnit': poolLengthUnit,
        if (totalDistance != null) 'totalDistance': totalDistance,
        if (totalDurationSec != null) 'totalDurationSec': totalDurationSec,
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
  final List<ExerciseRoutePoint>? route;
  final List<ExerciseLogPoint>? log;
  final SwimmingInfo? swimming;

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
    this.route,
    this.log,
    this.swimming,
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
        route: (json['route'] as List?)
            ?.map((e) => ExerciseRoutePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        log: (json['log'] as List?)
            ?.map((e) => ExerciseLogPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        swimming: json['swimming'] == null
            ? null
            : SwimmingInfo.fromJson(json['swimming'] as Map<String, dynamic>),
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
        if (route != null) 'route': route!.map((e) => e.toJson()).toList(),
        if (log != null) 'log': log!.map((e) => e.toJson()).toList(),
        if (swimming != null) 'swimming': swimming!.toJson(),
      };
}

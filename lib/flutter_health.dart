export 'src/models/health_record.dart';
export 'src/models/metric_value.dart';
export 'src/models/sleep_value.dart';
export 'src/models/exercise_value.dart';
export 'src/models/hourly_summary_value.dart';
export 'src/models/daily_summary_value.dart';
export 'src/models/weight_value.dart';
export 'src/models/blood_glucose_value.dart';
export 'src/models/blood_pressure_value.dart';
export 'src/models/insulin_delivery_value.dart';
export 'src/models/nutrition_value.dart';
export 'src/models/water_intake_value.dart';
export 'src/models/sleep_apnea_value.dart';
export 'src/models/floors_climbed_value.dart';
export 'src/models/energy_score_value.dart';
export 'src/models/body_temperature_value.dart';
export 'src/models/skin_temperature_value.dart';
export 'src/models/heart_rhythm_value.dart';
export 'src/models/quantity_value.dart';
export 'src/models/duration_value.dart';
export 'src/models/symptom_value.dart';
export 'src/models/menstrual_flow_value.dart';
export 'src/models/state_of_mind_value.dart';
export 'src/models/ecg_value.dart';
export 'src/models/reproductive_value.dart';
export 'src/models/audiogram_value.dart';
export 'src/models/heartbeat_series_value.dart';
export 'src/models/workout_route_value.dart';
export 'src/models/clinical_record_value.dart';
export 'src/models/medication_value.dart';

import 'flutter_health_platform_interface.dart';
import 'src/models/health_record.dart';

/// [FlutterHealth.queryQuantity] 에 넘길 수 있는 단순 측정값 dataType 식별자.
/// iOS HealthKit 의 단일값 quantity 타입에 1:1 대응한다. (Android 미지원 타입은 빈 결과)
class QuantityType {
  // 신체측정
  static const height = 'height';
  static const waistCircumference = 'waist_circumference';
  static const bmi = 'bmi';
  static const bodyFat = 'body_fat';
  static const leanBodyMass = 'lean_body_mass';
  static const basalBodyTemperature = 'basal_body_temperature';
  static const body = <String>[
    height, waistCircumference, bmi, bodyFat, leanBodyMass, basalBodyTemperature,
  ];

  // 활동·이동
  static const walkingSpeed = 'walking_speed';
  static const walkingStepLength = 'walking_step_length';
  static const walkingAsymmetry = 'walking_asymmetry';
  static const walkingDoubleSupport = 'walking_double_support';
  static const runningSpeed = 'running_speed';
  static const runningPower = 'running_power';
  static const runningStrideLength = 'running_stride_length';
  static const runningVerticalOscillation = 'running_vertical_oscillation';
  static const runningGroundContact = 'running_ground_contact';
  static const cyclingSpeed = 'cycling_speed';
  static const cyclingPower = 'cycling_power';
  static const cyclingCadence = 'cycling_cadence';
  static const stairAscentSpeed = 'stair_ascent_speed';
  static const stairDescentSpeed = 'stair_descent_speed';
  static const sixMinuteWalk = 'six_minute_walk';
  static const walkingSteadiness = 'walking_steadiness';
  static const standTime = 'stand_time';
  static const exerciseTime = 'exercise_time';
  static const moveTime = 'move_time';
  static const distanceCycling = 'distance_cycling';
  static const distanceSwimming = 'distance_swimming';
  static const distanceWheelchair = 'distance_wheelchair';
  static const distanceDownhill = 'distance_downhill';
  static const pushCount = 'push_count';
  static const swimmingStrokeCount = 'swimming_stroke_count';
  static const timeInDaylight = 'time_in_daylight';
  static const activity = <String>[
    walkingSpeed, walkingStepLength, walkingAsymmetry, walkingDoubleSupport,
    runningSpeed, runningPower, runningStrideLength, runningVerticalOscillation, runningGroundContact,
    cyclingSpeed, cyclingPower, cyclingCadence,
    stairAscentSpeed, stairDescentSpeed, sixMinuteWalk, walkingSteadiness,
    standTime, exerciseTime, moveTime,
    distanceCycling, distanceSwimming, distanceWheelchair, distanceDownhill,
    pushCount, swimmingStrokeCount, timeInDaylight,
  ];

  // 심혈관
  static const restingHeartRate = 'resting_heart_rate';
  static const walkingHeartRateAvg = 'walking_heart_rate_avg';
  static const heartRateRecovery = 'heart_rate_recovery';
  static const atrialFibrillationBurden = 'atrial_fibrillation_burden';
  static const peripheralPerfusion = 'peripheral_perfusion';
  static const vo2max = 'vo2max';
  static const cardio = <String>[
    restingHeartRate, walkingHeartRateAvg, heartRateRecovery,
    atrialFibrillationBurden, peripheralPerfusion, vo2max,
  ];

  // 호흡
  static const respiratoryRate = 'respiratory_rate';
  static const forcedVitalCapacity = 'forced_vital_capacity';
  static const fev1 = 'fev1';
  static const peakExpiratoryFlow = 'peak_expiratory_flow';
  static const inhalerUsage = 'inhaler_usage';
  static const respiratory = <String>[
    respiratoryRate, forcedVitalCapacity, fev1, peakExpiratoryFlow, inhalerUsage,
  ];

  // 환경·청력
  static const uvExposure = 'uv_exposure';
  static const environmentalAudio = 'environmental_audio';
  static const headphoneAudio = 'headphone_audio';
  static const environment = <String>[uvExposure, environmentalAudio, headphoneAudio];

  // 대사·기타
  static const restingEnergy = 'resting_energy';
  static const insulinDelivery = 'insulin_delivery';
  static const electrodermalActivity = 'electrodermal_activity';
  static const bloodAlcohol = 'blood_alcohol';
  static const numAlcoholicBeverages = 'num_alcoholic_beverages';
  static const falls = 'falls';
  static const metabolic = <String>[
    restingEnergy, insulinDelivery, electrodermalActivity,
    bloodAlcohol, numAlcoholicBeverages, falls,
  ];

  // 진단·검증용 — Metric(5min) 응답이 비어 보일 때 24h 이력으로 실측 여부 확인.
  /// 혈중산소 단독 시계열 (iOS 8+; Android 는 metric 5분 묶음에서만 평균값으로 노출).
  static const oxygenSaturation = 'oxygen_saturation';
  /// 심박변이도 SDNN 단독 시계열 (iOS 11+; Android SDK 미지원).
  static const hrvSdnn = 'hrv_sdnn';
  static const diagnostic = <String>[oxygenSaturation, hrvSdnn];

  // 운동 부속 quantity (iOS 16+/18+) — 운동 세션과 첨부되는 측정값.
  /// iOS 18+. 추정 운동 효과 점수 (1~10, appleEffortScore unit).
  static const estimatedWorkoutEffortScore = 'estimated_workout_effort_score';
  /// iOS 18+. 사용자 입력 운동 효과 점수.
  static const workoutEffortScore = 'workout_effort_score';
  /// iOS 16+. 수중 깊이 (다이빙·수영, m).
  static const underwaterDepth = 'underwater_depth';
  /// iOS 16+. 수온 (degC).
  static const waterTemperature = 'water_temperature';
  static const workoutAttached = <String>[
    estimatedWorkoutEffortScore, workoutEffortScore, underwaterDepth, waterTemperature,
  ];

  /// 한 번에 순회하며 수집할 때 쓰는 전체 목록.
  static const all = <String>[
    ...body, ...activity, ...cardio, ...respiratory, ...environment, ...metabolic,
    ...workoutAttached,
  ];
}

/// [FlutterHealth.queryCategory] 에 넘길 수 있는 지속시간형 category dataType.
class CategoryType {
  static const mindful = 'mindful';
  static const toothbrushing = 'toothbrushing';
  static const handwashing = 'handwashing';
  // PM 6 v3 — 고/저 심박 이벤트 (iOS 12.2+).
  /// 안정 시 임계 초과 심박 이벤트. iOS `HKCategoryTypeIdentifierHighHeartRateEvent`.
  static const highHeartRateEvent = 'high_heart_rate_event';
  /// 안정 시 임계 미만 심박 이벤트. iOS `HKCategoryTypeIdentifierLowHeartRateEvent`.
  static const lowHeartRateEvent = 'low_heart_rate_event';

  static const all = <String>[
    mindful, toothbrushing, handwashing,
    highHeartRateEvent, lowHeartRateEvent,
  ];

  /// 심혈관 이벤트만 (demo 의 심혈관 섹션 전용).
  static const cardioEvents = <String>[highHeartRateEvent, lowHeartRateEvent];
}

/// [FlutterHealth.queryReproductive] 에 넘길 수 있는 생리주기 상세 dataType.
class ReproductiveType {
  static const intermenstrualBleeding = 'intermenstrual_bleeding';
  static const sexualActivity = 'sexual_activity';
  static const ovulationTest = 'ovulation_test';
  static const cervicalMucus = 'cervical_mucus';
  static const contraceptive = 'contraceptive';
  static const pregnancyTest = 'pregnancy_test';
  static const progesteroneTest = 'progesterone_test';
  static const lactation = 'lactation';

  static const all = <String>[
    intermenstrualBleeding,
    sexualActivity,
    ovulationTest,
    cervicalMucus,
    contraceptive,
    pregnancyTest,
    progesteroneTest,
    lactation,
  ];
}

/// [FlutterHealth.queryClinical] 에 넘길 수 있는 임상기록 dataType.
/// 주의: 실제 데이터 수집은 'health-records' entitlement(Apple Developer Portal capability 승인) 필요.
class ClinicalType {
  static const allergy = 'clinical_allergy';
  static const condition = 'clinical_condition';
  static const immunization = 'clinical_immunization';
  static const labResult = 'clinical_lab_result';
  static const medication = 'clinical_medication';
  static const procedure = 'clinical_procedure';
  static const vitalSign = 'clinical_vital_sign';
  static const coverage = 'clinical_coverage';

  static const all = <String>[
    allergy, condition, immunization, labResult,
    medication, procedure, vitalSign, coverage,
  ];
}

/// [FlutterHealth.querySymptom] 에 넘길 수 있는 증상 dataType.
class SymptomType {
  static const coughing = 'symptom_coughing';
  static const chestTightnessOrPain = 'symptom_chest_tightness_or_pain';
  static const shortnessOfBreath = 'symptom_shortness_of_breath';
  static const rapidHeartbeat = 'symptom_rapid_heartbeat';
  static const skippedHeartbeat = 'symptom_skipped_heartbeat';
  static const fatigue = 'symptom_fatigue';
  static const dizziness = 'symptom_dizziness';
  static const abdominalCramps = 'symptom_abdominal_cramps';
  static const bloating = 'symptom_bloating';
  static const constipation = 'symptom_constipation';
  static const diarrhea = 'symptom_diarrhea';
  static const heartburn = 'symptom_heartburn';
  static const nausea = 'symptom_nausea';
  static const vomiting = 'symptom_vomiting';
  static const appetiteChanges = 'symptom_appetite_changes';
  static const acne = 'symptom_acne';
  static const drySkin = 'symptom_dry_skin';
  static const hairLoss = 'symptom_hair_loss';
  static const hotFlashes = 'symptom_hot_flashes';
  static const nightSweats = 'symptom_night_sweats';
  static const chills = 'symptom_chills';
  static const fever = 'symptom_fever';
  static const headache = 'symptom_headache';
  static const fainting = 'symptom_fainting';
  static const moodChanges = 'symptom_mood_changes';
  static const lowerBackPain = 'symptom_lower_back_pain';
  static const sleepChanges = 'symptom_sleep_changes';
  static const bladderIncontinence = 'symptom_bladder_incontinence';
  static const memoryLapse = 'symptom_memory_lapse';
  static const lossOfSmell = 'symptom_loss_of_smell';
  static const lossOfTaste = 'symptom_loss_of_taste';
  static const runnyNose = 'symptom_runny_nose';
  static const soreThroat = 'symptom_sore_throat';
  static const sinusCongestion = 'symptom_sinus_congestion';
  static const wheezing = 'symptom_wheezing';
  static const pelvicPain = 'symptom_pelvic_pain';
  static const vaginalDryness = 'symptom_vaginal_dryness';
  static const generalizedBodyAche = 'symptom_generalized_body_ache';
  static const breastPain = 'symptom_breast_pain';

  static const all = <String>[
    coughing, chestTightnessOrPain, shortnessOfBreath, rapidHeartbeat, skippedHeartbeat,
    fatigue, dizziness, abdominalCramps, bloating, constipation, diarrhea, heartburn,
    nausea, vomiting, appetiteChanges, acne, drySkin, hairLoss, hotFlashes, nightSweats,
    chills, fever, headache, fainting, moodChanges, lowerBackPain, sleepChanges,
    bladderIncontinence, memoryLapse, lossOfSmell, lossOfTaste, runnyNose, soreThroat,
    sinusCongestion, wheezing, pelvicPain, vaginalDryness, generalizedBodyAche, breastPain,
  ];
}

class FlutterHealth {
  /// 삼성헬스(Android) / Apple Health(iOS) 가용성 확인.
  /// Android: API 29+ & 삼성헬스 앱 설치 시 true.
  /// iOS: HealthDataAvailable 시 true (iPad는 false).
  Future<bool> isAvailable() => FlutterHealthPlatform.instance.isAvailable();

  /// SDK 연결. Android는 HealthDataStore 초기화, iOS는 즉시 true.
  Future<bool> connect() => FlutterHealthPlatform.instance.connect();

  /// 연결 해제.
  Future<void> disconnect() => FlutterHealthPlatform.instance.disconnect();

  /// 권한이 하나 이상 부여되어 있는지 확인.
  Future<bool> isPermissionGranted() => FlutterHealthPlatform.instance.isPermissionGranted();

  /// 삼성헬스 / HealthKit 권한 UI를 표시. 일부만 허용해도 true 반환.
  Future<bool> requestPermission() => FlutterHealthPlatform.instance.requestPermission();

  /// [from]~[to] 구간의 5분 건강 지표 (metric) 레코드를 반환.
  /// 데이터 없으면 null.
  Future<HealthRecord?> queryMetric(DateTime from, DateTime to) =>
      FlutterHealthPlatform.instance.queryMetric(from, to);

  /// [since]~[to] 구간에 종료된 수면 세션 목록을 반환.
  Future<List<HealthRecord>> queryEndedSleepSessions(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryEndedSleepSessions(since, to);

  /// [since]~[to] 구간에 종료된 운동 세션 목록을 반환.
  Future<List<HealthRecord>> queryEndedExerciseSessions(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryEndedExerciseSessions(since, to);

  /// [hourStart]~[hourEnd] 구간의 시간별 집계 (hourly_summary) 레코드를 반환.
  Future<HealthRecord?> queryHourlySummary(DateTime hourStart, DateTime hourEnd) =>
      FlutterHealthPlatform.instance.queryHourlySummary(hourStart, hourEnd);

  /// [date] 하루의 일별 집계 (daily_summary) 레코드를 반환.
  Future<HealthRecord?> queryDailySummary(DateTime date) =>
      FlutterHealthPlatform.instance.queryDailySummary(date);

  /// [since]~[to] 구간 내 모든 체중 (weight) 측정 목록을 시간순으로 반환.
  Future<List<HealthRecord>> queryWeights(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryWeights(since, to);

  /// [since]~[to] 구간 내 모든 혈당 (blood_glucose) 측정 목록.
  Future<List<HealthRecord>> queryBloodGlucose(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBloodGlucose(since, to);

  /// [since]~[to] 구간 내 모든 혈압 (blood_pressure) 측정 목록.
  Future<List<HealthRecord>> queryBloodPressure(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBloodPressure(since, to);

  /// iOS 전용. [since]~[to] 구간의 인슐린 투여 (insulin_delivery) — 양(IU) + basal/bolus reason.
  /// Android(Samsung) 는 SDK 가 reason 을 안 줘서 항상 빈 리스트. (혈당 레코드 안의 INSULIN_INJECTED 양만 받고 싶으면 [queryBloodGlucose] 사용.)
  Future<List<HealthRecord>> queryInsulinDelivery(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryInsulinDelivery(since, to);

  /// [since]~[to] 구간 내 모든 영양 (nutrition) 기록.
  Future<List<HealthRecord>> queryNutrition(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryNutrition(since, to);

  /// [since]~[to] 구간 내 모든 수분 섭취 (water_intake) 기록.
  Future<List<HealthRecord>> queryWaterIntake(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryWaterIntake(since, to);

  /// [since]~[to] 구간 내 모든 수면 무호흡 (sleep_apnea) 기록.
  Future<List<HealthRecord>> querySleepApnea(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.querySleepApnea(since, to);

  /// [since]~[to] 구간 내 모든 계단 (floors_climbed) 기록.
  Future<List<HealthRecord>> queryFloorsClimbed(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryFloorsClimbed(since, to);

  /// [since]~[to] 구간의 일별 에너지 점수 (energy_score) 목록.
  Future<List<HealthRecord>> queryEnergyScore(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryEnergyScore(since, to);

  /// [since]~[to] 구간 내 모든 체온 (body_temperature) 측정 목록.
  Future<List<HealthRecord>> queryBodyTemperature(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryBodyTemperature(since, to);

  /// [since]~[to] 구간 내 모든 피부 온도 (skin_temperature) 측정 목록.
  Future<List<HealthRecord>> querySkinTemperature(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.querySkinTemperature(since, to);

  /// [since]~[to] 구간 내 부정맥 알림 (heart_rhythm) 기록.
  Future<List<HealthRecord>> queryIrregularHeartRhythm(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryIrregularHeartRhythm(since, to);

  /// [type] (예: [QuantityType.respiratoryRate]) 의 [since]~[to] 구간 단순 측정값 목록.
  /// 단위는 [QuantityType] 약속을 따른다. 미지원 타입/플랫폼은 빈 리스트.
  Future<List<HealthRecord>> queryQuantity(String type, DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryQuantity(type, since, to);

  /// [type] (예: [CategoryType.mindful]) 의 [since]~[to] 구간 지속시간형 기록 목록.
  Future<List<HealthRecord>> queryCategory(String type, DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryCategory(type, since, to);

  /// [type] (예: [SymptomType.coughing]) 의 [since]~[to] 구간 증상 기록 목록.
  Future<List<HealthRecord>> querySymptom(String type, DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.querySymptom(type, since, to);

  /// [since]~[to] 구간 생리주기 흐름 (menstrual_flow) 기록 목록.
  Future<List<HealthRecord>> queryMenstrualFlow(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryMenstrualFlow(since, to);

  /// [since]~[to] 구간 마음 상태 (state_of_mind, iOS 17+) 기록 목록.
  Future<List<HealthRecord>> queryStateOfMind(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryStateOfMind(since, to);

  /// [since]~[to] 구간 심전도 (ecg) 기록 목록.
  Future<List<HealthRecord>> queryEcg(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryEcg(since, to);

  /// [type] (예: [ReproductiveType.ovulationTest]) 의 [since]~[to] 구간 생리주기 상세 기록 목록.
  Future<List<HealthRecord>> queryReproductive(String type, DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryReproductive(type, since, to);

  /// [since]~[to] 구간 청력검사 (audiogram) 기록 목록.
  Future<List<HealthRecord>> queryAudiogram(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryAudiogram(since, to);

  /// [since]~[to] 구간 심박 시리즈 (heartbeat_series) 기록 목록.
  Future<List<HealthRecord>> queryHeartbeatSeries(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryHeartbeatSeries(since, to);

  /// [since]~[to] 구간 운동 경로 (workout_route, GPS) 기록 목록.
  Future<List<HealthRecord>> queryWorkoutRoutes(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryWorkoutRoutes(since, to);

  /// [type] (예: [ClinicalType.medication]) 의 [since]~[to] 구간 임상기록 목록.
  /// 'health-records' entitlement + Portal capability 가 없으면 빈 리스트.
  Future<List<HealthRecord>> queryClinical(String type, DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryClinical(type, since, to);

  /// [since]~[to] 구간 복약 이벤트 (medication, iOS 26+) 목록. 그 외 플랫폼/버전은 빈 리스트.
  Future<List<HealthRecord>> queryMedication(DateTime since, DateTime to) =>
      FlutterHealthPlatform.instance.queryMedication(since, to);
}

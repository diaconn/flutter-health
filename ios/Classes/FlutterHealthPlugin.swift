import Flutter
import HealthKit

public class FlutterHealthPlugin: NSObject, FlutterPlugin {

    private let client = HealthKitClient()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_health", binaryMessenger: registrar.messenger())
        let instance = FlutterHealthPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(HKHealthStore.isHealthDataAvailable())

        case "connect":
            // iOS: HealthKit is always "connected" once available; permission is requested separately.
            result(HKHealthStore.isHealthDataAvailable())

        case "disconnect":
            result(nil)

        case "isPermissionGranted":
            Task {
                let granted = await client.isPermissionGranted()
                DispatchQueue.main.async { result(granted) }
            }

        case "requestPermission":
            Task {
                do {
                    let granted = try await client.requestPermission()
                    DispatchQueue.main.async { result(granted) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "HK_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "queryStepsDaily":
            guard let args    = call.arguments as? [String: Any],
                  let dateStr = args["date"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "date required", details: nil))
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            guard let date = formatter.date(from: dateStr) else {
                result(FlutterError(code: "INVALID_ARGS", message: "date format must be yyyy-MM-dd", details: nil))
                return
            }
            Task {
                let records = await client.queryStepsDaily(date: date)
                DispatchQueue.main.async { result(records.map { $0.toDictionary() }) }
            }

        case "queryEndedSleepSessions":
            guard let args = call.arguments as? [String: Any],
                  let sinceMs = args["since"] as? Int,
                  let toMs    = args["to"]    as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "since/to required", details: nil))
                return
            }
            let since = Date(timeIntervalSince1970: Double(sinceMs) / 1000.0)
            let to    = Date(timeIntervalSince1970: Double(toMs)    / 1000.0)
            Task {
                do {
                    let records = try await client.queryEndedSleepSessions(since: since, to: to)
                    DispatchQueue.main.async { result(records.map { $0.toDictionary() }) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "HK_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "queryEndedExerciseSessions":
            guard let args = call.arguments as? [String: Any],
                  let sinceMs = args["since"] as? Int,
                  let toMs    = args["to"]    as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "since/to required", details: nil))
                return
            }
            let since = Date(timeIntervalSince1970: Double(sinceMs) / 1000.0)
            let to    = Date(timeIntervalSince1970: Double(toMs)    / 1000.0)
            Task {
                do {
                    let records = try await client.queryEndedExerciseSessions(since: since, to: to)
                    DispatchQueue.main.async { result(records.map { $0.toDictionary() }) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "HK_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "queryHourlySummary":
            guard let args      = call.arguments as? [String: Any],
                  let startMs   = args["hourStart"] as? Int,
                  let endMs     = args["hourEnd"]   as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "hourStart/hourEnd required", details: nil))
                return
            }
            let hourStart = Date(timeIntervalSince1970: Double(startMs) / 1000.0)
            let hourEnd   = Date(timeIntervalSince1970: Double(endMs)   / 1000.0)
            Task {
                do {
                    let record = try await client.queryHourlySummary(from: hourStart, to: hourEnd)
                    DispatchQueue.main.async { result(record?.toDictionary()) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "HK_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "queryWeights":
            guard let args = call.arguments as? [String: Any],
                  let sinceMs = args["since"] as? Int,
                  let toMs    = args["to"]    as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "since/to required", details: nil))
                return
            }
            let since = Date(timeIntervalSince1970: Double(sinceMs) / 1000.0)
            let to    = Date(timeIntervalSince1970: Double(toMs)    / 1000.0)
            Task {
                let records = await client.queryWeights(since: since, to: to)
                DispatchQueue.main.async { result(records.map { $0.toDictionary() }) }
            }

        case "queryDailySummary":
            guard let args    = call.arguments as? [String: Any],
                  let dateStr = args["date"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "date required", details: nil))
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            guard let date = formatter.date(from: dateStr) else {
                result(FlutterError(code: "INVALID_ARGS", message: "date format must be yyyy-MM-dd", details: nil))
                return
            }
            Task {
                do {
                    let record = try await client.queryDailySummary(date: date)
                    DispatchQueue.main.async { result(record?.toDictionary()) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "HK_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "queryHeartRate", "querySteps", "queryDistance", "queryCalories",
             "queryBloodGlucose", "queryBloodPressure", "queryInsulinDelivery", "queryNutrition", "queryWaterIntake",
             "queryHeight":
            guard let args = call.arguments as? [String: Any],
                  let sinceMs = args["since"] as? Int,
                  let toMs    = args["to"]    as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "since/to required", details: nil))
                return
            }
            let since = Date(timeIntervalSince1970: Double(sinceMs) / 1000.0)
            let to    = Date(timeIntervalSince1970: Double(toMs)    / 1000.0)
            let method = call.method
            Task {
                let records: [HealthRecord]
                switch method {
                case "queryHeartRate":            records = await client.queryHeartRate(since: since, to: to)
                case "querySteps":                records = await client.querySteps(since: since, to: to)
                case "queryDistance":             records = await client.queryDistance(since: since, to: to)
                case "queryCalories":             records = await client.queryCalories(since: since, to: to)
                case "queryBloodGlucose":         records = await client.queryBloodGlucose(since: since, to: to)
                case "queryBloodPressure":        records = await client.queryBloodPressure(since: since, to: to)
                case "queryInsulinDelivery":      records = await client.queryInsulinDelivery(since: since, to: to)
                case "queryNutrition":            records = await client.queryNutrition(since: since, to: to)
                case "queryWaterIntake":          records = await client.queryWaterIntake(since: since, to: to)
                case "queryHeight":               records = await client.queryHeight(since: since, to: to)
                default:                          records = []
                }
                DispatchQueue.main.async { result(records.map { $0.toDictionary() }) }
            }

        case "queryChanges":
            guard let args     = call.arguments as? [String: Any],
                  let dataType = args["dataType"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "dataType required", details: nil))
                return
            }
            // since/to 는 기준선(첫 호출) predicate 범위. 미지정 시 최근 7일.
            let now   = Date()
            let since = (args["since"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000.0) } ?? now.addingTimeInterval(-7 * 24 * 3600)
            let to    = (args["to"]    as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000.0) } ?? now
            let token = args["token"] as? String
            Task {
                let (recs, deleted, newToken) = await client.queryChanges(dataType: dataType, since: since, to: to, anchorToken: token)
                var out: [String: Any] = [
                    "upserted": recs.map { $0.toDictionary() },
                    "deletedUids": deleted,
                ]
                if let newToken = newToken { out["token"] = newToken }
                DispatchQueue.main.async { result(out) }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

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

        case "queryMetric":
            guard let args = call.arguments as? [String: Any],
                  let fromMs = args["from"] as? Int,
                  let toMs = args["to"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "from/to required", details: nil))
                return
            }
            let from = Date(timeIntervalSince1970: Double(fromMs) / 1000.0)
            let to   = Date(timeIntervalSince1970: Double(toMs)   / 1000.0)
            Task {
                do {
                    let record = try await client.queryMetric(from: from, to: to)
                    DispatchQueue.main.async { result(record?.toDictionary()) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "HK_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
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
                    let record = try await client.queryHourlySummary(hourStart: hourStart, hourEnd: hourEnd)
                    DispatchQueue.main.async { result(record?.toDictionary()) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "HK_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
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

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

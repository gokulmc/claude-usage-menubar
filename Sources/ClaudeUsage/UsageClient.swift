import Foundation
import Security

struct UsageWindow {
    let utilization: Double
    let resetsAt: Date?
}

struct ModelWeeklyLimit {
    let modelName: String
    let utilization: Double
    let resetsAt: Date?
}

struct UsageSnapshot {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow
    // Per-model weekly caps (e.g. Sonnet, Fable) -- the API only includes an
    // entry here for models that currently have their own scoped limit, so
    // this can be empty or contain any subset of models.
    let modelWeeklyLimits: [ModelWeeklyLimit]
}

enum UsageError: Error {
    case noCredentials
    case badCredentials
    case unauthorized
    case network(Error)
    case decode
}

final class UsageClient {

    private let keychainService = "Claude Code-credentials"
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // Every SecItemCopyMatching call against this self-signed, non-Apple-signed
    // app is a Keychain "partition" check that macOS periodically re-prompts
    // for (roughly every 15-65 min observed), independent of the earlier
    // "Always Allow" choice -- that grant simply doesn't persist reliably for
    // non-Developer-ID-signed code. Reading the token once and reusing it
    // across polls (instead of re-reading on every 5-min timer fire) cuts
    // Keychain touches from "every poll, forever" down to "once per launch,
    // plus whenever the cached token actually stops working" -- which is by
    // far the biggest source of unnecessary prompts.
    private var cachedToken: String?

    func fetchUsage(completion: @escaping (Result<UsageSnapshot, UsageError>) -> Void) {
        let token: String
        if let cachedToken {
            token = cachedToken
        } else if let fresh = readAccessToken() {
            cachedToken = fresh
            token = fresh
        } else {
            completion(.failure(.noCredentials))
            return
        }

        performRequest(token: token) { [weak self] result in
            switch result {
            case .success(let snapshot):
                completion(.success(snapshot))
            case .failure(.unauthorized):
                // Cached token stopped working (rotated or revoked) -- drop it
                // and re-read from the Keychain once.
                guard let self else {
                    completion(.failure(.unauthorized))
                    return
                }
                self.cachedToken = nil
                guard let retryToken = self.readAccessToken(), retryToken != token else {
                    completion(.failure(.unauthorized))
                    return
                }
                self.cachedToken = retryToken
                self.performRequest(token: retryToken, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func performRequest(token: String, completion: @escaping (Result<UsageSnapshot, UsageError>) -> Void) {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error)))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                completion(.failure(.unauthorized))
                return
            }
            guard let data else {
                completion(.failure(.decode))
                return
            }
            guard let snapshot = Self.parse(data: data) else {
                completion(.failure(.decode))
                return
            }
            completion(.success(snapshot))
        }
        task.resume()
    }

    private static func parse(data: Data) -> UsageSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let fiveHourDict = json["five_hour"] as? [String: Any],
              let sevenDayDict = json["seven_day"] as? [String: Any] else {
            return nil
        }
        guard let fiveHour = parseWindow(fiveHourDict),
              let sevenDay = parseWindow(sevenDayDict) else {
            return nil
        }
        let modelWeeklyLimits = parseModelWeeklyLimits(json["limits"] as? [[String: Any]] ?? [])
        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay, modelWeeklyLimits: modelWeeklyLimits)
    }

    private static func parseModelWeeklyLimits(_ limits: [[String: Any]]) -> [ModelWeeklyLimit] {
        limits.compactMap { entry -> ModelWeeklyLimit? in
            guard entry["kind"] as? String == "weekly_scoped",
                  let percent = entry["percent"] as? Double,
                  let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let modelName = model["display_name"] as? String else {
                return nil
            }
            var resetsAt: Date? = nil
            if let resetsAtString = entry["resets_at"] as? String {
                resetsAt = ISO8601DateFormatter.usageFormatter.date(from: resetsAtString)
            }
            return ModelWeeklyLimit(modelName: modelName, utilization: percent, resetsAt: resetsAt)
        }
    }

    private static func parseWindow(_ dict: [String: Any]) -> UsageWindow? {
        guard let utilization = dict["utilization"] as? Double else {
            return nil
        }
        var resetsAt: Date? = nil
        if let resetsAtString = dict["resets_at"] as? String {
            resetsAt = ISO8601DateFormatter.usageFormatter.date(from: resetsAtString)
        }
        return UsageWindow(utilization: utilization, resetsAt: resetsAt)
    }

    private func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String else {
            return nil
        }

        return accessToken
    }
}

extension ISO8601DateFormatter {
    static let usageFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

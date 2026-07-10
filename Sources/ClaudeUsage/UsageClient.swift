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

    // Claude Code's own item -- reading it is a *cross-app* Keychain access,
    // which is what triggers macOS's "wants to use your confidential
    // information" prompt, and (for this self-signed, non-Apple-signed app)
    // that prompt keeps resurfacing periodically no matter what.
    private let sourceKeychainService = "Claude Code-credentials"

    // An item this app creates and owns. Reading back an item you created
    // yourself is *never* prompted by macOS, signed or not -- the whole
    // cross-app confirmation dance only applies to reading someone else's
    // item. Keeping our own persisted copy here means normal operation never
    // touches Claude Code's item at all, so it never prompts in the common
    // case. Same OS-level Keychain encryption as any other item -- this
    // isn't a weaker storage mechanism, just one we don't need permission
    // from another app to read.
    private let cacheKeychainService = "com.gokul.claude-usage.token-cache"

    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    // In-memory copy so a single run doesn't even touch the Keychain twice.
    private var cachedToken: String?

    func fetchUsage(completion: @escaping (Result<UsageSnapshot, UsageError>) -> Void) {
        let token: String
        if let cachedToken {
            token = cachedToken
        } else if let persisted = readOwnCachedToken() {
            // Silent: this is our own item, never prompts.
            cachedToken = persisted
            token = persisted
        } else if let fresh = readAccessToken(service: sourceKeychainService) {
            // First-ever run (or our cache got cleared): this one may prompt.
            cachedToken = fresh
            persistOwnCachedToken(fresh)
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
                // Our cached token (in-memory or persisted) stopped working --
                // it's genuinely stale, so re-sync from Claude Code's item.
                // This is the only path that can still prompt.
                guard let self else {
                    completion(.failure(.unauthorized))
                    return
                }
                self.cachedToken = nil
                guard let retryToken = self.readAccessToken(service: self.sourceKeychainService), retryToken != token else {
                    completion(.failure(.unauthorized))
                    return
                }
                self.cachedToken = retryToken
                self.persistOwnCachedToken(retryToken)
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

    /// Reads Claude Code's OAuth token from its own Keychain item. Cross-app
    /// access -- macOS may show its confirmation prompt here.
    private func readAccessToken(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    /// Reads our own persisted copy of the token. Same-app access -- never prompts.
    private func readOwnCachedToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheKeychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    /// Writes our own persisted copy of the token. Same-app access -- never prompts.
    private func persistOwnCachedToken(_ token: String) {
        let data = Data(token.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheKeychainService
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

extension ISO8601DateFormatter {
    static let usageFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

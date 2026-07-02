import Foundation
import Security

struct UsageWindow {
    let utilization: Double
    let resetsAt: Date?
}

struct UsageSnapshot {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow
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

    func fetchUsage(completion: @escaping (Result<UsageSnapshot, UsageError>) -> Void) {
        guard let token = readAccessToken() else {
            completion(.failure(.noCredentials))
            return
        }
        performRequest(token: token) { [weak self] result in
            switch result {
            case .success(let snapshot):
                completion(.success(snapshot))
            case .failure(.unauthorized):
                // Token may have rotated; re-read once and retry.
                guard let self, let retryToken = self.readAccessToken(), retryToken != token else {
                    completion(.failure(.unauthorized))
                    return
                }
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
        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay)
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

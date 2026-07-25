import Foundation

struct SunTimesWindow {
    let yesterdaySunrise: Date
    let yesterdaySunset: Date
    let todaySunrise: Date
    let todaySunset: Date
    let tomorrowSunrise: Date
    let tomorrowSunset: Date
}

enum SunTimesAPIError: Error {
    case badURL
    case http(Int)
    case decode(String)
    case noData
}

final class SunTimesAPIClient {

    // Matches the iOS app — note the double slash in the path is intentional.
    static let baseURL = "https://paragonday.herokuapp.com/api/v1/"

    func fetch(latitude: Double, longitude: Double,
               completion: @escaping (Result<SunTimesWindow, Error>) -> Void) {

        let urlString = "\(Self.baseURL)/sunrise-sunset/suntime?lat=\(latitude)&lng=\(longitude)"
        guard let url = URL(string: urlString) else {
            completion(.failure(SunTimesAPIError.badURL))
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(error)); return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                completion(.failure(SunTimesAPIError.http(http.statusCode))); return
            }
            guard let data = data else {
                completion(.failure(SunTimesAPIError.noData)); return
            }

            do {
                let win = try Self.decode(data)
                completion(.success(win))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private static func decode(_ data: Data) throws -> SunTimesWindow {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let window = json["window"] as? [String: Any],
              let yesterday = window["yesterday"] as? [String: Any],
              let today = window["today"] as? [String: Any],
              let tomorrow = window["tomorrow"] as? [String: Any] else {
            throw SunTimesAPIError.decode("missing window/today/tomorrow keys")
        }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func date(_ d: [String: Any], _ key: String) throws -> Date {
            guard let s = d[key] as? String, let parsed = f.date(from: s) else {
                throw SunTimesAPIError.decode("bad date for \(key)")
            }
            return parsed
        }

        return SunTimesWindow(
            yesterdaySunrise: try date(yesterday, "sunrise"),
            yesterdaySunset:  try date(yesterday, "sunset"),
            todaySunrise:     try date(today, "sunrise"),
            todaySunset:      try date(today, "sunset"),
            tomorrowSunrise:  try date(tomorrow, "sunrise"),
            tomorrowSunset:   try date(tomorrow, "sunset")
        )
    }
}

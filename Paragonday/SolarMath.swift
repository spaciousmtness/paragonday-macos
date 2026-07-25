import Foundation

// Faithful port of SunCalc's Meeus-derived sunrise/sunset algorithm.
// https://github.com/mourner/suncalc — MIT licensed reference.
// Targets ~±1 minute accuracy.

enum SolarMath {

    // -0.833° = -34' refraction + -16' solar semidiameter.
    static let horizonAltitudeDegrees: Double = -0.833

    static let polarLatitudeDegrees: Double = 66.5641

    enum Result {
        case times(sunrise: Date, sunset: Date)
        case polar
    }

    // MARK: - Public

    /// Returns sunrise and sunset for the given civil day (in `timeZone`)
    /// at the given latitude/longitude.
    static func sunriseSunset(on date: Date,
                              latitude: Double,
                              longitude: Double,
                              timeZone: TimeZone = .current) -> Result {

        // Use local noon of the requested civil day as the reference instant.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        guard let localNoon = cal.date(from: comps) else { return .polar }

        let lw = rad * -longitude
        let phi = rad * latitude

        let d = toDays(localNoon)
        let n = (d - j0 - lw / (2 * .pi)).rounded()  // integer Julian cycle
        let ds = approxTransit(0, lw: lw, n: n)

        let M = solarMeanAnomaly(ds)
        let L = eclipticLongitude(M)

        let dec = declination(L)

        let jNoon = solarTransit(ds: ds, M: M, L: L)

        let h = rad * horizonAltitudeDegrees
        let cosH = (sin(h) - sin(phi) * sin(dec)) / (cos(phi) * cos(dec))
        if cosH > 1.0 || cosH < -1.0 {
            return .polar
        }
        let H = acos(cosH)

        let jSet = solarTransit(ds: ds + H / (2 * .pi), M: M, L: L)
        let jRise = jNoon - (jSet - jNoon)

        return .times(sunrise: fromJulian(jRise),
                      sunset: fromJulian(jSet))
    }

    // MARK: - SunCalc primitives

    private static let rad = Double.pi / 180.0
    private static let j0: Double = 0.0009

    private static let j1970: Double = 2440588.0
    private static let j2000: Double = 2451545.0

    private static let earthObliquity = rad * 23.4397
    private static let perihelion = rad * 102.9372

    private static func toJulian(_ date: Date) -> Double {
        return date.timeIntervalSince1970 / 86400.0 - 0.5 + j1970
    }

    private static func fromJulian(_ j: Double) -> Date {
        return Date(timeIntervalSince1970: (j + 0.5 - j1970) * 86400.0)
    }

    private static func toDays(_ date: Date) -> Double {
        return toJulian(date) - j2000
    }

    private static func approxTransit(_ Ht: Double, lw: Double, n: Double) -> Double {
        return j0 + (Ht + lw) / (2 * .pi) + n
    }

    private static func solarMeanAnomaly(_ ds: Double) -> Double {
        return rad * (357.5291 + 0.98560028 * ds)
    }

    private static func eclipticLongitude(_ M: Double) -> Double {
        let C = rad * (1.9148 * sin(M)
                     + 0.0200 * sin(2 * M)
                     + 0.0003 * sin(3 * M))
        return M + C + perihelion + .pi
    }

    private static func declination(_ L: Double) -> Double {
        return asin(sin(L) * sin(earthObliquity))
    }

    private static func solarTransit(ds: Double, M: Double, L: Double) -> Double {
        return j2000 + ds + 0.0053 * sin(M) - 0.0069 * sin(2 * L)
    }
}

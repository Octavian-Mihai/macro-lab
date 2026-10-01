import Foundation
import SwiftUI
import Combine

// MARK: - Unit System

enum UnitSystem: String, Codable, CaseIterable {
    case metric   = "Metric (kg, cm)"
    case imperial = "Imperial (lbs, ft/in)"
}

// MARK: - Unit Manager (ObservableObject so views react to changes)

class UnitManager: ObservableObject {
    static let shared = UnitManager()

    @Published var system: UnitSystem {
        didSet { UserDefaults.standard.set(system.rawValue, forKey: "unitSystem") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "unitSystem") ?? ""
        self.system = UnitSystem(rawValue: saved) ?? .metric
    }

    var isMetric: Bool { system == .metric }

    // MARK: - Weight

    var weightUnit: String { isMetric ? "kg" : "lbs" }

    /// Display kg value in user's preferred unit
    func displayWeight(_ kg: Double) -> Double {
        isMetric ? kg : kg * 2.20462
    }

    /// Convert user-entered value back to kg for storage
    func toKg(_ value: Double) -> Double {
        isMetric ? value : value / 2.20462
    }

    func weightString(_ kg: Double, decimals: Int = 1) -> String {
        let val = displayWeight(kg)
        return String(format: "%.\(decimals)f \(weightUnit)", val)
    }

    // MARK: - Height

    var heightUnit: String { isMetric ? "cm" : "ft / in" }

    /// Display cm value in user's preferred unit (returns string)
    func displayHeight(_ cm: Double) -> String {
        if isMetric {
            return String(format: "%.0f cm", cm)
        } else {
            let totalInches = cm / 2.54
            let feet = Int(totalInches / 12)
            let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)′ \(inches)″"
        }
    }

    /// Convert height to cm for storage
    func toCm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * 2.54
    }

    // MARK: - Height slider helpers

    var heightRangeMin: Double { isMetric ? 140 : 55 }   // cm or inches
    var heightRangeMax: Double { isMetric ? 220 : 87 }

    func heightSliderValue(from cm: Double) -> Double {
        isMetric ? cm : cm / 2.54
    }

    func cmFromSlider(_ value: Double) -> Double {
        isMetric ? value : value * 2.54
    }

    // MARK: - Weight slider helpers

    var weightRangeMin: Double { isMetric ? 30 : 66 }
    var weightRangeMax: Double { isMetric ? 250 : 551 }

    func weightSliderValue(from kg: Double) -> Double {
        displayWeight(kg)
    }

    func kgFromSlider(_ value: Double) -> Double {
        toKg(value)
    }
}

// MARK: - Environment key for convenience

private struct UnitManagerKey: EnvironmentKey {
    static let defaultValue = UnitManager.shared
}

extension EnvironmentValues {
    var units: UnitManager {
        get { self[UnitManagerKey.self] }
        set { self[UnitManagerKey.self] = newValue }
    }
}

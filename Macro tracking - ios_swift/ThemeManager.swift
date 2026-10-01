import SwiftUI
import Combine

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Codable {
    case blue       = "Blue"
    case indigo     = "Indigo"
    case purple     = "Purple"
    case pink       = "Pink"
    case red        = "Red"
    case orange     = "Orange"
    case yellow     = "Yellow"
    case green      = "Green"
    case teal       = "Teal"
    case mint       = "Mint"
    case cyan       = "Cyan"
    case brown      = "Brown"

    var color: Color {
        switch self {
        case .blue:   return Color(red: 0.20, green: 0.47, blue: 0.96)
        case .indigo: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .purple: return Color(red: 0.59, green: 0.24, blue: 0.82)
        case .pink:   return Color(red: 0.96, green: 0.25, blue: 0.55)
        case .red:    return Color(red: 0.91, green: 0.22, blue: 0.20)
        case .orange: return Color(red: 0.96, green: 0.53, blue: 0.09)
        case .yellow: return Color(red: 0.88, green: 0.70, blue: 0.05)
        case .green:  return Color(red: 0.20, green: 0.68, blue: 0.35)
        case .teal:   return Color(red: 0.11, green: 0.62, blue: 0.62)
        case .mint:   return Color(red: 0.00, green: 0.73, blue: 0.61)
        case .cyan:   return Color(red: 0.12, green: 0.65, blue: 0.85)
        case .brown:  return Color(red: 0.59, green: 0.44, blue: 0.27)
        }
    }

    var icon: String {
        switch self {
        case .blue:   return "drop.fill"
        case .indigo: return "star.fill"
        case .purple: return "bolt.fill"
        case .pink:   return "heart.fill"
        case .red:    return "flame.fill"
        case .orange: return "sun.max.fill"
        case .yellow: return "sparkles"
        case .green:  return "leaf.fill"
        case .teal:   return "waveform"
        case .mint:   return "wind"
        case .cyan:   return "bubble.fill"
        case .brown:  return "mountain.2.fill"
        }
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: "appTheme")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appTheme") ?? ""
        self.current = AppTheme(rawValue: saved) ?? .blue
    }

    var accentColor: Color { current.color }
}

// MARK: - Environment Key

private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue = ThemeManager.shared
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}

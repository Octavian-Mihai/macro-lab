import SwiftUI
import SwiftData

@main
struct MacroTrackerApp: App {
    @StateObject private var units  = UnitManager.shared
    @StateObject private var health = HealthKitManager.shared
    @StateObject private var theme  = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(units)
                .environmentObject(health)
                .environmentObject(theme)
                .environment(\.units, units)
                .environment(\.theme, theme)
                .tint(theme.accentColor)
        }
        .modelContainer(for: [UserProfile.self, FoodEntry.self, WeightEntry.self])
    }
}

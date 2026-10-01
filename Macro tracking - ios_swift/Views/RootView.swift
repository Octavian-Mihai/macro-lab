import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]
    @AppStorage("colorScheme") private var colorSchemeString: String = "system"

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeString {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainTabView(profile: profile)
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }
}

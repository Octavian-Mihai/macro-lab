import SwiftUI
import SwiftData


@ViewBuilder
private func macroChip(title: String, value: String, color: Color) -> some View {
    VStack(spacing: 4) {
        Text(value)
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .monospacedDigit()

        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(Color(.secondarySystemGroupedBackground))
    .cornerRadius(12)
}

struct SettingsView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.units) private var units
    @EnvironmentObject private var unitManager: UnitManager
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var name: String = ""
    @State private var age: Int = 0
    @State private var sex: Sex = .male
    @State private var heightCm: Double = 170
    @State private var goalWeightKg: Double = 70
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var goal: Goal = .lose
    @State private var showResetAlert = false
    @State private var showResetProfileAlert = false
    @State private var saved = false
    @AppStorage("colorScheme") private var colorSchemeString: String = "system"

    // Macro colours (stored as encoded float strings)
    @AppStorage("colorCal")  private var colorCalHex:  String = MacroColorManager.defaultCalHex
    @AppStorage("colorProt") private var colorProtHex: String = MacroColorManager.defaultProtHex
    @AppStorage("colorCarb") private var colorCarbHex: String = MacroColorManager.defaultCarbHex
    @AppStorage("colorFat")  private var colorFatHex:  String = MacroColorManager.defaultFatHex

    // Custom accent colour (nil = using a preset AppTheme)
    @State private var customAccentColor: Color? = {
        if let s = UserDefaults.standard.string(forKey: "customAccentEncoded") {
            return Color.fromEncoded(s)
        }
        return nil
    }()

    @Query private var allFoodEntries: [FoodEntry]
    @Query private var allWeightEntries: [WeightEntry]

    var body: some View {
        NavigationStack {
            Form {
                // Units
                Section("Units") {
                    Picker("Unit System", selection: $unitManager.system) {
                        ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                // Appearance
                Section("Appearance") {
                    Picker("Color Scheme", selection: $colorSchemeString) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                // App accent colour
                Section("Accent Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                        // 11 preset swatches (all cases except the last one)
                        ForEach(AppTheme.allCases.dropLast(), id: \.self) { t in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    themeManager.current = t
                                    customAccentColor = nil
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(t.color)
                                        .frame(width: 40, height: 40)
                                    if themeManager.current == t && customAccentColor == nil {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: 2.5)
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        // + button opens the full colour picker
                        ColorPicker("", selection: Binding(
                            get: { customAccentColor ?? Color.accentColor },
                            set: { picked in
                                customAccentColor = picked
                                // Store as encoded string in UserDefaults
                                UserDefaults.standard.set(picked.encodedString, forKey: "customAccentEncoded")
                            }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .overlay {
                            ZStack {
                                Circle()
                                    .fill(customAccentColor ?? Color(.systemGray4))
                                    .frame(width: 40, height: 40)
                                if customAccentColor == nil {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2.5)
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    }
                    .padding(.vertical, 6)

                    if customAccentColor == nil {
                        HStack {
                            Image(systemName: themeManager.current.icon)
                                .foregroundStyle(themeManager.accentColor)
                            Text(themeManager.current.rawValue)
                                .foregroundStyle(themeManager.accentColor)
                                .bold()
                        }
                    } else {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                                .foregroundStyle(customAccentColor!)
                            Text("Custom")
                                .foregroundStyle(customAccentColor!)
                                .bold()
                            Spacer()
                            Button("Reset") {
                                customAccentColor = nil
                                UserDefaults.standard.removeObject(forKey: "customAccentEncoded")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // Macro colours
                Section {
                    macroSwatchRow(label: "Calories", icon: "flame.fill",
                                   encoded: $colorCalHex,  defaultEncoded: MacroColorManager.defaultCalHex)
                    macroSwatchRow(label: "Protein",  icon: "bolt.fill",
                                   encoded: $colorProtHex, defaultEncoded: MacroColorManager.defaultProtHex)
                    macroSwatchRow(label: "Carbs",    icon: "leaf.fill",
                                   encoded: $colorCarbHex, defaultEncoded: MacroColorManager.defaultCarbHex)
                    macroSwatchRow(label: "Fat",      icon: "drop.fill",
                                   encoded: $colorFatHex,  defaultEncoded: MacroColorManager.defaultFatHex)
                } header: {
                    Text("Macro Colors")
                } footer: {
                    Text("These colors are used in the dashboard ring, circles, and bar views.")
                }

                // Apple Health
                Section {
                    if health.isAvailable {
                        if health.isAuthorized {
                            Label("Connected to Apple Health", systemImage: "heart.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                Task { await health.requestAuthorization() }
                            } label: {
                                Label("Connect Apple Health", systemImage: "heart.fill")
                            }
                        }
                    } else {
                        Text("Apple Health not available on this device.")
                            .foregroundStyle(.secondary)
                    }
                    if let err = health.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Sync your logged weight and calories to the Health app.")
                }

                Section("Profile") {
                    TextField("Name", text: $name)

                    Picker("Biological Sex", selection: $sex) {
                        ForEach(Sex.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }

                    Stepper("Age: \(age)", value: $age, in: 10...100)

                    LabeledContent("Height") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { units.heightSliderValue(from: heightCm) },
                                    set: { heightCm = units.cmFromSlider($0) }
                                ),
                                in: units.heightRangeMin...units.heightRangeMax,
                                step: 0.5
                            )
                            .frame(width: 120)
                            Text(units.displayHeight(heightCm)).monospacedDigit()
                        }
                    }
                }

                Section("Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(Goal.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }

                    LabeledContent("Goal Weight") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { units.weightSliderValue(from: goalWeightKg) },
                                    set: { goalWeightKg = units.kgFromSlider($0) }
                                ),
                                in: units.weightRangeMin...units.weightRangeMax,
                                step: 0.5
                            )
                            .frame(width: 120)
                            Text(units.weightString(goalWeightKg)).monospacedDigit()
                        }
                    }

                    Picker("Activity Level", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) {
                            Text($0.shortName).tag($0)
                        }
                    }
                }

                Section("Calorie Target") {
                    LabeledContent("TDEE (estimated)") {
                        Text(String(format: "%.0f kcal", profile.baseTDEE))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Current Adjusted Target") {
                        Text(String(format: "%.0f kcal", profile.adjustedTarget))
                            .bold()
                    }
                    Text("Your target auto-adjusts every 7 days based on your actual weight trend. No manual tweaking needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Save Changes") { saveChanges() }
                        .bold()
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(saved ? .green : Color.accentColor)

                    if saved {
                        Label("Saved!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    }
                }

                Section {
                    Button("Reset Profile", role: .destructive) { showResetProfileAlert = true }
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("Deletes your profile and calorie targets and takes you back to setup. Your food log and weight history are kept.")
                }

                Section {
                    Button("Reset All Data", role: .destructive) { showResetAlert = true }
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("This will delete all food logs, weight entries, and your profile. Cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadFromProfile() }
            .alert("Reset Profile?", isPresented: $showResetProfileAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Profile", role: .destructive) { resetProfile() }
            } message: {
                Text("Your profile and calorie targets will be deleted and you'll set them up again. Your food log and weight history stay.")
            }
            .alert("Reset All Data?", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { resetAllData() }
            } message: {
                Text("All food logs, weight entries, and your profile will be permanently deleted.")
            }
        }
    }

    // MARK: - Macro swatch row

    // A row of 5 preset colour dots + a + custom picker button
    private let macroPresets: [Color] = [
        Color(red: 1.00, green: 0.58, blue: 0.00), // amber
        Color(red: 0.00, green: 0.48, blue: 1.00), // blue
        Color(red: 0.20, green: 0.68, blue: 0.35), // green
        Color(red: 0.91, green: 0.22, blue: 0.20), // red
        Color(red: 0.59, green: 0.24, blue: 0.82), // purple
    ]

    @ViewBuilder
    private func macroSwatchRow(label: String, icon: String, encoded: Binding<String>, defaultEncoded: String) -> some View {
        let currentColor = Color.fromEncoded(encoded.wrappedValue)
        let isPreset = macroPresets.contains { sameColor($0, currentColor) }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(currentColor)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                Spacer()
                // Reset
                Button {
                    withAnimation { encoded.wrappedValue = defaultEncoded }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                // 5 preset swatches
                ForEach(macroPresets.indices, id: \.self) { i in
                    let c = macroPresets[i]
                    let selected = sameColor(c, currentColor)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            encoded.wrappedValue = c.encodedString
                        }
                    } label: {
                        ZStack {
                            Circle().fill(c).frame(width: 32, height: 32)
                            if selected {
                                Circle().strokeBorder(.white, lineWidth: 2).frame(width: 32, height: 32)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // + custom picker
                ColorPicker("", selection: Binding(
                    get: { currentColor },
                    set: { encoded.wrappedValue = $0.encodedString }
                ), supportsOpacity: false)
                .labelsHidden()
                .overlay {
                    ZStack {
                        Circle()
                            .fill(isPreset ? Color(.systemGray5) : currentColor)
                            .frame(width: 32, height: 32)
                        if isPreset {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 32, height: 32)
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }

    /// Rough colour equality (handles float imprecision in storage round-trips)
    private func sameColor(_ a: Color, _ b: Color) -> Bool {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: nil)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: nil)
        return abs(r1-r2) < 0.01 && abs(g1-g2) < 0.01 && abs(b1-b2) < 0.01
    }

    // MARK: - Helpers

    private func loadFromProfile() {
        name          = profile.name
        age           = profile.age
        sex           = profile.sex
        heightCm      = profile.heightCm
        goalWeightKg  = profile.goalWeightKg
        activityLevel = profile.activityLevel
        goal          = profile.goal
    }

    private func saveChanges() {
        profile.name          = name
        profile.age           = age
        profile.sex           = sex
        profile.heightCm      = heightCm
        profile.goalWeightKg  = goalWeightKg
        profile.activityLevel = activityLevel
        profile.goal          = goal
        profile.baseTDEE       = profile.calculateTDEE()
        profile.adjustedTarget = profile.calculateInitialTarget()
        try? modelContext.save()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }

    /// Removes only the profile; RootView then shows onboarding again. Logged data is untouched.
    private func resetProfile() {
        modelContext.delete(profile)
        try? modelContext.save()
    }

    private func resetAllData() {
        allFoodEntries.forEach   { modelContext.delete($0) }
        allWeightEntries.forEach { modelContext.delete($0) }
        modelContext.delete(profile)
        try? modelContext.save()
    }
}

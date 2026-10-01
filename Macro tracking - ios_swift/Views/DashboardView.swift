import SwiftUI
import SwiftData

// MARK: - Display Mode

enum CalorieDisplayMode: String, CaseIterable {
    case ring       = "Ring"
    case concentric = "Circles"
    case bars       = "Bars"

    var icon: String {
        switch self {
        case .ring:       return "circle.circle"
        case .concentric: return "circle.dashed.inset.filled"
        case .bars:       return "chart.bar.fill"
        }
    }
}

// MARK: - Ring Focus

enum RingFocus: String, CaseIterable {
    case calories = "Calories"
    case protein  = "Protein"
    case carbs    = "Carbs"
    case fat      = "Fat"

    var unit: String {
        switch self {
        case .calories: return "kcal"
        case .protein, .carbs, .fat: return "g"
        }
    }
    var icon: String {
        switch self {
        case .calories: return "flame.fill"
        case .protein:  return "bolt.fill"
        case .carbs:    return "leaf.fill"
        case .fat:      return "drop.fill"
        }
    }
    // Default colour — overridden by MacroColorManager when available
    var defaultColor: Color {
        switch self {
        case .calories: return Color.accentColor
        case .protein:  return .blue
        case .carbs:    return .orange
        case .fat:      return Color(red: 0.85, green: 0.70, blue: 0.1)
        }
    }
}

// MARK: - Consumed / Remaining toggle

enum TrackingMode: String {
    case consumed  = "Consumed"
    case remaining = "Remaining"

    var toggled: TrackingMode { self == .consumed ? .remaining : .consumed }
    var icon: String          { self == .consumed ? "fork.knife" : "minus.circle" }
}

// MARK: - Shared pure helpers

private func ringProgress(consumed: Double, target: Double) -> Double {
    guard target > 0 else { return 0 }
    return min(consumed / target, 1.0)
}

private func displayValue(consumed: Double, target: Double, mode: TrackingMode) -> Double {
    mode == .consumed ? consumed : target - consumed
}

private func isOver(consumed: Double, target: Double) -> Bool { consumed > target }

private func overColor(goal: Goal) -> Color { goal == .gain ? .green : .red }

private func fmt(_ v: Double) -> String { String(format: "%.0f", v) }

// MARK: - Shared bar section (used by all three cards)

private struct MacroBarsSection: View {
    let calConsumed:  Double; let calTarget:  Double
    let protConsumed: Double; let protTarget: Double
    let carbConsumed: Double; let carbTarget: Double
    let fatConsumed:  Double; let fatTarget:  Double
    let trackingMode: TrackingMode
    let goal: Goal
    // Injected colours from settings
    var calColor:  Color = Color.accentColor
    var protColor: Color = .blue
    var carbColor: Color = .orange
    var fatColor:  Color = Color(red: 0.85, green: 0.70, blue: 0.1)

    var body: some View {
        VStack(spacing: 14) {
            bar(consumed: calConsumed,  target: calTarget,  unit: "kcal", label: "Calories", color: calColor)
            bar(consumed: protConsumed, target: protTarget, unit: "g",    label: "Protein",  color: protColor)
            bar(consumed: carbConsumed, target: carbTarget, unit: "g",    label: "Carbs",    color: carbColor)
            bar(consumed: fatConsumed,  target: fatTarget,  unit: "g",    label: "Fat",      color: fatColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private func bar(consumed: Double, target: Double, unit: String, label: String, color: Color) -> some View {
        let progress  = ringProgress(consumed: consumed, target: target)
        let over      = isOver(consumed: consumed, target: target)
        let dispValue = displayValue(consumed: consumed, target: target, mode: trackingMode)
        let pct       = Int(progress * 100)
        let showRed   = over && trackingMode == .remaining

        return VStack(spacing: 6) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(fmt(dispValue)) / \(Int(target)) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(showRed ? .red : .secondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: dispValue)
                Text(showRed ? "over" : "\(pct)%")
                    .font(.caption.bold())
                    .foregroundStyle(showRed ? .red : color)
                    .frame(width: 36, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(showRed ? Color.red : color)
                        .frame(width: geo.size.width * progress, height: 10)
                        .animation(.easeInOut(duration: 0.55), value: progress)
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    let profile: UserProfile

    @Query private var foodEntries:   [FoodEntry]
    @Query private var weightEntries: [WeightEntry]

    @State private var showLogWeight      = false
    @State private var adjustmentMessage: String? = nil

    @AppStorage("calorieDisplayMode") private var displayModeRaw:  String = CalorieDisplayMode.ring.rawValue
    @AppStorage("trackingMode")       private var trackingModeRaw: String = TrackingMode.consumed.rawValue
    @AppStorage("ringFocus")          private var ringFocusRaw:    String = RingFocus.calories.rawValue

    // Macro colours from settings
    @AppStorage("colorCal")  private var colorCalHex:  String = MacroColorManager.defaultCalHex
    @AppStorage("colorProt") private var colorProtHex: String = MacroColorManager.defaultProtHex
    @AppStorage("colorCarb") private var colorCarbHex: String = MacroColorManager.defaultCarbHex
    @AppStorage("colorFat")  private var colorFatHex:  String = MacroColorManager.defaultFatHex

    private var calColor:  Color { Color.fromEncoded(colorCalHex) }
    private var protColor: Color { Color.fromEncoded(colorProtHex) }
    private var carbColor: Color { Color.fromEncoded(colorCarbHex) }
    private var fatColor:  Color { Color.fromEncoded(colorFatHex) }

    private var displayMode:  CalorieDisplayMode { CalorieDisplayMode(rawValue: displayModeRaw) ?? .ring }
    private var trackingMode: TrackingMode       { TrackingMode(rawValue: trackingModeRaw)       ?? .consumed }
    private var ringFocus:    RingFocus          { RingFocus(rawValue: ringFocusRaw)             ?? .calories }

    private var today: Date { Date() }

    private var totals: (cal: Double, protein: Double, carbs: Double, fat: Double) {
        AdaptiveEngine.totalsForDay(today, entries: foodEntries)
    }
    private var latestWeight: Double {
        AdaptiveEngine.latestWeight(entries: weightEntries) ?? profile.startingWeightKg
    }
    private var targets: MacroTargets { profile.macroTargets(weightKg: latestWeight) }

    // Map RingFocus → its user-chosen colour
    private func focusColor(_ f: RingFocus) -> Color {
        switch f {
        case .calories: return calColor
        case .protein:  return protColor
        case .carbs:    return carbColor
        case .fat:      return fatColor
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    if let msg = adjustmentMessage {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(.tint)
                            Text(msg).font(.subheadline)
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    WeightCard(
                        latestWeight: latestWeight,
                        goalWeight: profile.goalWeightKg,
                        entries: weightEntries
                    ) { showLogWeight = true }

                    // ── Control row ───────────────────────────────────────────
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                trackingModeRaw = trackingMode.toggled.rawValue
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: trackingMode.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(trackingMode.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Menu {
                            ForEach(CalorieDisplayMode.allCases, id: \.self) { mode in
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                        displayModeRaw = mode.rawValue
                                    }
                                } label: {
                                    Label(mode.rawValue, systemImage: mode.icon)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(displayMode.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)

                    // ── Visualisation ─────────────────────────────────────────
                    switch displayMode {
                    case .ring:
                        CalorieRingCard(
                            calConsumed:  totals.cal,     calTarget:  targets.calories,
                            protConsumed: totals.protein, protTarget: targets.protein,
                            carbConsumed: totals.carbs,   carbTarget: targets.carbs,
                            fatConsumed:  totals.fat,     fatTarget:  targets.fat,
                            trackingMode: trackingMode,
                            goal:         profile.goal,
                            focus:        ringFocus,
                            calColor:     calColor,
                            protColor:    protColor,
                            carbColor:    carbColor,
                            fatColor:     fatColor,
                            onChangeFocus: { ringFocusRaw = $0.rawValue }
                        )

                    case .concentric:
                        ConcentricRingsCard(
                            calConsumed:  totals.cal,     calTarget:  targets.calories,
                            protConsumed: totals.protein, protTarget: targets.protein,
                            carbConsumed: totals.carbs,   carbTarget: targets.carbs,
                            fatConsumed:  totals.fat,     fatTarget:  targets.fat,
                            trackingMode: trackingMode,
                            goal:         profile.goal,
                            calColor:  calColor,
                            protColor: protColor,
                            carbColor: carbColor,
                            fatColor:  fatColor
                        )

                    case .bars:
                        FillBarsCard(
                            calConsumed:  totals.cal,     calTarget:  targets.calories,
                            protConsumed: totals.protein, protTarget: targets.protein,
                            carbConsumed: totals.carbs,   carbTarget: targets.carbs,
                            fatConsumed:  totals.fat,     fatTarget:  targets.fat,
                            trackingMode: trackingMode,
                            goal:         profile.goal,
                            calColor:  calColor,
                            protColor: protColor,
                            carbColor: carbColor,
                            fatColor:  fatColor
                        )
                    }

                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { checkForWeeklyAdjustment() }
            .sheet(isPresented: $showLogWeight) { LogWeightSheet(profile: profile) }
        }
    }

    private var greeting: String {
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: today) ?? 1
        let totalDays = cal.range(of: .day, in: .year, for: today)?.count ?? 365
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return "\(f.string(from: today)) • Day \(dayOfYear)/\(totalDays)"
    }

    private func checkForWeeklyAdjustment() {
        if let result = AdaptiveEngine.recalculate(profile: profile, weightEntries: Array(weightEntries)) {
            profile.adjustedTarget     = result.newTarget
            profile.lastAdjustmentDate = Date()
            adjustmentMessage          = result.message
            try? modelContext.save()
        }
    }

    @Environment(\.modelContext) private var modelContext
}

// MARK: - Calorie Ring Card

struct CalorieRingCard: View {
    let calConsumed:  Double; let calTarget:  Double
    let protConsumed: Double; let protTarget: Double
    let carbConsumed: Double; let carbTarget: Double
    let fatConsumed:  Double; let fatTarget:  Double
    let trackingMode: TrackingMode
    let goal: Goal
    let focus: RingFocus
    var calColor:  Color = Color.accentColor
    var protColor: Color = .blue
    var carbColor: Color = .orange
    var fatColor:  Color = Color(red: 0.85, green: 0.70, blue: 0.1)
    var onChangeFocus: (RingFocus) -> Void

    private var focusConsumed: Double {
        switch focus { case .calories: return calConsumed; case .protein: return protConsumed; case .carbs: return carbConsumed; case .fat: return fatConsumed }
    }
    private var focusTarget: Double {
        switch focus { case .calories: return calTarget; case .protein: return protTarget; case .carbs: return carbTarget; case .fat: return fatTarget }
    }
    private func colorFor(_ f: RingFocus) -> Color {
        switch f { case .calories: return calColor; case .protein: return protColor; case .carbs: return carbColor; case .fat: return fatColor }
    }

    private var progress:     Double { ringProgress(consumed: focusConsumed, target: focusTarget) }
    private var over:         Bool   { isOver(consumed: focusConsumed, target: focusTarget) }
    private var centreValue:  Double { displayValue(consumed: focusConsumed, target: focusTarget, mode: trackingMode) }
    private var ringColor:    Color  { over ? overColor(goal: goal) : colorFor(focus) }

    var body: some View {
        VStack(spacing: 0) {

            // Focus picker — icon-only when unselected, expands to icon+name when selected
            HStack(spacing: 6) {
                Text("Focus")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                ForEach(RingFocus.allCases, id: \.self) { f in
                    let selected = f == focus
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { onChangeFocus(f) }
                    } label: {
                        HStack(spacing: selected ? 4 : 0) {
                            Image(systemName: f.icon)
                                .font(.system(size: 10, weight: .semibold))
                            if selected {
                                Text(f.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .fixedSize()
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                        .padding(.horizontal, selected ? 10 : 8)
                        .padding(.vertical, 5)
                        .background(selected ? colorFor(f) : Color(.systemGray5))
                        .foregroundStyle(selected ? .white : .secondary)
                        .clipShape(Capsule())
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Ring
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 18)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                VStack(spacing: 2) {
                    Text(fmt(centreValue))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(over && trackingMode == .remaining ? .red : .primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: centreValue)
                    Text(centreLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(focus.unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 16)   // tighter gap between ring and bars

            // Bars — no divider
            MacroBarsSection(
                calConsumed:  calConsumed,  calTarget:  calTarget,
                protConsumed: protConsumed, protTarget: protTarget,
                carbConsumed: carbConsumed, carbTarget: carbTarget,
                fatConsumed:  fatConsumed,  fatTarget:  fatTarget,
                trackingMode: trackingMode,
                goal:         goal,
                calColor:  calColor,
                protColor: protColor,
                carbColor: carbColor,
                fatColor:  fatColor
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    private var centreLabel: String {
        if trackingMode == .consumed { return "consumed" }
        return over ? "over" : "remaining"
    }
}

// MARK: - Concentric Rings Card

struct ConcentricRingsCard: View {
    let calConsumed:  Double; let calTarget:  Double
    let protConsumed: Double; let protTarget: Double
    let carbConsumed: Double; let carbTarget: Double
    let fatConsumed:  Double; let fatTarget:  Double
    let trackingMode: TrackingMode
    let goal: Goal
    var calColor:  Color = Color.accentColor
    var protColor: Color = .blue
    var carbColor: Color = .orange
    var fatColor:  Color = Color(red: 0.85, green: 0.70, blue: 0.1)

    private var calProg:  Double { ringProgress(consumed: calConsumed,  target: calTarget) }
    private var protProg: Double { ringProgress(consumed: protConsumed, target: protTarget) }
    private var carbProg: Double { ringProgress(consumed: carbConsumed, target: carbTarget) }
    private var fatProg:  Double { ringProgress(consumed: fatConsumed,  target: fatTarget) }

    private var calOver:  Bool { isOver(consumed: calConsumed,  target: calTarget) }
    private var protOver: Bool { isOver(consumed: protConsumed, target: protTarget) }
    private var carbOver: Bool { isOver(consumed: carbConsumed, target: carbTarget) }
    private var fatOver:  Bool { isOver(consumed: fatConsumed,  target: fatTarget) }

    private var calDisplay: Double { displayValue(consumed: calConsumed, target: calTarget, mode: trackingMode) }

    var body: some View {
        VStack(spacing: 0) {

            // Concentric rings — tighter top padding
            ZStack {
                ring(progress: calProg,  color: calOver  ? overColor(goal: goal) : calColor,  diameter: 200, lw: 22)
                ring(progress: protProg, color: protOver ? .red : protColor,                  diameter: 156, lw: 18)
                ring(progress: carbProg, color: carbOver ? .red : carbColor,                  diameter: 116, lw: 18)
                ring(progress: fatProg,  color: fatOver  ? .red : fatColor,                   diameter: 76,  lw: 18)

                VStack(spacing: 1) {
                    Text(fmt(calDisplay))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(calOver && trackingMode == .remaining ? .red : .primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: calDisplay)
                    Text(trackingMode == .consumed ? "kcal" : (calOver ? "over" : "left"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)
            .padding(.top, 16)    // tighter top
            .padding(.bottom, 16) // tighter bottom before bars

            // Bars — no divider
            MacroBarsSection(
                calConsumed:  calConsumed,  calTarget:  calTarget,
                protConsumed: protConsumed, protTarget: protTarget,
                carbConsumed: carbConsumed, carbTarget: carbTarget,
                fatConsumed:  fatConsumed,  fatTarget:  fatTarget,
                trackingMode: trackingMode,
                goal:         goal,
                calColor:  calColor,
                protColor: protColor,
                carbColor: carbColor,
                fatColor:  fatColor
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    private func ring(progress: Double, color: Color, diameter: CGFloat, lw: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.13), lineWidth: lw)
                .frame(width: diameter, height: diameter)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.7), value: progress)
        }
    }
}

// MARK: - Fill Bars Card

struct FillBarsCard: View {
    let calConsumed:  Double; let calTarget:  Double
    let protConsumed: Double; let protTarget: Double
    let carbConsumed: Double; let carbTarget: Double
    let fatConsumed:  Double; let fatTarget:  Double
    let trackingMode: TrackingMode
    let goal: Goal
    var calColor:  Color = Color.accentColor
    var protColor: Color = .blue
    var carbColor: Color = .orange
    var fatColor:  Color = Color(red: 0.85, green: 0.70, blue: 0.1)

    private var calOver:    Bool   { isOver(consumed: calConsumed, target: calTarget) }
    private var calDisplay: Double { displayValue(consumed: calConsumed, target: calTarget, mode: trackingMode) }

    var body: some View {
        VStack(spacing: 0) {
            // Header — no divider after it
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(fmt(calDisplay)) kcal")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(calOver && trackingMode == .remaining ? .red : .primary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: calDisplay)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let pct = Int(ringProgress(consumed: calConsumed, target: calTarget) * 100)
                ZStack {
                    Circle()
                        .fill(calOver ? overColor(goal: goal).opacity(0.15) : Color.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Text("\(pct)%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(calOver ? overColor(goal: goal) : Color.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)   // tight gap — no divider

            MacroBarsSection(
                calConsumed:  calConsumed,  calTarget:  calTarget,
                protConsumed: protConsumed, protTarget: protTarget,
                carbConsumed: carbConsumed, carbTarget: carbTarget,
                fatConsumed:  fatConsumed,  fatTarget:  fatTarget,
                trackingMode: trackingMode,
                goal:         goal,
                calColor:  calColor,
                protColor: protColor,
                carbColor: carbColor,
                fatColor:  fatColor
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    private var headerSubtitle: String {
        if trackingMode == .consumed { return "consumed today" }
        return calOver ? "over your target" : "remaining today"
    }
}

// MARK: - Weight Card

struct WeightCard: View {
    let latestWeight: Double
    let goalWeight:   Double
    let entries:      [WeightEntry]
    var onLog: () -> Void
    @Environment(\.units) private var units

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Weight").font(.caption).foregroundStyle(.secondary)
                Text(units.weightString(latestWeight)).font(.title2.bold())
                Text("Goal: \(units.weightString(goalWeight))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onLog) {
                Label("Log", systemImage: "scalemass.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.tint)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Today Food Section

struct TodayFoodSection: View {
    let entries: [FoodEntry]

    private var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        if !todayEntries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Log").font(.headline).padding(.horizontal)
                ForEach(todayEntries) { entry in
                    HStack {
                        Image(systemName: entry.meal.icon).foregroundStyle(.tint).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline.bold())
                            Text(entry.meal.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(entry.calories)) kcal").font(.subheadline.bold())
                            Text("P: \(Int(entry.protein))  C: \(Int(entry.carbs))  F: \(Int(entry.fat))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
    }
}

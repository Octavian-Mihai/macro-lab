import SwiftUI
import SwiftData


struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var step = 0

    // Everything starts empty — the profile (and the targets derived from it) must come from the user.
    @State private var name = ""
    @State private var ageText = ""
    @State private var sex: Sex? = nil
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var goalWeightText = ""
    @State private var activityLevel: ActivityLevel? = nil
    @State private var goal: Goal? = nil

    private func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private func value(_ text: String, in range: ClosedRange<Double>) -> Double? {
        number(text).flatMap { range.contains($0) ? $0 : nil }
    }
    private var ageValue: Int?       { value(ageText, in: 10...100).map { Int($0) } }
    private var heightValue: Double? { value(heightText, in: 100...250) }
    private var weightValue: Double? { value(weightText, in: 30...300) }
    private var goalWeightValue: Double? { value(goalWeightText, in: 30...300) }

    private let totalSteps = 5

    var body: some View {
        bodyContent
            .keyboardDoneButton()
    }

    private var bodyContent: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(.systemGray5)).frame(height: 4)
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps), height: 4)
                            .animation(.easeInOut, value: step)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal)
                .padding(.top, 16)

                TabView(selection: $step) {
                    stepWelcome.tag(0)
                    stepBasics.tag(1)
                    stepBody.tag(2)
                    stepGoal.tag(3)
                    stepActivity.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .scrollDisabled(true)   // only the Continue buttons advance, so validation can't be skipped
                .animation(.easeInOut, value: step)
            }
        }
    }

    var stepWelcome: some View {
        OnboardingStep(
            title: "Welcome",
            subtitle: "Let's set up your profile so we can calculate your calorie targets.",
            nextLabel: "Continue",
            isNextDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onNext: { step = 1 }
        ) {
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 8)
                LabeledField(label: "Your Name") {
                    TextField("e.g. Alex", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    var stepBasics: some View {
        OnboardingStep(
            title: "The Basics",
            subtitle: "Used for your BMR calculation.",
            nextLabel: "Continue",
            isNextDisabled: sex == nil || ageValue == nil,
            onNext: { step = 2 }
        ) {
            VStack(spacing: 20) {
                LabeledField(label: "Biological Sex") {
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                LabeledField(label: "Age") {
                    HStack(spacing: 8) {
                        TextField("e.g. 28", text: $ageText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Text("years").foregroundStyle(.secondary)
                    }
                    hint("Enter an age between 10 and 100", show: !ageText.isEmpty && ageValue == nil)
                }
            }
        }
    }

    var stepBody: some View {
        OnboardingStep(
            title: "Your Body",
            subtitle: "Height and current weight.",
            nextLabel: "Continue",
            isNextDisabled: heightValue == nil || weightValue == nil,
            onNext: { step = 3 }
        ) {
            VStack(spacing: 20) {
                LabeledField(label: "Height") {
                    HStack(spacing: 8) {
                        TextField("e.g. 175", text: $heightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("cm").foregroundStyle(.secondary)
                    }
                    hint("Enter a height between 100 and 250 cm", show: !heightText.isEmpty && heightValue == nil)
                }
                LabeledField(label: "Current Weight") {
                    HStack(spacing: 8) {
                        TextField("e.g. 72.5", text: $weightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    hint("Enter a weight between 30 and 300 kg", show: !weightText.isEmpty && weightValue == nil)
                }
            }
        }
    }

    var stepGoal: some View {
        OnboardingStep(
            title: "Your Goal",
            subtitle: "What are you working towards?",
            nextLabel: "Continue",
            isNextDisabled: goal == nil || goalWeightValue == nil,
            onNext: { step = 4 }
        ) {
            VStack(spacing: 20) {
                LabeledField(label: "Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(Goal.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                LabeledField(label: "Goal Weight") {
                    HStack(spacing: 8) {
                        TextField("e.g. 68", text: $goalWeightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    hint("Enter a weight between 30 and 300 kg", show: !goalWeightText.isEmpty && goalWeightValue == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func hint(_ text: String, show: Bool) -> some View {
        if show {
            Text(text).font(.caption).foregroundStyle(.red)
        }
    }

    var stepActivity: some View {
        OnboardingStep(
            title: "Activity Level",
            subtitle: "How active are you on a typical week?",
            nextLabel: "Create Profile",
            isNextDisabled: activityLevel == nil,
            onNext: { createProfile() }
        ) {
            VStack(spacing: 10) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    let isSelected = activityLevel == level
                    Button {
                        activityLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.shortName).font(.headline)
                                Text(level.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                        .padding()
                        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func createProfile() {
        guard
            let age = ageValue, let sex, let heightCm = heightValue,
            let currentWeightKg = weightValue, let goalWeightKg = goalWeightValue,
            let activityLevel, let goal
        else { return }
        let profile = UserProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            age: age,
            sex: sex,
            heightCm: heightCm,
            startingWeightKg: currentWeightKg,
            goalWeightKg: goalWeightKg,
            activityLevel: activityLevel,
            goal: goal
        )
        profile.lastAdjustmentDate = Date()
        modelContext.insert(profile)
        let weightEntry = WeightEntry(weightKg: currentWeightKg)
        modelContext.insert(weightEntry)
        try? modelContext.save()
    }
}

struct OnboardingStep<Content: View>: View {
    let title: String
    let subtitle: String
    var nextLabel: String = "Continue"
    var isNextDisabled: Bool
    var onNext: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 32)

            ScrollView {
                content()
                    .padding(.horizontal)
                    .padding(.top, 28)
            }

            Spacer()

            Button(action: onNext) {
                Text(nextLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isNextDisabled ? Color(.systemGray4) : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(isNextDisabled)
            .padding()
        }
    }
}

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)
            content()
        }
    }
}

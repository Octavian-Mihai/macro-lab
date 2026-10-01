import SwiftUI
import SwiftData


struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var step = 0

    @State private var name = ""
    @State private var age = 25
    @State private var sex: Sex = .male
    @State private var heightCm: Double = 170
    @State private var currentWeightKg: Double = 75
    @State private var goalWeightKg: Double = 68
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var goal: Goal = .lose

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
            isNextDisabled: false,
            onNext: { step = 2 }
        ) {
            VStack(spacing: 20) {
                LabeledField(label: "Biological Sex") {
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                LabeledField(label: "Age") {
                    Stepper("\(age) years old", value: $age, in: 10...100)
                }
            }
        }
    }

    var stepBody: some View {
        OnboardingStep(
            title: "Your Body",
            subtitle: "Height and current weight.",
            nextLabel: "Continue",
            isNextDisabled: false,
            onNext: { step = 3 }
        ) {
            VStack(spacing: 20) {
                LabeledField(label: "Height (cm)") {
                    HStack(spacing: 12) {
                        Slider(value: $heightCm, in: 140...220, step: 0.5)
                        TextField("cm", value: $heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .multilineTextAlignment(.center)
                    }
                }
                LabeledField(label: "Current Weight (kg)") {
                    HStack(spacing: 12) {
                        Slider(value: $currentWeightKg, in: 40...200, step: 0.5)
                        TextField("kg", value: $currentWeightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    var stepGoal: some View {
        OnboardingStep(
            title: "Your Goal",
            subtitle: "What are you working towards?",
            nextLabel: "Continue",
            isNextDisabled: false,
            onNext: { step = 4 }
        ) {
            VStack(spacing: 20) {
                LabeledField(label: "Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(Goal.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                LabeledField(label: "Goal Weight") {
                    HStack {
                        Slider(value: $goalWeightKg, in: 40...200, step: 0.5)
                        Text(String(format: "%.1f kg", goalWeightKg))
                            .frame(width: 64)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    var stepActivity: some View {
        OnboardingStep(
            title: "Activity Level",
            subtitle: "How active are you on a typical week?",
            nextLabel: "Create Profile",
            isNextDisabled: false,
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
        let profile = UserProfile(
            name: name,
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

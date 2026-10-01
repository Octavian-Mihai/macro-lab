import SwiftUI
import SwiftData
import Charts

struct ProgressChartView: View {
    let profile: UserProfile

    @Query(sort: \WeightEntry.date) private var weightEntries: [WeightEntry]
    @Query(sort: \FoodEntry.date)   private var foodEntries: [FoodEntry]

    @State private var selectedRange: ChartRange = .month

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Range picker
                    Picker("Range", selection: $selectedRange) {
                        ForEach(ChartRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Weight chart
                    weightChartCard

                    // Calorie chart
                    calorieChartCard

                    // Stats summary
                    statsCard
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Progress")
        }
    }

    // MARK: - Filtered data

    private var cutoff: Date {
        let days = selectedRange.days
        return Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private var filteredWeights: [WeightEntry] {
        weightEntries.filter { $0.date >= cutoff }
    }

    private var dailyCalories: [(date: Date, calories: Double)] {
        let days = selectedRange.days
        return (0..<days).compactMap { offset -> (Date, Double)? in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: Date())) else { return nil }
            let total = AdaptiveEngine.totalsForDay(day, entries: Array(foodEntries)).cal
            return total > 0 ? (day, total) : nil
        }.reversed()
    }

    // MARK: - Weight chart card

    var weightChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight").font(.headline).padding(.horizontal)

            if filteredWeights.count >= 2 {
                Chart(filteredWeights) { entry in
                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.1))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(30)
                }
                .frame(height: 180)
                .padding(.horizontal)

                // Goal line annotation
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            } else {
                Text("Log at least 2 weight entries to see your chart.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    // MARK: - Calorie chart card

    var calorieChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Calories").font(.headline).padding(.horizontal)

            if dailyCalories.isEmpty {
                Text("No food logged yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .multilineTextAlignment(.center)
            } else {
                Chart(dailyCalories, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Calories", item.calories)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)

                    RuleMark(y: .value("Target", profile.adjustedTarget))
                        .foregroundStyle(Color.red.opacity(0.5))
                        .lineStyle(StrokeStyle(dash: [6, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Target").font(.caption2).foregroundStyle(.red.opacity(0.7))
                        }
                }
                .frame(height: 180)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    // MARK: - Stats card

    var statsCard: some View {
        let startW  = weightEntries.sorted { $0.date < $1.date }.first?.weightKg ?? profile.startingWeightKg
        let latestW = AdaptiveEngine.latestWeight(entries: Array(weightEntries)) ?? startW
        let change  = latestW - startW
        let toGo    = profile.goalWeightKg - latestW
        let u       = UnitManager.shared

        return VStack(spacing: 0) {
            Text("Overall Stats").font(.headline).padding()
            Divider()
            HStack {
                statItem(label: "Start",   value: u.weightString(startW))
                Divider().frame(height: 40)
                statItem(label: "Now",     value: u.weightString(latestW))
                Divider().frame(height: 40)
                statItem(label: "Change",  value: String(format: "%+.1f \(u.weightUnit)", u.displayWeight(change)))
                Divider().frame(height: 40)
                statItem(label: "To Goal", value: u.weightString(abs(toGo)))
            }
            .padding()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chart Range

enum ChartRange: String, CaseIterable {
    case week  = "1W"
    case month = "1M"
    case threeMonths = "3M"

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        }
    }
}

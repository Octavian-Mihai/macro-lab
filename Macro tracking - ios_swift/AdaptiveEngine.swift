import Foundation
import SwiftData

/// Handles the weekly adaptive calorie target logic (MacroFactor-style)
struct AdaptiveEngine {

    // MARK: - Weekly Adjustment

    /// Call once per week. Compares actual vs expected weight change and nudges target.
    /// Returns a new calorie target and a human-readable reason string.
    static func recalculate(
        profile: UserProfile,
        weightEntries: [WeightEntry]
    ) -> (newTarget: Double, message: String)? {

        guard let lastAdj = profile.lastAdjustmentDate else {
            // First time — just set baseline
            return nil
        }

        // Need at least 7 days since last adjustment
        let daysSince = Calendar.current.dateComponents([.day], from: lastAdj, to: Date()).day ?? 0
        guard daysSince >= 7 else { return nil }

        // Weight entries since last adjustment
        let recent = weightEntries
            .filter { $0.date >= lastAdj }
            .sorted { $0.date < $1.date }

        guard recent.count >= 2,
              let first = recent.first,
              let last = recent.last else { return nil }

        let actualChange = last.weightKg - first.weightKg   // kg over period
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 7
        let weeklyActual = actualChange / Double(days) * 7   // normalize to per-week

        // Expected rate based on goal & current target vs TDEE
        let deficit = profile.adjustedTarget - profile.baseTDEE  // negative = deficit
        let expectedWeeklyChange = (deficit * 7) / 7700          // 7700 kcal ≈ 1 kg fat

        let discrepancy = weeklyActual - expectedWeeklyChange

        // Adjust: if losing slower than expected → cut more; gaining too fast → reduce surplus
        // Each 0.1 kg/week off ≈ 100 kcal adjustment
        let adjustment = -(discrepancy * 1000)
        let clampedAdjustment = min(max(adjustment, -200), 200)   // cap at ±200 kcal/week

        let newTarget = profile.adjustedTarget + clampedAdjustment

        // Build message
        let message = buildMessage(
            goal: profile.goal,
            weeklyActual: weeklyActual,
            expectedWeekly: expectedWeeklyChange,
            adjustment: clampedAdjustment
        )

        return (newTarget, message)
    }

    private static func buildMessage(
        goal: Goal,
        weeklyActual: Double,
        expectedWeekly: Double,
        adjustment: Double
    ) -> String {
        let actualStr = String(format: "%.2f", abs(weeklyActual))
        let adjInt = Int(adjustment.rounded())
        let sign = adjInt >= 0 ? "+" : ""

        switch goal {
        case .lose:
            if weeklyActual > -0.05 {
                return "You lost less than expected this week (\(actualStr) kg). Target adjusted \(sign)\(adjInt) kcal to keep you on track."
            } else if weeklyActual < -0.8 {
                return "You're losing weight very fast (\(actualStr) kg/week). Target increased by \(abs(adjInt)) kcal to keep the loss sustainable."
            } else {
                return "Great progress! You lost \(actualStr) kg this week. Target fine-tuned \(sign)\(adjInt) kcal."
            }
        case .gain:
            if weeklyActual < 0.05 {
                return "Minimal weight gain this week (\(actualStr) kg). Target adjusted \(sign)\(adjInt) kcal to fuel your growth."
            } else if weeklyActual > 0.5 {
                return "You're gaining faster than planned (\(actualStr) kg/week). Target reduced by \(abs(adjInt)) kcal for a cleaner bulk."
            } else {
                return "Solid week! Gained \(actualStr) kg. Target fine-tuned \(sign)\(adjInt) kcal."
            }
        }
    }

    // MARK: - Daily Totals Helper

    static func totalsForDay(_ date: Date, entries: [FoodEntry]) -> (cal: Double, protein: Double, carbs: Double, fat: Double) {
        let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        return (
            cal:     dayEntries.reduce(0) { $0 + $1.calories },
            protein: dayEntries.reduce(0) { $0 + $1.protein },
            carbs:   dayEntries.reduce(0) { $0 + $1.carbs },
            fat:     dayEntries.reduce(0) { $0 + $1.fat }
        )
    }

    // MARK: - Latest Weight

    static func latestWeight(entries: [WeightEntry]) -> Double? {
        entries.sorted { $0.date > $1.date }.first?.weightKg
    }

    // MARK: - 7-day average weight

    static func sevenDayAverageWeight(entries: [WeightEntry]) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let recent = entries.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.weightKg } / Double(recent.count)
    }
}

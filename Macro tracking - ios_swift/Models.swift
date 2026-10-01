import SwiftData
import Foundation

// MARK: - User Profile
@Model
class UserProfile {
    var name: String
    var age: Int
    var sex: Sex
    var heightCm: Double
    var startingWeightKg: Double
    var goalWeightKg: Double
    var activityLevel: ActivityLevel
    var goal: Goal
    var createdAt: Date
    var baseTDEE: Double        // Calculated from Mifflin-St Jeor
    var adjustedTarget: Double  // Adapted from weekly weight trend
    var lastAdjustmentDate: Date?

    init(
        name: String,
        age: Int,
        sex: Sex,
        heightCm: Double,
        startingWeightKg: Double, 
        goalWeightKg: Double,
        activityLevel: ActivityLevel,
        goal: Goal
    ) {
        self.name = name
        self.age = age
        self.sex = sex
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.goalWeightKg = goalWeightKg
        self.activityLevel = activityLevel
        self.goal = goal
        self.createdAt = Date()
        self.baseTDEE = 0
        self.adjustedTarget = 0
        self.lastAdjustmentDate = nil
        self.baseTDEE = calculateTDEE()
        self.adjustedTarget = calculateInitialTarget()
    }

    // Mifflin-St Jeor BMR → TDEE
    func calculateTDEE() -> Double {
        let bmr: Double
        if sex == .male {
            bmr = (10 * startingWeightKg) + (6.25 * heightCm) - (5 * Double(age)) + 5
        } else {
            bmr = (10 * startingWeightKg) + (6.25 * heightCm) - (5 * Double(age)) - 161
        }
        return bmr * activityLevel.multiplier
    }

    func calculateInitialTarget() -> Double {
        let tdee = calculateTDEE()
        switch goal {
        case .lose:   return tdee - 500   // ~0.5 kg/week deficit
        case .gain:   return tdee + 300   // lean bulk surplus
        }
    }

    // Protein: 2g/kg bodyweight, Fat: 25% of calories, remainder from carbs
    func macroTargets(weightKg: Double) -> MacroTargets {
        let calories = adjustedTarget
        let protein = weightKg * 2.0          // grams
        let fat = (calories * 0.25) / 9       // grams
        let carbs = (calories - (protein * 4) - (fat * 9)) / 4
        return MacroTargets(calories: calories, protein: protein, carbs: max(carbs, 0), fat: fat)
    }
}

struct MacroTargets {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

// MARK: - Food Entry
@Model
class FoodEntry {
    var date: Date
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var meal: MealType

    init(date: Date = Date(), name: String, calories: Double,
         protein: Double = 0, carbs: Double = 0, fat: Double = 0,
         meal: MealType = .other) {
        self.date = date
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.meal = meal
    }
}

// MARK: - Weight Entry
@Model
class WeightEntry {
    var date: Date
    var weightKg: Double

    init(date: Date = Date(), weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

// MARK: - Enums
enum Sex: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
}

enum Goal: String, Codable, CaseIterable {
    case lose = "Lose Weight"
    case gain = "Gain Weight / Muscle"
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary    = "Sedentary (desk job, little exercise)"
    case light        = "Lightly Active (1–3 days/week)"
    case moderate     = "Moderately Active (3–5 days/week)"
    case active       = "Very Active (6–7 days/week)"
    case veryActive   = "Athlete (2x/day training)"

    var multiplier: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    var shortName: String {
        switch self {
        case .sedentary:  return "Sedentary"
        case .light:      return "Light"
        case .moderate:   return "Moderate"
        case .active:     return "Active"
        case .veryActive: return "Athlete"
        }
    }
}

enum MealType: String, Codable, CaseIterable {
    case breakfast = "Breakfast"
    case lunch     = "Lunch"
    case dinner    = "Dinner"
    case snack     = "Snack"
    case other     = "Other"

    var icon: String {
        switch self {
        case .breakfast: return "sun.rise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "leaf.fill"
        case .other:     return "fork.knife"
        }
    }
}

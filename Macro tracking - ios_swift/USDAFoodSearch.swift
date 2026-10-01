import SwiftUI
import SwiftData

// MARK: - USDA Food Search Result

struct USDAFood: Identifiable, Hashable {
    let id: Int           // fdcId
    let name: String
    let brand: String?
    let category: String?
    let calories: Double  // per 100g
    let protein: Double
    let carbs: Double
    let fat: Double
}

// MARK: - USDA FoodData Central API

struct USDAFoodAPI {

    // Loaded from the gitignored Secrets.swift (see Secrets.example.swift)
    static let apiKey = Secrets.usdaAPIKey

    // Nutrient IDs in FoodData Central
    private enum NutrientID: Int {
        case calories = 1008   // Energy (kcal)
        case protein  = 1003
        case fat      = 1004
        case carbs    = 1005
    }

    // MARK: - Search

    static func search(query: String, pageSize: Int = 20) async throws -> [USDAFood] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key",  value: apiKey),
            URLQueryItem(name: "query",    value: query),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            // Prefer Foundation Foods + SR Legacy for generic foods, plus Branded
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded Food,Survey (FNDDS)")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)

        guard
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let foods = json["foods"] as? [[String: Any]]
        else { return [] }

        return foods.compactMap { parse(food: $0) }
    }

    // MARK: - Parse a single food from search results

    private static func parse(food: [String: Any]) -> USDAFood? {
        guard let fdcId = food["fdcId"] as? Int else { return nil }

        let name     = food["description"]   as? String ?? "Unknown"
        let brand    = food["brandOwner"]    as? String
        let category = food["foodCategory"]  as? String

        var cal: Double = 0
        var pro: Double = 0
        var fat: Double = 0
        var carb: Double = 0

        // foodNutrients array
        if let nutrients = food["foodNutrients"] as? [[String: Any]] {
            for n in nutrients {
                guard let nid   = n["nutrientId"]   as? Int,
                      let value = n["value"]         as? Double else { continue }
                switch nid {
                case NutrientID.calories.rawValue: cal  = value
                case NutrientID.protein.rawValue:  pro  = value
                case NutrientID.fat.rawValue:      fat  = value
                case NutrientID.carbs.rawValue:    carb = value
                default: break
                }
            }
        }

        // Some results use a nested "nutrientNumber" string instead
        if cal == 0, let nutrients = food["foodNutrients"] as? [[String: Any]] {
            for n in nutrients {
                guard
                    let numStr = n["nutrientNumber"] as? String,
                    let num    = Int(numStr),
                    let value  = n["value"] as? Double
                else { continue }
                switch num {
                case NutrientID.calories.rawValue: cal  = value
                case NutrientID.protein.rawValue:  pro  = value
                case NutrientID.fat.rawValue:      fat  = value
                case NutrientID.carbs.rawValue:    carb = value
                default: break
                }
            }
        }

        return USDAFood(
            id: fdcId,
            name: name.capitalized,
            brand: brand,
            category: category,
            calories: cal,
            protein:  pro,
            carbs:    carb,
            fat:      fat
        )
    }
}

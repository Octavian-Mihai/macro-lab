import SwiftUI
import SwiftData

// MARK: - USDA Food Search Result

struct USDAFood: Identifiable, Hashable {
    let id: Int           // fdcId
    let name: String
    let brand: String?
    let category: String?
    let dataType: String  // Foundation, SR Legacy, Branded …
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
        case atwaterGeneral  = 2047   // Foundation foods report energy here instead
        case atwaterSpecific = 2048
        case protein  = 1003
        case fat      = 1004
        case carbs    = 1005
    }

    // MARK: - Search

    static func search(query: String) async throws -> [USDAFood] {
        // Branded products are fetched alongside as a best-effort extra; only the
        // everyday-foods request is allowed to fail the search.
        async let branded = (try? await fetch(query: query, dataType: "Branded", pageSize: 15)) ?? []
        let generic = try await fetch(query: query, dataType: "Foundation,SR Legacy", pageSize: 100)
        return Array(rank(generic, for: query).prefix(30)) + (await branded)
    }

    // NOTE: don't add "Survey (FNDDS)" to dataType — the API answers 400 for it about half the time.
    private static func fetch(query: String, dataType: String, pageSize: Int) async throws -> [USDAFood] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key",  value: apiKey),
            URLQueryItem(name: "query",    value: query),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "dataType", value: dataType)
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        // The service occasionally returns a transient error page; retry once before failing.
        var data = Data()
        for attempt in 0..<2 {
            let (body, response) = try await URLSession.shared.data(from: url)
            data = body
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if (200..<300).contains(status) { break }
            if attempt == 1 { throw URLError(.badServerResponse) }
        }

        guard
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let foods = json["foods"] as? [[String: Any]]
        else { throw URLError(.cannotParseResponse) }

        return foods.compactMap { parse(food: $0) }
    }

    // MARK: - Ranking
    // USDA's own relevance puts things like "Crackers, milk" above plain "Milk, whole".
    // Rank foods whose name *starts with* what was typed first (USDA writes "Chicken, breast,
    // raw" as well as "Chicken breast, roll"), Foundation data before SR Legacy, shorter first.

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
    }

    private static func rank(_ foods: [USDAFood], for query: String) -> [USDAFood] {
        let q = words(query)
        guard !q.isEmpty else { return foods }

        func tier(_ food: USDAFood) -> Int {
            let name  = words(food.name)
            let head  = words(food.name.components(separatedBy: ",")[0])
            let hasAll = q.allSatisfy { name.contains($0) }
            if Array(name.prefix(q.count)) == q || head == q { return 0 }
            if hasAll, !head.isEmpty, head.allSatisfy({ q.contains($0) }) { return 1 }
            if hasAll, name.first == q.first { return 2 }
            return hasAll ? 3 : 4
        }

        return foods
            .map { (food: $0, tier: tier($0)) }
            .sorted {
                if $0.tier != $1.tier { return $0.tier < $1.tier }
                let f0 = $0.food.dataType == "Foundation", f1 = $1.food.dataType == "Foundation"
                if f0 != f1 { return f0 }
                return $0.food.name.count < $1.food.name.count
            }
            .map(\.food)
    }

    // MARK: - Parse a single food from search results

    private static func parse(food: [String: Any]) -> USDAFood? {
        guard let fdcId = food["fdcId"] as? Int else { return nil }

        let name     = food["description"]   as? String ?? "Unknown"
        let brand    = food["brandOwner"]    as? String
        let category = food["foodCategory"]  as? String
        let dataType = food["dataType"] as? String ?? ""

        var cal: Double = 0
        var pro: Double = 0
        var fat: Double = 0
        var carb: Double = 0
        var atwater: Double = 0

        // foodNutrients array
        if let nutrients = food["foodNutrients"] as? [[String: Any]] {
            for n in nutrients {
                guard let nid   = n["nutrientId"]   as? Int,
                      let value = n["value"]         as? Double else { continue }
                switch nid {
                case NutrientID.calories.rawValue: cal  = value
                case NutrientID.atwaterSpecific.rawValue: atwater = value
                case NutrientID.atwaterGeneral.rawValue:  if atwater == 0 { atwater = value }
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
                case NutrientID.atwaterSpecific.rawValue: atwater = value
                case NutrientID.atwaterGeneral.rawValue:  if atwater == 0 { atwater = value }
                case NutrientID.protein.rawValue:  pro  = value
                case NutrientID.fat.rawValue:      fat  = value
                case NutrientID.carbs.rawValue:    carb = value
                default: break
                }
            }
        }

        // Foundation foods have no plain "Energy (kcal)" value; use Atwater energy, else compute.
        if cal == 0 { cal = atwater }
        if cal == 0 { cal = pro * 4 + carb * 4 + fat * 9 }

        return USDAFood(
            id: fdcId,
            name: name.capitalized,
            brand: brand,
            category: category,
            dataType: dataType,
            calories: cal,
            protein:  pro,
            carbs:    carb,
            fat:      fat
        )
    }
}

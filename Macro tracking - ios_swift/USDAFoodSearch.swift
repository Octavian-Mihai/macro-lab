import SwiftUI
import SwiftData

// MARK: - USDA Food Search Result

struct USDAFood: Identifiable {
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

    // ⚠️ Replace with your key from https://fdc.nal.usda.gov/api-key-signup/
    static let apiKey = "u8dXpzCfg6Nh86XqM9cAGdnvbKVBFY8SyCnPTld8"

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

// MARK: - Food Search Sheet

struct FoodSearchSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @EnvironmentObject private var health: HealthKitManager

    @State private var query        = ""
    @State private var results: [USDAFood] = []
    @State private var isSearching  = false
    @State private var errorMsg: String? = nil
    @State private var selected: USDAFood? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView("Searching…")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let err = errorMsg {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .listRowBackground(Color.clear)
                } else if results.isEmpty && !query.isEmpty {
                    Text("No results for \(query)")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(results) { food in
                        Button { selected = food } label: {
                            FoodSearchRow(food: food)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search Foods")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "e.g. chicken breast, oats…")
            .onChange(of: query) { _, newVal in
                debounceSearch(newVal)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selected) { food in
                FoodPortionSheet(food: food)
            }
        }
    }

    // Debounce: wait 400ms after typing stops before firing request
    private func debounceSearch(_ text: String) {
        searchTask?.cancel()
        guard text.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(text)
        }
    }

    @MainActor
    private func performSearch(_ text: String) async {
        isSearching = true
        errorMsg    = nil
        do {
            results = try await USDAFoodAPI.search(query: text)
        } catch {
            errorMsg = "Search failed: \(error.localizedDescription)"
        }
        isSearching = false
    }
}

// MARK: - Search Result Row

struct FoodSearchRow: View {
    let food: USDAFood

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name)
                .font(.subheadline.bold())
                .lineLimit(2)
            HStack(spacing: 8) {
                if let brand = food.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                macroTag("\(Int(food.calories)) kcal", color: .primary)
                macroTag("P \(Int(food.protein))g",    color: .blue)
                macroTag("C \(Int(food.carbs))g",      color: .orange)
                macroTag("F \(Int(food.fat))g",        color: .yellow)
            }
            if let cat = food.category {
                Text(cat)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func macroTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
    }
}

// MARK: - Portion & Meal Picker Sheet

struct FoodPortionSheet: View {
    let food: USDAFood

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @EnvironmentObject private var health: HealthKitManager

    // USDA values are per 100g — user picks serving size
    @State private var servingGrams: Double = 100
    @State private var meal: MealType = .other
    @State private var syncToHealth = true

    private var factor: Double { servingGrams / 100.0 }

    private var displayCalories: Double { food.calories * factor }
    private var displayProtein:  Double { food.protein  * factor }
    private var displayCarbs:    Double { food.carbs    * factor }
    private var displayFat:      Double { food.fat      * factor }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name).font(.headline)
                        if let brand = food.brand {
                            Text(brand).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Serving Size") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Grams")
                            Spacer()
                            Text(String(format: "%.0f g", servingGrams))
                                .monospacedDigit()
                                .bold()
                        }
                        Slider(value: $servingGrams, in: 5...500, step: 5)

                        // Quick portion buttons
                        HStack(spacing: 8) {
                            ForEach([50, 100, 150, 200], id: \.self) { g in
                                Button("\(g)g") {
                                    withAnimation { servingGrams = Double(g) }
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Int(servingGrams) == g ? Color.accentColor : Color(.systemGray5))
                                .foregroundColor(Int(servingGrams) == g ? .white : .primary)
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                Section("Nutrition for \(Int(servingGrams))g") {
                    nutrientRow("Calories", value: displayCalories, unit: "kcal", color: .primary)
                    nutrientRow("Protein",  value: displayProtein,  unit: "g",    color: .blue)
                    nutrientRow("Carbs",    value: displayCarbs,    unit: "g",    color: .orange)
                    nutrientRow("Fat",      value: displayFat,      unit: "g",    color: .yellow)
                }

                Section("Meal") {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases, id: \.self) {
                            Label($0.rawValue, systemImage: $0.icon).tag($0)
                        }
                    }
                }

                if health.isAvailable {
                    Section {
                        Toggle("Sync to Apple Health", isOn: $syncToHealth)
                    }
                }

                Section {
                    Button("Add to Log") { save() }
                        .bold()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func nutrientRow(_ name: String, value: Double, unit: String, color: Color) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(String(format: "%.1f \(unit)", value))
                .bold()
                .foregroundStyle(color)
        }
    }

    private func save() {
        let entry = FoodEntry(
            name:     food.name,
            calories: displayCalories,
            protein:  displayProtein,
            carbs:    displayCarbs,
            fat:      displayFat,
            meal:     meal
        )
        modelContext.insert(entry)
        try? modelContext.save()
        if syncToHealth && health.isAuthorized {
            Task { await health.saveDietaryCalories(displayCalories, name: food.name) }
        }
        dismiss()
    }
}

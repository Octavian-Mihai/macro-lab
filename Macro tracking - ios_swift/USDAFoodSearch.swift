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
    @State private var showBarcode = false
    @State private var showManual  = false
    @State private var toast: String? = nil

    @Query(sort: \FoodEntry.date, order: .reverse) private var allEntries: [FoodEntry]

    // Most recent distinct foods, for one-tap re-logging
    private var recentFoods: [FoodEntry] {
        var seen = Set<String>()
        return Array(allEntries.filter { seen.insert($0.name).inserted }.prefix(8))
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty && !recentFoods.isEmpty {
                    Section("Recent — tap to log again") {
                        ForEach(recentFoods) { entry in
                            Button { quickLog(entry) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name).font(.subheadline.bold()).lineLimit(1)
                                        Text("P \(Int(entry.protein))g · C \(Int(entry.carbs))g · F \(Int(entry.fat))g")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(entry.calories)) kcal").font(.subheadline).bold()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if query.isEmpty {
                    Text("Search for a food, scan a barcode, or enter one manually.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .listRowBackground(Color.clear)
                }
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
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showBarcode = true } label: {
                            Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        }
                        Button { showManual = true } label: {
                            Label("Enter Manually", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $selected) { food in
                // Closing the whole flow after a save avoids a second "Cancel" tap
                FoodPortionSheet(food: food) { dismiss() }
            }
            .fullScreenCover(isPresented: $showBarcode) { BarcodeScanSheet() }
            .sheet(isPresented: $showManual) { ManualFoodEntrySheet() }
            .overlay(alignment: .bottom) {
                if let toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // Re-log a previous entry as-is, stamped now, with the meal for this time of day
    private func quickLog(_ entry: FoodEntry) {
        modelContext.insert(FoodEntry(
            name: entry.name, calories: entry.calories,
            protein: entry.protein, carbs: entry.carbs, fat: entry.fat,
            meal: MealType.suggested()
        ))
        try? modelContext.save()
        if health.isAuthorized {
            Task { await health.saveDietaryCalories(entry.calories, name: entry.name) }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { toast = "Added \(entry.name)" }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
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
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @EnvironmentObject private var health: HealthKitManager

    // USDA values are per 100g — user picks serving size
    @State private var servingGrams: Double = 100
    @State private var meal: MealType = .suggested()
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
                            TextField("100", value: $servingGrams, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .bold()
                                .frame(width: 80)
                            Text("g").bold()
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .bold()
                        .disabled(servingGrams <= 0)
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        onSaved()
    }
}

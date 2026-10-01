import SwiftUI
import SwiftData

// MARK: - Shared logging helper

@MainActor
private func logFood(
    _ context: ModelContext,
    health: HealthKitManager,
    name: String, calories: Double, protein: Double, carbs: Double, fat: Double,
    meal: MealType, syncToHealth: Bool = true
) {
    context.insert(FoodEntry(name: name, calories: calories, protein: protein,
                             carbs: carbs, fat: fat, meal: meal))
    try? context.save()
    if syncToHealth && health.isAuthorized {
        Task { await health.saveDietaryCalories(calories, name: name) }
    }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

// MARK: - Add Food (single screen: search → detail, with scan / manual shortcuts)

struct AddFoodView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitManager

    @Query(sort: \FoodEntry.date, order: .reverse) private var allEntries: [FoodEntry]

    @State private var query = ""
    @State private var results: [USDAFood] = []
    @State private var isSearching = false
    @State private var errorMsg: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var path: [USDAFood] = []
    @State private var showBarcode = false
    @State private var showManual = false
    @State private var toast: String?
    @FocusState private var searchFocused: Bool

    private var recents: [FoodEntry] {
        var seen = Set<String>()
        return Array(allEntries.filter { seen.insert($0.name).inserted }.prefix(10))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: USDAFood.self) { food in
                FoodDetailView(food: food) { dismiss() }
            }
            .overlay(alignment: .bottom) { toastView }
        }
        .fullScreenCover(isPresented: $showBarcode) { BarcodeScanSheet() }
        .sheet(isPresented: $showManual) { ManualFoodEntrySheet() }
        .onAppear { searchFocused = true }
    }

    // MARK: Search bar + shortcuts

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search foods, e.g. chicken breast", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onChange(of: query) { _, new in debounceSearch(new) }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            shortcut("barcode.viewfinder", label: "Scan barcode") { showBarcode = true }
            shortcut("square.and.pencil", label: "Enter manually") { showManual = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func shortcut(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel(label)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            recentsList
        } else if isSearching && results.isEmpty {
            ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMsg {
            message(errorMsg, icon: "wifi.exclamationmark")
        } else if results.isEmpty {
            message("No results for “\(query)”.\nTry a simpler name, or enter it manually.", icon: "magnifyingglass")
        } else {
            List(results) { food in
                NavigationLink(value: food) { resultRow(food) }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var recentsList: some View {
        Group {
            if recents.isEmpty {
                message("Search for a food, scan a barcode, or enter one manually.", icon: "fork.knife")
            } else {
                List {
                    Section("Recent — tap to log again") {
                        ForEach(recents) { entry in
                            Button { quickLog(entry) } label: { recentRow(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.tertiary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(_ food: USDAFood) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(food.name).font(.subheadline.bold()).lineLimit(2)
            if let brand = food.brand {
                Text(brand).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Text("\(Int(food.calories)) kcal").foregroundStyle(.primary)
                Text("P \(Int(food.protein))").foregroundStyle(.blue)
                Text("C \(Int(food.carbs))").foregroundStyle(.orange)
                Text("F \(Int(food.fat))").foregroundStyle(.yellow)
                Text("per 100g").foregroundStyle(.tertiary)
            }
            .font(.caption2.bold())
        }
        .padding(.vertical, 2)
    }

    private func recentRow(_ entry: FoodEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline.bold()).lineLimit(1)
                Text("P \(Int(entry.protein))g · C \(Int(entry.carbs))g · F \(Int(entry.fat))g")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.calories)) kcal").font(.subheadline.bold())
            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var toastView: some View {
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

    // MARK: Actions

    private func quickLog(_ entry: FoodEntry) {
        logFood(modelContext, health: health, name: entry.name, calories: entry.calories,
                protein: entry.protein, carbs: entry.carbs, fat: entry.fat,
                meal: .suggested())
        withAnimation { toast = "Added \(entry.name)" }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }

    private func debounceSearch(_ text: String) {
        searchTask?.cancel()
        errorMsg = nil
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                let found = try await USDAFoodAPI.search(query: text)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                errorMsg = "Search failed. Check your connection and try again."
            }
            isSearching = false
        }
    }
}

// MARK: - Food detail (portion, meal, confirm)

private struct FoodDetailView: View {
    let food: USDAFood
    let onLogged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var health: HealthKitManager

    @State private var grams: Double = 100
    @State private var meal: MealType = .suggested()
    @State private var syncToHealth = true
    @FocusState private var gramsFocused: Bool

    private var factor: Double { grams / 100 }
    private let presets: [Double] = [50, 100, 150, 200, 250]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                portionCard
                nutritionCard
                mealPicker
                if health.isAvailable {
                    Toggle("Sync to Apple Health", isOn: $syncToHealth)
                        .font(.subheadline)
                        .padding(.horizontal, 4)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Add \(Int(food.calories * factor)) kcal to Log")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(grams > 0 ? Color.accentColor : Color.gray, in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(grams <= 0)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name).font(.title3.bold())
            if let brand = food.brand {
                Text(brand).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var portionCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Amount").font(.subheadline.weight(.semibold))
                Spacer()
                TextField("100", value: $grams, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .focused($gramsFocused)
                    .multilineTextAlignment(.trailing)
                    .font(.title2.bold().monospacedDigit())
                    .frame(width: 100)
                Text("g").font(.title3.bold()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { min(max(grams, 5), 500) }, set: { grams = $0 }),
                   in: 5...500, step: 5)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { g in
                    let on = grams == g
                    Button("\(Int(g))g") { grams = g; gramsFocused = false }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Color.accentColor : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(on ? .white : .primary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var nutritionCard: some View {
        HStack(spacing: 0) {
            stat("\(Int((food.calories * factor).rounded()))", "kcal", .primary)
            stat(String(format: "%.1f", food.protein * factor), "Protein g", .blue)
            stat(String(format: "%.1f", food.carbs * factor), "Carbs g", .orange)
            stat(String(format: "%.1f", food.fat * factor), "Fat g", .yellow)
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var mealPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MealType.allCases, id: \.self) { m in
                    Button { meal = m } label: {
                        Label(m.rawValue, systemImage: m.icon)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(meal == m ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(meal == m ? .white : .primary)
                    }
                }
            }
        }
    }

    private func save() {
        guard grams > 0 else { return }
        logFood(modelContext, health: health, name: food.name,
                calories: food.calories * factor, protein: food.protein * factor,
                carbs: food.carbs * factor, fat: food.fat * factor,
                meal: meal, syncToHealth: syncToHealth)
        onLogged()
    }
}

import SwiftUI
import SwiftData

// MARK: - Add Food Sheet
// Opens the food database immediately. Manual entry is a fallback via "Enter manually".

struct AddFoodSheet: View {
    var body: some View {
        // Search is the entry point; barcode and manual entry are reachable from its toolbar.
        FoodSearchSheet()
    }
}

// MARK: - Manual Food Entry Sheet (fallback)

struct ManualFoodEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitManager
    @Query(sort: \FoodEntry.date, order: .reverse) private var allEntries: [FoodEntry]

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var showBarcode = false
    @State private var syncToHealth = true
    @State private var showMacros = false
    @State private var caloriesManuallyEdited = false

    private var calculatedCalories: String {
        let p = Double(protein) ?? 0
        let c = Double(carbs)   ?? 0
        let f = Double(fat)     ?? 0
        let total = (p * 4) + (c * 4) + (f * 9)
        return total > 0 ? String(format: "%.0f", total) : ""
    }

    private var isValid: Bool { !name.isEmpty && Double(calories) != nil }

    private var recentFoods: [FoodEntry] {
        var seen = Set<String>()
        let deduped: [FoodEntry] = allEntries.filter { seen.insert($0.name).inserted }
        return Array(deduped.prefix(6))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    recentsSection
                    entryCard
                    if health.isAvailable {
                        Toggle("Sync to Apple Health", isOn: $syncToHealth)
                            .padding(.horizontal, 20)
                            .font(.subheadline)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Enter Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(!isValid)
                }
            }
            .fullScreenCover(isPresented: $showBarcode) {
                BarcodeScanSheet()
            }
        }
    }

    // MARK: - Recents strip

    @ViewBuilder
    private var recentsSection: some View {
        if !recentFoods.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recentFoods) { entry in
                            RecentFoodChip(entry: entry) { fillFrom(entry) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Entry card

    private var entryCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Food name", text: $name)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 48)
            caloriesRow
            Divider().padding(.leading, 48)
            macrosToggleRow

            if showMacros {
                Divider().padding(.leading, 48)
                macroRow("P", label: "Protein", color: .blue, binding: $protein)
                Divider().padding(.leading, 48)
                macroRow("C", label: "Carbs", color: .orange, binding: $carbs)
                Divider().padding(.leading, 48)
                macroRow("F", label: "Fat", color: .yellow, binding: $fat)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private var caloriesRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("Calories", text: $calories)
                .keyboardType(.decimalPad)
                .onChange(of: calories) { _, new in
                    if new != calculatedCalories { caloriesManuallyEdited = true }
                }
            Text("kcal").foregroundStyle(.secondary).font(.subheadline)
            if caloriesManuallyEdited {
                Button {
                    caloriesManuallyEdited = false
                    calories = calculatedCalories
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var macrosToggleRow: some View {
        let hasValues = (Double(protein) ?? 0) + (Double(carbs) ?? 0) + (Double(fat) ?? 0) > 0
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { showMacros.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.pie")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(showMacros ? "Hide macros" : "Add macros (optional)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if !showMacros && hasValues {
                    Text("P\(Int(Double(protein) ?? 0)) C\(Int(Double(carbs) ?? 0)) F\(Int(Double(fat) ?? 0))")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                }
                Image(systemName: showMacros ? "chevron.up" : "chevron.down")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func macroRow(_ badge: String, label: String, color: Color, binding: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(badge).font(.caption.bold()).frame(width: 20).foregroundStyle(color)
            TextField(label, text: binding)
                .keyboardType(.decimalPad)
                .onChange(of: binding.wrappedValue) { _, _ in
                    guard !caloriesManuallyEdited else { return }
                    calories = calculatedCalories
                }
            Text("g").foregroundStyle(.secondary).font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func fillFrom(_ entry: FoodEntry) {
        name     = entry.name
        protein  = entry.protein > 0 ? String(Int(entry.protein)) : ""
        carbs    = entry.carbs   > 0 ? String(Int(entry.carbs))   : ""
        fat      = entry.fat     > 0 ? String(Int(entry.fat))     : ""
        calories = String(Int(entry.calories))
        caloriesManuallyEdited = false
        if entry.protein > 0 || entry.carbs > 0 || entry.fat > 0 { showMacros = true }
    }

    private func save() {
        guard let cal = Double(calories) else { return }
        let entry = FoodEntry(
            name:     name,
            calories: cal,
            protein:  Double(protein) ?? 0,
            carbs:    Double(carbs)   ?? 0,
            fat:      Double(fat)     ?? 0
        )
        modelContext.insert(entry)
        try? modelContext.save()
        if syncToHealth && health.isAuthorized {
            Task { await health.saveDietaryCalories(cal, name: name) }
        }
        dismiss()
    }
}

// MARK: - Recent Food Chip

private struct RecentFoodChip: View {
    let entry: FoodEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("· \(Int(entry.calories)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Weight Sheet

struct LogWeightSheet: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.units) private var units
    @EnvironmentObject private var health: HealthKitManager
    @State private var weight = ""
    @State private var syncToHealth = true

    var placeholder: String { units.isMetric ? "e.g. 74.5" : "e.g. 164.0" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(placeholder, text: $weight)
                            .keyboardType(.decimalPad)
                        Text(units.weightUnit).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Today's Weight")
                } footer: {
                    Text("Weigh yourself in the morning, before eating, for the most consistent readings.")
                }

                if health.isAvailable {
                    Section {
                        Toggle("Sync to Apple Health", isOn: $syncToHealth)
                    }
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(Double(weight) == nil)
                }
            }
        }
    }

    private func save() {
        guard let val = Double(weight) else { return }
        let kg = units.toKg(val)
        modelContext.insert(WeightEntry(weightKg: kg))
        try? modelContext.save()
        if syncToHealth && health.isAuthorized {
            Task { await health.saveWeight(kg) }
        }
        dismiss()
    }
}

// MARK: - Food Log View (full history by date)

struct FoodLogView: View {
    let profile: UserProfile
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
    @State private var showAdd = false

    private var groupedByDay: [(Date, [FoodEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedByDay, id: \.0) { (day, dayEntries) in
                    Section(header: Text(day.formatted(date: .abbreviated, time: .omitted))) {
                        ForEach(dayEntries) { entry in
                            FoodRowView(entry: entry)
                        }
                        .onDelete { offsets in
                            deleteEntries(offsets: offsets, from: dayEntries)
                        }
                    }
                }
            }
            .navigationTitle("Food Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFoodSheet()
            }
        }
    }

    @Environment(\.modelContext) private var modelContext

    private func deleteEntries(offsets: IndexSet, from dayEntries: [FoodEntry]) {
        for index in offsets { modelContext.delete(dayEntries[index]) }
        try? modelContext.save()
    }
}

struct FoodRowView: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline.bold())
                Text("P \(Int(entry.protein))g · C \(Int(entry.carbs))g · F \(Int(entry.fat))g")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.calories)) kcal")
                .font(.subheadline).bold()
        }
    }
}

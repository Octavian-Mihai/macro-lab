import Foundation
import HealthKit
import SwiftData
import Combine

// MARK: - HealthKit Manager

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var errorMessage: String? = nil

    private let weightType     = HKQuantityType(.bodyMass)
    private let caloriesType   = HKQuantityType(.activeEnergyBurned)
    private let dietaryCalType = HKQuantityType(.dietaryEnergyConsumed)

    private var readTypes:  Set<HKObjectType>  { [weightType, caloriesType, dietaryCalType] }
    private var writeTypes: Set<HKSampleType>  { [weightType, dietaryCalType] }

    // MARK: - Availability

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Request Authorization

    func requestAuthorization() async {
        guard isAvailable else {
            errorMessage = "HealthKit is not available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            errorMessage = "HealthKit authorization failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Write Weight

    func saveWeight(_ kg: Double, date: Date = Date()) async {
        guard isAuthorized else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample   = HKQuantitySample(type: weightType, quantity: quantity, start: date, end: date)
        do {
            try await store.save(sample)
        } catch {
            errorMessage = "Failed to save weight to Health: \(error.localizedDescription)"
        }
    }

    // MARK: - Write Dietary Calories

    func saveDietaryCalories(_ kcal: Double, name: String, date: Date = Date()) async {
        guard isAuthorized else { return }
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        let metadata: [String: Any] = [HKMetadataKeyFoodType: name]
        let sample   = HKQuantitySample(
            type: dietaryCalType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: metadata
        )
        do {
            try await store.save(sample)
        } catch {
            errorMessage = "Failed to save calories to Health: \(error.localizedDescription)"
        }
    }

    // MARK: - Read Latest Weight from Health

    func fetchLatestWeight() async -> Double? {
        guard isAuthorized else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    // MARK: - Read Weight History from Health (last N days)

    func fetchWeightHistory(days: Int = 90) async -> [(date: Date, kg: Double)] {
        guard isAuthorized else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: weightType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let results = (samples as? [HKQuantitySample] ?? []).map { s -> (Date, Double) in
                    (s.endDate, s.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }
}

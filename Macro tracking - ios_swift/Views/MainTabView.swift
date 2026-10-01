import SwiftUI

struct MainTabView: View {
    let profile: UserProfile

    @State private var showAddFood = false
    @State private var showBarcode = false

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Main tab view (unchanged behaviour) ──────────────────────────
            TabView {
                DashboardView(profile: profile)
                    .tabItem { Label("Today", systemImage: "circle.grid.2x2.fill") }

                FoodLogView(profile: profile)
                    .tabItem { Label("Log", systemImage: "list.bullet") }

                ProgressChartView(profile: profile)
                    .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

                SettingsView(profile: profile)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            // Reserve space so page content is never hidden behind our floating row
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 52)
            }

            // ── Persistent action row — sits just above the native tab bar ───
            VStack(spacing: 0) {
                actionRow
                // Transparent block the height of the native tab bar so our row
                // stacks directly above it without overlapping
                Color.clear.frame(height: 49)
            }
        }
        .sheet(isPresented: $showAddFood) {
            AddFoodView()
        }
        .fullScreenCover(isPresented: $showBarcode) {
            BarcodeScanSheet()
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                showAddFood = true
            } label: {
                Label("Log Food", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Button {
                showBarcode = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Color.accentColor.opacity(0.13))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) { Divider() }
    }
}

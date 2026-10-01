import SwiftUI
import AVFoundation
import SwiftData

// MARK: - Scanned Food Result

struct ScannedFood {
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSizeG: Double?
    var brand: String?
}

// MARK: - Open Food Facts API

struct OpenFoodFactsAPI {
    static func lookup(barcode: String) async throws -> ScannedFood? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)?fields=product_name,brands,nutriments,serving_size")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard
            let json      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let status    = json["status"] as? Int, status == 1,
            let product   = json["product"]  as? [String: Any],
            let nutriments = product["nutriments"] as? [String: Any]
        else { return nil }

        let name    = product["product_name"] as? String ?? "Unknown Product"
        let brand   = product["brands"] as? String

        // Prefer per-100g values, then convert based on serving size
        let cal100  = nutriments["energy-kcal_100g"]  as? Double
                   ?? (nutriments["energy_100g"] as? Double).map { $0 / 4.184 }
                   ?? 0
        let prot100 = nutriments["proteins_100g"]     as? Double ?? 0
        let carb100 = nutriments["carbohydrates_100g"] as? Double ?? 0
        let fat100  = nutriments["fat_100g"]           as? Double ?? 0

        // Serving size string, e.g. "30 g"
        let servingStr = product["serving_size"] as? String
        let servingG   = parseServingGrams(servingStr)

        let factor = (servingG ?? 100) / 100.0
        return ScannedFood(
            name:         name,
            calories:     cal100  * factor,
            protein:      prot100 * factor,
            carbs:        carb100 * factor,
            fat:          fat100  * factor,
            servingSizeG: servingG,
            brand:        brand
        )
    }

    private static func parseServingGrams(_ s: String?) -> Double? {
        guard let s else { return nil }
        // Try to extract a number before "g"
        let pattern = #"(\d+\.?\d*)\s*g"#
        if let range = s.range(of: pattern, options: .regularExpression) {
            let match = String(s[range])
            let numStr = match.components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            return Double(numStr)
        }
        return nil
    }
}

// MARK: - Scanner UIViewController

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onBarcode: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    private func setupSession() {
        let session = AVCaptureSession()
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [
            .ean8, .ean13, .upce, .code128, .qr, .dataMatrix
        ]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        // Scan region overlay
        addOverlay()

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func addOverlay() {
        let overlay = UIView()
        overlay.frame = view.bounds
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(overlay)

        let w: CGFloat = 260
        let h: CGFloat = 160
        let x = (view.bounds.width  - w) / 2
        let y = (view.bounds.height - h) / 2
        let clearRect = CGRect(x: x, y: y, width: w, height: h)

        let path = UIBezierPath(rect: overlay.bounds)
        let clear = UIBezierPath(roundedRect: clearRect, cornerRadius: 12)
        path.append(clear)
        path.usesEvenOddFillRule = true

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        overlay.layer.mask = maskLayer

        // Corner lines
        let border = UIView(frame: clearRect)
        border.backgroundColor = .clear
        border.layer.borderColor = UIColor.systemGreen.cgColor
        border.layer.borderWidth = 2
        border.layer.cornerRadius = 12
        view.addSubview(border)

        let label = UILabel()
        label.text = "Align barcode within frame"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.sizeToFit()
        label.center = CGPoint(x: view.bounds.midX, y: clearRect.maxY + 28)
        view.addSubview(label)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard
            let obj    = objects.first as? AVMetadataMachineReadableCodeObject,
            let string = obj.stringValue
        else { return }

        captureSession?.stopRunning()
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onBarcode?(string)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}

// MARK: - SwiftUI Wrapper

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onBarcode = onBarcode
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

// MARK: - Full Scan Sheet (scanner + result + confirm)

struct BarcodeScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isScanning   = true
    @State private var isLoading    = false
    @State private var scanned: ScannedFood? = nil
    @State private var error: String? = nil

    // Editable fields after scan
    @State private var name     = ""
    @State private var calories = ""
    @State private var protein  = ""
    @State private var carbs    = ""
    @State private var fat      = ""
    @State private var meal: MealType = .other

    var body: some View {
        NavigationStack {
            Group {
                if isScanning {
                    scannerView
                } else if isLoading {
                    loadingView
                } else if let err = error {
                    errorView(err)
                } else {
                    confirmView
                }
            }
            .navigationTitle(isScanning ? "Scan Barcode" : "Confirm Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Sub-views

    var scannerView: some View {
        BarcodeScannerView { barcode in
            isScanning = false
            isLoading  = true
            Task {
                do {
                    if let food = try await OpenFoodFactsAPI.lookup(barcode: barcode) {
                        scanned  = food
                        name     = food.brand.map { "\($0) – \(food.name)" } ?? food.name
                        calories = String(format: "%.0f", food.calories)
                        protein  = String(format: "%.1f", food.protein)
                        carbs    = String(format: "%.1f", food.carbs)
                        fat      = String(format: "%.1f", food.fat)
                    } else {
                        error = "Product not found in Open Food Facts database. You can enter the values manually."
                    }
                } catch {
                    self.error = "Network error: \(error.localizedDescription)"
                }
                isLoading = false
            }
        }
        .ignoresSafeArea()
    }

    var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Looking up product…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorView(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(msg)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
            Button("Scan Again") {
                error = nil
                isScanning = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var confirmView: some View {
        Form {
            if let food = scanned, let serving = food.servingSizeG {
                Section {
                    Text("Per serving (\(Int(serving))g)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Food") {
                TextField("Name", text: $name)
            }

            Section("Calories & Macros") {
                macroField("Calories (kcal)", $calories)
                macroField("Protein (g)",     $protein)
                macroField("Carbs (g)",        $carbs)
                macroField("Fat (g)",           $fat)
            }

            Section("Meal") {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases, id: \.self) {
                        Label($0.rawValue, systemImage: $0.icon).tag($0)
                    }
                }
            }

            Section {
                Button("Add to Log") { save() }
                    .bold()
                    .frame(maxWidth: .infinity)
                    .disabled(name.isEmpty || Double(calories) == nil)

                Button("Scan Another") {
                    isScanning = true
                    scanned    = nil
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func macroField(_ label: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: binding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func save() {
        guard let cal = Double(calories) else { return }
        let entry = FoodEntry(
            name:     name,
            calories: cal,
            protein:  Double(protein) ?? 0,
            carbs:    Double(carbs)   ?? 0,
            fat:      Double(fat)     ?? 0,
            meal:     meal
        )
        modelContext.insert(entry)
        try? modelContext.save()
        dismiss()
    }
}

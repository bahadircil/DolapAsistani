import SwiftUI
import PhotosUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var processedImage: UIImage? = nil
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selectedCategory: String = "Üst"
    @State private var selectedStyle: String = "Günlük"
    @State private var detectedColorHex: String = "#808080"
    @State private var showSaveConfirmation: Bool = false
    @State private var showCameraPicker: Bool = false
    @State private var showCameraUnavailableAlert: Bool = false

    private let categories = ["Üst", "Alt", "Ayakkabı", "Dış Giyim"]
    private let styles = ["Günlük", "Spor", "Klasik"]

    var body: some View {
        TabView {
            addClothingTab
                .tabItem {
                    Label("Kıyafet Ekle", systemImage: "plus.circle.fill")
                }

            WardrobeView()
                .tabItem {
                    Label("Dolabım", systemImage: "cabinet.fill")
                }

            OutfitView()
                .tabItem {
                    Label("Kombin Yap", systemImage: "wand.and.stars")
                }

            VirtualTryOnView()
                .tabItem {
                    Label("Sanal Kabin", systemImage: "figure.stand")
                }
        }
    }

    /// Kıyafet seçme/çekme, arka plan silme, renk/stil analizi ve dolaba kaydetme sekmesi
    private var addClothingTab: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Seçilen ve arka planı silinen fotoğrafın gösterileceği alan
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: 280)

                            if isProcessing {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .controlSize(.large)
                                    Text("Kıyafet dekupe ediliyor ve rengi analiz ediliyor...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            } else if let processedImage {
                                Image(uiImage: processedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 260)
                                    .padding(10)
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "tshirt.fill")
                                        .font(.system(size: 52))
                                        .foregroundStyle(.secondary)
                                    Text(errorMessage ?? "Henüz bir kıyafet fotoğrafı seçilmedi")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                        }

                        // CoreImage ile tespit edilen baskın renk rozeti
                        if processedImage != nil && !isProcessing {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: detectedColorHex))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                                Text("Renk: \(ColorHarmonyHelper.colorName(for: detectedColorHex))")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(12)
                        }
                    }
                    .padding(.horizontal)

                    // Kategori Seçici (Picker)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kategori")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Picker("Kategori", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)

                    // Stil Etiketi Seçici (Günlük, Spor, Klasik)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stil Etiketi")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Picker("Stil", selection: $selectedStyle) {
                            ForEach(styles, id: \.self) { style in
                                Text(style).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)

                    // Galeriden Seç & Kameradan Çek Butonları
                    HStack(spacing: 12) {
                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Galeriden Seç", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isProcessing)

                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showCameraPicker = true
                            } else {
                                showCameraUnavailableAlert = true
                            }
                        } label: {
                            Label("Kameradan Çek", systemImage: "camera.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.indigo)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isProcessing)
                    }
                    .padding(.horizontal)
                    .onChange(of: selectedItem) { newItem in
                        guard let newItem else { return }
                        Task {
                            await processSelectedPhoto(from: newItem)
                        }
                    }

                    // En altta Dolaba Ekle butonu
                    Button(action: saveToWardrobe) {
                        Label("Dolaba Ekle", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(processedImage != nil && !isProcessing ? Color.green : Color.gray.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(processedImage == nil || isProcessing)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .padding(.top)
            }
            .navigationTitle("Kıyafet Ekle")
            .sheet(isPresented: $showCameraPicker) {
                CameraPicker { capturedImage in
                    Task {
                        await processRawUIImage(capturedImage)
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Başarılı", isPresented: $showSaveConfirmation) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text("Kıyafet '\(selectedCategory)' (\(selectedStyle)) olarak dolabınıza kaydedildi.")
            }
            .alert("Kamera Kullanılamıyor", isPresented: $showCameraUnavailableAlert) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text("Sanal iPhone (Simulator) üzerinde fiziksel kamera bulunmadığı için lütfen 'Galeriden Seç' butonunu kullanın.")
            }
        }
    }

    /// Ekrandaki dekupe edilmiş kıyafeti PNG verisine çevirip kategori, stil ve baskın rengiyle SwiftData'ya kaydeder.
    private func saveToWardrobe() {
        guard let processedImage,
              let pngData = processedImage.pngData() else {
            errorMessage = "Görsel PNG verisine dönüştürülemedi."
            return
        }

        let newItem = ClothingItem(
            imageData: pngData,
            category: selectedCategory,
            styleTag: selectedStyle,
            dominantColorHex: detectedColorHex
        )
        modelContext.insert(newItem)

        do {
            try modelContext.save()
            showSaveConfirmation = true
            self.processedImage = nil
            self.selectedItem = nil
        } catch {
            errorMessage = "Kayıt sırasında hata oluştu: \(error.localizedDescription)"
        }
    }

    /// Galeriden seçilen fotoğrafı yükler ve işler.
    @MainActor
    private func processSelectedPhoto(from item: PhotosPickerItem) async {
        isProcessing = true
        errorMessage = nil

        guard let data = try? await item.loadTransferable(type: Data.self),
              let inputImage = UIImage(data: data) else {
            errorMessage = "Fotoğraf yüklenemedi."
            isProcessing = false
            return
        }

        await processRawUIImage(inputImage)
    }

    /// UIImage (galeri veya kamera) üzerinde arka plan silme ve CoreImage baskın renk analizini çalıştırır.
    @MainActor
    private func processRawUIImage(_ inputImage: UIImage) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let normalizedImage = normalizeOrientation(inputImage)

        if let cutoutImage = await removeBackground(from: normalizedImage) {
            processedImage = cutoutImage
            detectedColorHex = ColorHarmonyHelper.extractDominantColorHex(from: cutoutImage)
        } else {
            processedImage = normalizedImage
            detectedColorHex = ColorHarmonyHelper.extractDominantColorHex(from: normalizedImage)
            errorMessage = "Arka plan ayrıştırılamadı (orijinal görsel kullanılıyor)."
        }
    }

    /// Vision (`VNGenerateForegroundInstanceMaskRequest`) ve CoreImage kullanarak
    /// fotoğrafın arka planını tamamen cihaz içinde (offline) şeffaf hale getirir.
    private func removeBackground(from image: UIImage) async -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

            do {
                try handler.perform([request])
                guard let result = request.results?.first else { return nil }

                let maskPixelBuffer = try result.generateScaledMaskForImage(
                    forInstances: result.allInstances,
                    from: handler
                )
                let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)

                let blendFilter = CIFilter.blendWithMask()
                blendFilter.inputImage = ciImage
                blendFilter.maskImage = maskCIImage
                blendFilter.backgroundImage = CIImage.empty()

                guard let outputCIImage = blendFilter.outputImage,
                      let cgImage = CIContext().createCGImage(outputCIImage, from: outputCIImage.extent) else {
                    return nil
                }

                return UIImage(cgImage: cgImage)
            } catch {
                print("Arka plan silme hatası: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    /// Fotoğrafın EXIF yönelimini (orientation) düzeltir.
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

/// Kameradan doğrudan fotoğraf çekmek için UIImagePickerController sarmalayıcısı
struct CameraPicker: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// CoreImage ile kıyafetin baskın rengini bulan ve renk uyumu hesaplayan yardımcı yapı
enum ColorHarmonyHelper {
    /// CoreImage `CIAreaAverage` filtresiyle görselin baskın rengini Hex formatında döndürür.
    static func extractDominantColorHex(from image: UIImage) -> String {
        guard let ciImage = CIImage(image: image) else { return "#808080" }
        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent

        guard let outputImage = filter.outputImage else { return "#808080" }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let alpha = Double(bitmap[3]) / 255.0
        guard alpha > 0.05 else { return "#808080" }

        // Şeffaf piksellerin ortalamayı karartmasını önlemek için alpha ile normalize et
        let r = min(255, Int((Double(bitmap[0]) / alpha)))
        let g = min(255, Int((Double(bitmap[1]) / alpha)))
        let b = min(255, Int((Double(bitmap[2]) / alpha)))

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// İki Hex rengi arasındaki renk uyum puanını (0.0 - 1.0) hesaplar (Nötr, Tamamlayıcı ve Benzer renk uyumu).
    static func harmonyScore(hex1: String, hex2: String) -> Double {
        let c1 = UIColor(Color(hex: hex1))
        let c2 = UIColor(Color(hex: hex2))

        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        c1.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        c2.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)

        // Siyah, beyaz, gri, bej gibi nötr renkler her renkle yüksek uyum sağlar
        if s1 < 0.18 || s2 < 0.18 || b1 < 0.18 || b2 < 0.18 {
            return 0.95
        }

        let hueDiff = abs(Double(h1 - h2))
        let normalizedDiff = min(hueDiff, 1.0 - hueDiff) // 0.0 ... 0.5

        // Benzer (analogous ~0.08) veya tamamlayıcı (complementary ~0.5) tonlar uyumludur
        if normalizedDiff < 0.12 {
            return 0.88
        } else if abs(normalizedDiff - 0.5) < 0.12 {
            return 0.92
        } else {
            return 0.65
        }
    }

    /// Hex koduna göre Türkçe renk ailesi adını döndürür.
    static func colorName(for hex: String) -> String {
        let uiColor = UIColor(Color(hex: hex))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        if b < 0.20 { return "Siyah" }
        if s < 0.15 && b > 0.82 { return "Beyaz" }
        if s < 0.18 { return "Gri / Nötr" }

        let deg = h * 360
        switch deg {
        case 0..<20, 340...360: return "Kırmızı"
        case 20..<45: return "Turuncu / Kahve"
        case 45..<70: return "Sarı / Bej"
        case 70..<165: return "Yeşil"
        case 165..<255: return "Mavi / Lacivert"
        case 255..<340: return "Mor / Pembe"
        default: return "Çok Renkli"
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        if cleaned.count == 6 {
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        } else {
            (r, g, b) = (128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ClothingItem.self, SavedOutfit.self], inMemory: true)
}

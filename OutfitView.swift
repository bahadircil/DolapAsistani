import SwiftUI
import SwiftData
import WeatherKit
import CoreLocation

/// WeatherKit ve CoreLocation kullanarak anlık hava durumu bilgisini çeken,
/// erişim veya ücretsiz geliştirici hesabı kısıtlaması durumunda mevsime göre tahmin üreten yönetici.
@MainActor
final class WeatherOutfitManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperatureCelsius: Double = 20.0
    @Published var conditionDescription: String = "Mevsim Normalleri"
    @Published var symbolName: String = "cloud.sun.fill"
    @Published var isRainyOrSnowy: Bool = false
    @Published var isLoadingWeather: Bool = false
    @Published var weatherSourceNote: String = "Mevsimsel Tahmin"

    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared

    override init() {
        super.init()
        locationManager.delegate = self
        applySeasonalFallback()
    }

    /// Konum izni isteyip WeatherKit üzerinden güncel hava durumunu sorgular.
    func requestWeatherUpdate() {
        isLoadingWeather = true
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        } else {
            Task {
                await fetchWeather(for: CLLocation(latitude: 41.0082, longitude: 28.9784))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                await fetchWeather(for: CLLocation(latitude: 41.0082, longitude: 28.9784))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            await fetchWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            await fetchWeather(for: CLLocation(latitude: 41.0082, longitude: 28.9784))
        }
    }

    /// WeatherKit üzerinden verilen konumun hava durumunu alır.
    func fetchWeather(for location: CLLocation) async {
        do {
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather
            temperatureCelsius = current.temperature.converted(to: .celsius).value
            conditionDescription = current.condition.description
            symbolName = current.symbolName
            isRainyOrSnowy = Self.checkPrecipitation(for: current.condition)
            weatherSourceNote = "Apple WeatherKit"
        } catch {
            applySeasonalFallback()
        }
        isLoadingWeather = false
    }

    /// Takvim ayına göre mevsimsel hava durumu tahmini uygular.
    func applySeasonalFallback() {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12, 1, 2:
            temperatureCelsius = 7.0
            conditionDescription = "Kış Mevsimi • Soğuk"
            symbolName = "snowflake"
            isRainyOrSnowy = true
        case 3, 4, 5:
            temperatureCelsius = 16.0
            conditionDescription = "İlkbahar • Serin"
            symbolName = "cloud.sun.fill"
            isRainyOrSnowy = false
        case 6, 7, 8:
            temperatureCelsius = 28.0
            conditionDescription = "Yaz Mevsimi • Sıcak"
            symbolName = "sun.max.fill"
            isRainyOrSnowy = false
        default:
            temperatureCelsius = 14.0
            conditionDescription = "Sonbahar • Serin & Rüzgarlı"
            symbolName = "wind"
            isRainyOrSnowy = false
        }
        weatherSourceNote = "Mevsimsel Analiz"
    }

    /// Hava sıcaklığı ve yağış durumuna göre dış giyim (ceket/mont) gerekip gerekmediğini hesaplar.
    var needsOuterwear: Bool {
        temperatureCelsius < 18.0 || isRainyOrSnowy
    }

    /// Hava durumuna uygun kombin tavsiyesi metni
    var recommendationMessage: String {
        if temperatureCelsius < 10 {
            return "Hava oldukça soğuk (\(Int(temperatureCelsius))°C). Kalın bir Dış Giyim ile katmanlı kombin önerilir."
        } else if needsOuterwear {
            return "Hava serin (\(Int(temperatureCelsius))°C). Üst, Alt ve Ayakkabıya ek olarak Dış Giyim parçası eklendi."
        } else {
            return "Hava sıcak ve güzel (\(Int(temperatureCelsius))°C). Dış giyime gerek olmadan ferah bir kombin oluşturuldu."
        }
    }

    private static func checkPrecipitation(for condition: WeatherCondition) -> Bool {
        switch condition {
        case .rain, .heavyRain, .drizzle, .freezingRain, .freezingDrizzle,
             .snow, .heavySnow, .flurries, .sleet, .hail, .wintryMix,
             .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms:
            return true
        default:
            return false
        }
    }
}

struct OutfitView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var clothingItems: [ClothingItem]
    @Query(sort: \SavedOutfit.createdAt, order: .reverse) private var savedOutfits: [SavedOutfit]
    @StateObject private var weatherManager = WeatherOutfitManager()

    @State private var selectedStyleFilter: String = "Tümü"
    @State private var selectedTop: ClothingItem?
    @State private var selectedBottom: ClothingItem?
    @State private var selectedShoes: ClothingItem?
    @State private var selectedOuterwear: ClothingItem?
    @State private var includeOuterwearOverride: Bool? = nil
    @State private var showSavedAlert: Bool = false

    private let styleFilters = ["Tümü", "Günlük", "Spor", "Klasik"]

    private var filteredItems: [ClothingItem] {
        guard selectedStyleFilter != "Tümü" else { return clothingItems }
        let matched = clothingItems.filter { $0.styleTag == selectedStyleFilter }
        return matched.isEmpty ? clothingItems : matched
    }

    private var tops: [ClothingItem] {
        filteredItems.filter { $0.category == "Üst" }
    }

    private var bottoms: [ClothingItem] {
        filteredItems.filter { $0.category == "Alt" }
    }

    private var shoes: [ClothingItem] {
        filteredItems.filter { $0.category == "Ayakkabı" }
    }

    private var outerwears: [ClothingItem] {
        filteredItems.filter { $0.category == "Dış Giyim" }
    }

    private var shouldShowOuterwear: Bool {
        includeOuterwearOverride ?? weatherManager.needsOuterwear
    }

    /// Mevcut kombinin ortalama renk uyumu yüzdesi
    private var currentHarmonyPercentage: Int? {
        guard let top = selectedTop, let bottom = selectedBottom else { return nil }
        var total = ColorHarmonyHelper.harmonyScore(hex1: top.dominantColorHex, hex2: bottom.dominantColorHex)
        var count = 1.0
        if let shoe = selectedShoes {
            total += ColorHarmonyHelper.harmonyScore(hex1: bottom.dominantColorHex, hex2: shoe.dominantColorHex)
            count += 1.0
        }
        if shouldShowOuterwear, let outer = selectedOuterwear {
            total += ColorHarmonyHelper.harmonyScore(hex1: top.dominantColorHex, hex2: outer.dominantColorHex)
            count += 1.0
        }
        return Int((total / count) * 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Hava Durumu ve Mevsim Kartı
                    weatherHeaderCard

                    // Stil Filtresi
                    Picker("Stil Filtresi", selection: $selectedStyleFilter) {
                        ForEach(styleFilters, id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedStyleFilter) { _ in
                        generateSmartOutfit()
                    }

                    // Kombin Tuvali (Seçilen Kıyafetler)
                    if clothingItems.isEmpty {
                        emptyWardrobePlaceholder
                    } else {
                        if let harmony = currentHarmonyPercentage {
                            HStack {
                                Label("Renk Uyumu Skoru: %\(harmony)", systemImage: "paintpalette.fill")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.indigo)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }

                        outfitCanvasSection

                        // Otomatik Kombin Öner & Kaydet Butonları
                        HStack(spacing: 12) {
                            Button(action: generateSmartOutfit) {
                                Label("Akıllı Kombin Öner", systemImage: "wand.and.stars")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [.indigo, .blue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Button(action: saveCurrentOutfit) {
                                Label("Kaydet", systemImage: "heart.fill")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding()
                                    .background(Color.pink)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(selectedTop == nil && selectedBottom == nil)
                        }
                        .padding(.horizontal)
                    }

                    // Kayıtlı Kombinlerim Bölümü
                    if !savedOutfits.isEmpty {
                        savedOutfitsSection
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kombin Yap")
            .onAppear {
                weatherManager.requestWeatherUpdate()
                if selectedTop == nil && selectedBottom == nil && selectedShoes == nil {
                    generateSmartOutfit()
                }
            }
            .alert("Kombin Kaydedildi", isPresented: $showSavedAlert) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text("Beğendiğiniz kombin 'Kayıtlı Kombinlerim' listesine eklendi.")
            }
        }
    }

    /// WeatherKit & Mevsim Durumu Kartı
    private var weatherHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: weatherManager.symbolName)
                    .font(.system(size: 36))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(Int(weatherManager.temperatureCelsius))°C")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(weatherManager.conditionDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(weatherManager.weatherSourceNote)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }

                Spacer()

                if weatherManager.isLoadingWeather {
                    ProgressView()
                } else {
                    Button {
                        weatherManager.requestWeatherUpdate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .padding(8)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
            }

            Text(weatherManager.recommendationMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(.secondary)
                Slider(value: $weatherManager.temperatureCelsius, in: -5...38, step: 1) {
                    Text("Sıcaklık")
                }
                .onChange(of: weatherManager.temperatureCelsius) { _ in
                    includeOuterwearOverride = nil
                    if weatherManager.needsOuterwear && selectedOuterwear == nil {
                        selectedOuterwear = outerwears.randomElement()
                    }
                }

                Toggle("Dış Giyim", isOn: Binding(
                    get: { shouldShowOuterwear },
                    set: { newValue in
                        includeOuterwearOverride = newValue
                        if newValue && selectedOuterwear == nil {
                            selectedOuterwear = outerwears.randomElement()
                        }
                    }
                ))
                .labelsHidden()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// Kombin Parçalarının Gösterildiği Alan
    private var outfitCanvasSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                OutfitSlotCard(
                    title: "Üst",
                    icon: "tshirt.fill",
                    item: selectedTop,
                    availableCount: tops.count,
                    onNext: { selectedTop = nextItem(in: tops, current: selectedTop) }
                )

                if shouldShowOuterwear {
                    OutfitSlotCard(
                        title: "Dış Giyim",
                        icon: "jacket.fill",
                        item: selectedOuterwear,
                        availableCount: outerwears.count,
                        badgeText: "Hava Önerisi",
                        onNext: { selectedOuterwear = nextItem(in: outerwears, current: selectedOuterwear) }
                    )
                }
            }

            HStack(spacing: 16) {
                OutfitSlotCard(
                    title: "Alt",
                    icon: "figure.walk",
                    item: selectedBottom,
                    availableCount: bottoms.count,
                    onNext: { selectedBottom = nextItem(in: bottoms, current: selectedBottom) }
                )

                OutfitSlotCard(
                    title: "Ayakkabı",
                    icon: "shoe.fill",
                    item: selectedShoes,
                    availableCount: shoes.count,
                    onNext: { selectedShoes = nextItem(in: shoes, current: selectedShoes) }
                )
            }
        }
        .padding(.horizontal)
    }

    private var savedOutfitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kayıtlı Kombinlerim (\(savedOutfits.count))")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(savedOutfits) { outfit in
                        SavedOutfitCard(
                            outfit: outfit,
                            allItems: clothingItems,
                            onDelete: {
                                modelContext.delete(outfit)
                                try? modelContext.save()
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }

    private var emptyWardrobePlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.secondarySystemGroupedBackground))
            .frame(height: 240)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Kombin oluşturmak için önce dolabınıza kıyafet ekleyin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal)
    }

    /// Hava durumu, stil etiketi ve CoreImage baskın renk uyumuna göre en uygun kombini seçer.
    private func generateSmartOutfit() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let chosenTop = tops.randomElement()
            selectedTop = chosenTop

            if let chosenTop {
                // Üst giyimle renk uyumu en yüksek olan Alt, Ayakkabı ve Dış Giyimi seç
                selectedBottom = bottoms.max(by: {
                    ColorHarmonyHelper.harmonyScore(hex1: chosenTop.dominantColorHex, hex2: $0.dominantColorHex) <
                    ColorHarmonyHelper.harmonyScore(hex1: chosenTop.dominantColorHex, hex2: $1.dominantColorHex)
                }) ?? bottoms.randomElement()

                selectedShoes = shoes.max(by: {
                    ColorHarmonyHelper.harmonyScore(hex1: chosenTop.dominantColorHex, hex2: $0.dominantColorHex) <
                    ColorHarmonyHelper.harmonyScore(hex1: chosenTop.dominantColorHex, hex2: $1.dominantColorHex)
                }) ?? shoes.randomElement()

                if shouldShowOuterwear {
                    selectedOuterwear = outerwears.max(by: {
                        ColorHarmonyHelper.harmonyScore(hex1: chosenTop.dominantColorHex, hex2: $0.dominantColorHex) <
                        ColorHarmonyHelper.harmonyScore(hex1: chosenTop.dominantColorHex, hex2: $1.dominantColorHex)
                    }) ?? outerwears.randomElement()
                } else {
                    selectedOuterwear = nil
                }
            } else {
                selectedBottom = bottoms.randomElement()
                selectedShoes = shoes.randomElement()
                selectedOuterwear = shouldShowOuterwear ? outerwears.randomElement() : nil
            }
        }
    }

    private func saveCurrentOutfit() {
        let summary = "\(Int(weatherManager.temperatureCelsius))°C • \(weatherManager.conditionDescription)"
        let outfit = SavedOutfit(
            styleTag: selectedStyleFilter == "Tümü" ? (selectedTop?.styleTag ?? "Günlük") : selectedStyleFilter,
            weatherSummary: summary,
            topID: selectedTop?.id,
            bottomID: selectedBottom?.id,
            shoesID: selectedShoes?.id,
            outerwearID: shouldShowOuterwear ? selectedOuterwear?.id : nil
        )
        modelContext.insert(outfit)
        try? modelContext.save()
        showSavedAlert = true
    }

    private func nextItem(in list: [ClothingItem], current: ClothingItem?) -> ClothingItem? {
        guard !list.isEmpty else { return nil }
        guard let current,
              let index = list.firstIndex(where: { $0.id == current.id }) else {
            return list.first
        }
        let nextIndex = (index + 1) % list.count
        return list[nextIndex]
    }
}

private struct OutfitSlotCard: View {
    let title: String
    let icon: String
    let item: ClothingItem?
    let availableCount: Int
    var badgeText: String? = nil
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if availableCount > 1 {
                    Button(action: onNext) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .padding(6)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGroupedBackground))
                    .frame(height: 150)

                if let item, let uiImage = UIImage(data: item.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

                    Circle()
                        .fill(Color(hex: item.dominantColorHex))
                        .frame(width: 12, height: 12)
                        .padding(8)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("\(title) Yok")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let badgeText {
                Text(badgeText)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

private struct SavedOutfitCard: View {
    let outfit: SavedOutfit
    let allItems: [ClothingItem]
    let onDelete: () -> Void

    private var outfitItems: [ClothingItem] {
        let ids = [outfit.topID, outfit.outerwearID, outfit.bottomID, outfit.shoesID].compactMap { $0 }
        return ids.compactMap { id in allItems.first(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(outfit.styleTag)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 8) {
                ForEach(outfitItems) { item in
                    if let uiImage = UIImage(data: item.imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 56)
                            .padding(4)
                            .background(Color(.systemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Text(outfit.weatherSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 240)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    OutfitView()
        .modelContainer(for: [ClothingItem.self, SavedOutfit.self], inMemory: true)
}

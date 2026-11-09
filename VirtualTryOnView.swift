import SwiftUI
import SwiftData
import PhotosUI
import Vision
import ARKit
import RealityKit

/// Sanal Kabin Modları: Stüdyo Manken, AI Boy Fotoğrafı (Vücut Algılama) ve AR Oda Manken
enum TryOnMode: String, CaseIterable {
    case studio = "Stüdyo Manken"
    case aiBody = "AI Fotoğraf"
    case arRoom = "AR Oda (3D)"
}

/// Vision `VNDetectHumanBodyPoseRequest` ile tespit edilen vücut eklem noktaları (0..1 normalize koordinatlar, üst-sol orijinli)
struct DetectedBodyPose {
    var neck: CGPoint?
    var leftShoulder: CGPoint?
    var rightShoulder: CGPoint?
    var root: CGPoint?
    var leftHip: CGPoint?
    var rightHip: CGPoint?
    var leftAnkle: CGPoint?
    var rightAnkle: CGPoint?

    /// Omuz genişliği ve gövde merkezini hesaplar
    var torsoFrame: (center: CGPoint, width: CGFloat, height: CGFloat)? {
        guard let ls = leftShoulder, let rs = rightShoulder else { return nil }
        let shoulderMid = CGPoint(x: (ls.x + rs.x) / 2.0, y: (ls.y + rs.y) / 2.0)
        let hipMid: CGPoint
        if let lh = leftHip, let rh = rightHip {
            hipMid = CGPoint(x: (lh.x + rh.x) / 2.0, y: (lh.y + rh.y) / 2.0)
        } else if let root {
            hipMid = root
        } else {
            hipMid = CGPoint(x: shoulderMid.x, y: min(0.9, shoulderMid.y + 0.28))
        }

        let shoulderSpan = hypot(ls.x - rs.x, ls.y - rs.y)
        let width = max(0.28, shoulderSpan * 1.85)
        let height = max(0.24, abs(hipMid.y - shoulderMid.y) * 1.35)
        let center = CGPoint(
            x: (shoulderMid.x + hipMid.x) / 2.0,
            y: (shoulderMid.y + hipMid.y) / 2.0
        )
        return (center, width, height)
    }

    /// Kalça ve ayak bileği noktalarından alt giyim (pantolon/etek) çerçevesini hesaplar
    var legsFrame: (center: CGPoint, width: CGFloat, height: CGFloat)? {
        let hipMid: CGPoint
        if let lh = leftHip, let rh = rightHip {
            hipMid = CGPoint(x: (lh.x + rh.x) / 2.0, y: (lh.y + rh.y) / 2.0)
        } else if let root {
            hipMid = root
        } else {
            return nil
        }

        let ankleMid: CGPoint
        if let la = leftAnkle, let ra = rightAnkle {
            ankleMid = CGPoint(x: (la.x + ra.x) / 2.0, y: (la.y + ra.y) / 2.0)
        } else {
            ankleMid = CGPoint(x: hipMid.x, y: min(0.92, hipMid.y + 0.34))
        }

        let height = max(0.26, abs(ankleMid.y - hipMid.y) * 1.18)
        let width = max(0.26, height * 0.65)
        let center = CGPoint(
            x: (hipMid.x + ankleMid.x) / 2.0,
            y: (hipMid.y + ankleMid.y) / 2.0
        )
        return (center, width, height)
    }

    /// Ayak bileği noktalarından ayakkabı çerçevesini hesaplar
    var shoesFrame: (center: CGPoint, width: CGFloat, height: CGFloat)? {
        if let la = leftAnkle, let ra = rightAnkle {
            let center = CGPoint(x: (la.x + ra.x) / 2.0, y: min(0.95, ((la.y + ra.y) / 2.0) + 0.03))
            let span = max(0.18, abs(la.x - ra.x) * 1.8)
            return (center, span, 0.12)
        } else if let legs = legsFrame {
            let center = CGPoint(x: legs.center.x, y: min(0.95, legs.center.y + legs.height * 0.52))
            return (center, 0.22, 0.12)
        }
        return nil
    }
}

struct VirtualTryOnView: View {
    @Query private var clothingItems: [ClothingItem]

    @State private var selectedMode: TryOnMode = .studio
    @State private var selectedTop: ClothingItem?
    @State private var selectedBottom: ClothingItem?
    @State private var selectedShoes: ClothingItem?
    @State private var selectedOuterwear: ClothingItem?
    @State private var showOuterwear: Bool = false

    // AI Fotoğraf Modu Durumları
    @State private var bodyPhotoItem: PhotosPickerItem?
    @State private var userBodyImage: UIImage?
    @State private var detectedPose: DetectedBodyPose?
    @State private var isAnalyzingPose: Bool = false
    @State private var showPoseSkeleton: Bool = true
    @State private var poseStatusText: String = "Boy fotoğrafı seçtiğinizde Vision AI eklemleri otomatik algılar."

    // Stüdyo Modu Sürükleme & Ölçeklendirme Durumları
    @State private var topOffset: CGSize = .zero
    @State private var bottomOffset: CGSize = .zero
    @State private var shoesOffset: CGSize = .zero
    @State private var outerOffset: CGSize = .zero
    @State private var topScale: CGFloat = 1.0
    @State private var bottomScale: CGFloat = 1.0
    @State private var shoesScale: CGFloat = 1.0
    @State private var outerScale: CGFloat = 1.0

    @State private var activeCategoryTab: String = "Üst"
    private let categories = ["Üst", "Alt", "Ayakkabı", "Dış Giyim"]

    private var tops: [ClothingItem] { clothingItems.filter { $0.category == "Üst" } }
    private var bottoms: [ClothingItem] { clothingItems.filter { $0.category == "Alt" } }
    private var shoes: [ClothingItem] { clothingItems.filter { $0.category == "Ayakkabı" } }
    private var outerwears: [ClothingItem] { clothingItems.filter { $0.category == "Dış Giyim" } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Mod Seçici (Stüdyo Manken | AI Fotoğraf | AR Oda 3D)
                Picker("Mod", selection: $selectedMode) {
                    ForEach(TryOnMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Ana Manken / AR / AI Sahnesi
                ZStack {
                    switch selectedMode {
                    case .studio:
                        studioMannequinCanvas
                    case .aiBody:
                        aiBodyPoseCanvas
                    case .arRoom:
                        arRoomCanvas
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)

                // Alt Kıyafet Seçici Panel
                bottomWardrobeStrip
            }
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sanal Kabin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sıfırla") {
                        resetOffsets()
                    }
                    .font(.subheadline)
                }
            }
            .onAppear {
                if selectedTop == nil { selectedTop = tops.first }
                if selectedBottom == nil { selectedBottom = bottoms.first }
                if selectedShoes == nil { selectedShoes = shoes.first }
                if selectedOuterwear == nil { selectedOuterwear = outerwears.first }
            }
        }
    }

    // MARK: - 1. Stüdyo Manken Modu
    private var studioMannequinCanvas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Stüdyo Arka Planı
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color(.secondarySystemGroupedBackground), Color.indigo.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Anatomik Manken Silüeti Çizimi
                MannequinSilhouetteView()
                    .frame(width: w * 0.55, height: h * 0.88)
                    .opacity(0.32)

                // Katman 1: Ayakkabı (En Altta)
                if let selectedShoes, let img = UIImage(data: selectedShoes.imageData) {
                    DraggableClothingLayer(
                        image: img,
                        baseSize: CGSize(width: w * 0.28, height: h * 0.14),
                        initialPosition: CGPoint(x: w * 0.5, y: h * 0.86),
                        offset: $shoesOffset,
                        scale: $shoesScale
                    )
                }

                // Katman 2: Alt Giyim (Bacak & Kalça Bölgesi)
                if let selectedBottom, let img = UIImage(data: selectedBottom.imageData) {
                    DraggableClothingLayer(
                        image: img,
                        baseSize: CGSize(width: w * 0.42, height: h * 0.40),
                        initialPosition: CGPoint(x: w * 0.5, y: h * 0.62),
                        offset: $bottomOffset,
                        scale: $bottomScale
                    )
                }

                // Katman 3: Üst Giyim (Gövde & Omuz Bölgesi)
                if let selectedTop, let img = UIImage(data: selectedTop.imageData) {
                    DraggableClothingLayer(
                        image: img,
                        baseSize: CGSize(width: w * 0.44, height: h * 0.34),
                        initialPosition: CGPoint(x: w * 0.5, y: h * 0.32),
                        offset: $topOffset,
                        scale: $topScale
                    )
                }

                // Katman 4: Dış Giyim (Varsa en üst katman)
                if showOuterwear, let selectedOuterwear, let img = UIImage(data: selectedOuterwear.imageData) {
                    DraggableClothingLayer(
                        image: img,
                        baseSize: CGSize(width: w * 0.48, height: h * 0.36),
                        initialPosition: CGPoint(x: w * 0.52, y: h * 0.33),
                        offset: $outerOffset,
                        scale: $outerScale
                    )
                }

                // Bilgi Etiketi
                VStack {
                    HStack {
                        Label("Kıyafetleri sürükleyip boyutlandırabilirsiniz", systemImage: "hand.draw.fill")
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                        Spacer()

                        Toggle("Dış Giyim", isOn: $showOuterwear)
                            .labelsHidden()
                            .tint(.indigo)
                    }
                    .padding(12)
                    Spacer()
                }
            }
        }
    }

    // MARK: - 2. AI Boy Fotoğrafı (Vision Vücut Eklemi Algılama) Modu
    private var aiBodyPoseCanvas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))

                if let userBodyImage {
                    Image(uiImage: userBodyImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Vision AI eklem noktalarına göre kıyafetleri otomatik yerleştir
                    if let pose = detectedPose {
                        if showPoseSkeleton {
                            BodyPoseSkeletonOverlay(pose: pose)
                                .frame(width: w, height: h)
                        }

                        if let shoesFrame = pose.shoesFrame,
                           let selectedShoes,
                           let img = UIImage(data: selectedShoes.imageData) {
                            DraggableClothingLayer(
                                image: img,
                                baseSize: CGSize(width: w * shoesFrame.width, height: h * shoesFrame.height),
                                initialPosition: CGPoint(x: w * shoesFrame.center.x, y: h * shoesFrame.center.y),
                                offset: $shoesOffset,
                                scale: $shoesScale
                            )
                        }

                        if let legsFrame = pose.legsFrame,
                           let selectedBottom,
                           let img = UIImage(data: selectedBottom.imageData) {
                            DraggableClothingLayer(
                                image: img,
                                baseSize: CGSize(width: w * legsFrame.width, height: h * legsFrame.height),
                                initialPosition: CGPoint(x: w * legsFrame.center.x, y: h * legsFrame.center.y),
                                offset: $bottomOffset,
                                scale: $bottomScale
                            )
                        }

                        if let torsoFrame = pose.torsoFrame,
                           let selectedTop,
                           let img = UIImage(data: selectedTop.imageData) {
                            DraggableClothingLayer(
                                image: img,
                                baseSize: CGSize(width: w * torsoFrame.width, height: h * torsoFrame.height),
                                initialPosition: CGPoint(x: w * torsoFrame.center.x, y: h * torsoFrame.center.y),
                                offset: $topOffset,
                                scale: $topScale
                            )
                        }

                        if showOuterwear,
                           let torsoFrame = pose.torsoFrame,
                           let selectedOuterwear,
                           let img = UIImage(data: selectedOuterwear.imageData) {
                            DraggableClothingLayer(
                                image: img,
                                baseSize: CGSize(width: w * torsoFrame.width * 1.08, height: h * torsoFrame.height * 1.06),
                                initialPosition: CGPoint(x: w * torsoFrame.center.x, y: h * torsoFrame.center.y),
                                offset: $outerOffset,
                                scale: $outerScale
                            )
                        }
                    } else {
                        // Eklem algılanamazsa standart merkezli yerleştir
                        studioMannequinOverlayFallback(width: w, height: h)
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "figure.stand.line.dotted.figure.stand")
                            .font(.system(size: 54))
                            .foregroundStyle(.indigo)

                        Text("AI Vücut Algılama ile Kıyafet Deneme")
                            .font(.headline)

                        Text("Galerinizden bir boy fotoğrafı seçin; Apple Vision AI omuz, bel ve ayak bileği eklemlerini otomatik bulup kıyafetleri üzerinize giydirsin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        PhotosPicker(selection: $bodyPhotoItem, matching: .images) {
                            Label("Boy Fotoğrafı Seç", systemImage: "person.crop.rectangle")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.indigo)
                                .clipShape(Capsule())
                        }
                    }
                }

                if isAnalyzingPose {
                    ProgressView("Vision AI vücut eklemlerini algılıyor...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Üst Контроl Çubuğu
                if userBodyImage != nil {
                    VStack {
                        HStack(spacing: 8) {
                            PhotosPicker(selection: $bodyPhotoItem, matching: .images) {
                                Label("Fotoğraf Değiştir", systemImage: "photo")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }

                            Button {
                                showPoseSkeleton.toggle()
                            } label: {
                                Label(showPoseSkeleton ? "AI Eklemler Açık" : "AI Eklemler Gizli", systemImage: "figure.arms.open")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }

                            Spacer()
                        }
                        .padding(10)

                        Spacer()

                        Text(poseStatusText)
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 8)
                    }
                }
            }
            .onChange(of: bodyPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    await analyzeBodyPhoto(from: newItem)
                }
            }
        }
    }

    @ViewBuilder
    private func studioMannequinOverlayFallback(width w: CGFloat, height h: CGFloat) -> some View {
        if let selectedShoes, let img = UIImage(data: selectedShoes.imageData) {
            DraggableClothingLayer(
                image: img,
                baseSize: CGSize(width: w * 0.26, height: h * 0.13),
                initialPosition: CGPoint(x: w * 0.5, y: h * 0.85),
                offset: $shoesOffset,
                scale: $shoesScale
            )
        }
        if let selectedBottom, let img = UIImage(data: selectedBottom.imageData) {
            DraggableClothingLayer(
                image: img,
                baseSize: CGSize(width: w * 0.40, height: h * 0.38),
                initialPosition: CGPoint(x: w * 0.5, y: h * 0.62),
                offset: $bottomOffset,
                scale: $bottomScale
            )
        }
        if let selectedTop, let img = UIImage(data: selectedTop.imageData) {
            DraggableClothingLayer(
                image: img,
                baseSize: CGSize(width: w * 0.42, height: h * 0.32),
                initialPosition: CGPoint(x: w * 0.5, y: h * 0.34),
                offset: $topOffset,
                scale: $topScale
            )
        }
    }

    // MARK: - 3. AR Oda (3D RealityKit Manken) Modu
    private var arRoomCanvas: some View {
        ZStack(alignment: .top) {
            ARMannequinContainerView(
                topImageData: selectedTop?.imageData,
                bottomImageData: selectedBottom?.imageData,
                shoesImageData: selectedShoes?.imageData,
                outerwearImageData: showOuterwear ? selectedOuterwear?.imageData : nil
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            HStack {
                Label("Kamerayı odanıza tutun • 3D AR Manken", systemImage: "arkit")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                Spacer()

                Toggle("Dış Giyim", isOn: $showOuterwear)
                    .labelsHidden()
                    .tint(.indigo)
            }
            .padding(12)
        }
    }

    // MARK: - Alt Kıyafet Seçim Paneli
    private var bottomWardrobeStrip: some View {
        VStack(spacing: 8) {
            // Kategori Sekmeleri
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        let isSelected = activeCategoryTab == category
                        Button {
                            activeCategoryTab = category
                            if category == "Dış Giyim" {
                                showOuterwear = true
                            }
                        } label: {
                            Text(category)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.indigo : Color.secondary.opacity(0.15))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Seçili Kategorideki Kıyafetler
            let itemsForTab = clothingItems.filter { $0.category == activeCategoryTab }
            if itemsForTab.isEmpty {
                Text("Bu kategoride henüz kıyafet yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 74)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(itemsForTab) { item in
                            let isChosen = isItemSelected(item)
                            Button {
                                selectItemForMannequin(item)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                        .frame(width: 68, height: 74)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isChosen ? Color.indigo : Color.clear, lineWidth: 2.5)
                                        )

                                    if let uiImage = UIImage(data: item.imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 56, height: 62)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 78)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func isItemSelected(_ item: ClothingItem) -> Bool {
        switch item.category {
        case "Üst": return selectedTop?.id == item.id
        case "Alt": return selectedBottom?.id == item.id
        case "Ayakkabı": return selectedShoes?.id == item.id
        case "Dış Giyim": return selectedOuterwear?.id == item.id && showOuterwear
        default: return false
        }
    }

    private func selectItemForMannequin(_ item: ClothingItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            switch item.category {
            case "Üst": selectedTop = item
            case "Alt": selectedBottom = item
            case "Ayakkabı": selectedShoes = item
            case "Dış Giyim":
                selectedOuterwear = item
                showOuterwear = true
            default: break
            }
        }
    }

    private func resetOffsets() {
        withAnimation(.spring()) {
            topOffset = .zero
            bottomOffset = .zero
            shoesOffset = .zero
            outerOffset = .zero
            topScale = 1.0
            bottomScale = 1.0
            shoesScale = 1.0
            outerScale = 1.0
        }
    }

    /// Vision `VNDetectHumanBodyPoseRequest` ile boy fotoğrafındaki omuz, kalça ve ayak bileği eklemlerini tespit eder.
    @MainActor
    private func analyzeBodyPhoto(from item: PhotosPickerItem) async {
        isAnalyzingPose = true
        defer { isAnalyzingPose = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let rawImage = UIImage(data: data) else {
            poseStatusText = "Fotoğraf yüklenemedi."
            return
        }

        // Yönelimi düzelt
        let renderer = UIGraphicsImageRenderer(size: rawImage.size)
        let normalized = rawImage.imageOrientation == .up ? rawImage : renderer.image { _ in
            rawImage.draw(in: CGRect(origin: .zero, size: rawImage.size))
        }
        userBodyImage = normalized
        resetOffsets()

        guard let cgImage = normalized.cgImage else { return }

        let pose = await Task.detached(priority: .userInitiated) { () -> DetectedBodyPose? in
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first else { return nil }
                let points = try observation.recognizedPoints(.all)

                func convert(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                    guard let pt = points[joint], pt.confidence > 0.2 else { return nil }
                    // Vision koordinatlarında (0,0) sol-alt köşedir; SwiftUI için üst-sol orijine çevir
                    return CGPoint(x: pt.location.x, y: 1.0 - pt.location.y)
                }

                return DetectedBodyPose(
                    neck: convert(.neck),
                    leftShoulder: convert(.leftShoulder),
                    rightShoulder: convert(.rightShoulder),
                    root: convert(.root),
                    leftHip: convert(.leftHip),
                    rightHip: convert(.rightHip),
                    leftAnkle: convert(.leftAnkle),
                    rightAnkle: convert(.rightAnkle)
                )
            } catch {
                return nil
            }
        }.value

        if let pose, pose.torsoFrame != nil {
            detectedPose = pose
            poseStatusText = "Vision AI vücut eklemlerini algıladı ve kıyafetleri hizaladı."
        } else {
            detectedPose = nil
            poseStatusText = "Eklemler tam görünmediği için standart hizalama kullanıldı (elle sürükleyebilirsiniz)."
        }
    }
}

/// Manken üzerinde sürüklenebilir ve yakınlaştırılabilir kıyafet katmanı
private struct DraggableClothingLayer: View {
    let image: UIImage
    let baseSize: CGSize
    let initialPosition: CGPoint
    @Binding var offset: CGSize
    @Binding var scale: CGFloat

    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(
                width: baseSize.width * scale * pinchDelta,
                height: baseSize.height * scale * pinchDelta
            )
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            .position(
                x: initialPosition.x + offset.width + dragDelta.width,
                y: initialPosition.y + offset.height + dragDelta.height
            )
            .gesture(
                DragGesture()
                    .updating($dragDelta) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
                    .simultaneously(
                        with: MagnificationGesture()
                            .updating($pinchDelta) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                scale = min(max(scale * value, 0.5), 2.2)
                            }
                    )
            )
    }
}

/// 2D Stüdyo Manken Silüeti
private struct MannequinSilhouetteView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            VStack(spacing: 4) {
                // Baş
                Circle()
                    .fill(Color.secondary)
                    .frame(width: w * 0.22, height: w * 0.22)

                // Boyun
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary)
                    .frame(width: w * 0.09, height: h * 0.03)

                // Gövde & Omuzlar
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.secondary)
                    .frame(width: w * 0.62, height: h * 0.34)

                // Bacaklar
                HStack(spacing: w * 0.06) {
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: w * 0.22, height: h * 0.42)
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: w * 0.22, height: h * 0.42)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Vision AI ile tespit edilen eklem noktalarını gösteren çizim katmanı
private struct BodyPoseSkeletonOverlay: View {
    let pose: DetectedBodyPose

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let joints = [
                pose.neck, pose.leftShoulder, pose.rightShoulder,
                pose.root, pose.leftHip, pose.rightHip,
                pose.leftAnkle, pose.rightAnkle
            ].compactMap { $0 }

            ZStack {
                ForEach(0..<joints.count, id: \.self) { idx in
                    let pt = joints[idx]
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(x: pt.x * w, y: pt.y * h)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// ARKit + RealityKit ile gerçek odaya 3 boyutlu manken ve seçili kıyafetleri yerleştiren AR görünümü
private struct ARMannequinContainerView: UIViewRepresentable {
    let topImageData: Data?
    let bottomImageData: Data?
    let shoesImageData: Data?
    let outerwearImageData: Data?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        // Kameranın 1.6 metre önüne ve biraz aşağısına 3D Manken Anchor'ı yerleştir
        let anchor = AnchorEntity(world: SIMD3<Float>(0, -0.55, -1.6))
        anchor.name = "MannequinAnchor"
        arView.scene.addAnchor(anchor)

        updateMannequinEntities(in: anchor)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        guard let anchor = arView.scene.anchors.first(where: { $0.name == "MannequinAnchor" }) as? AnchorEntity else {
            return
        }
        anchor.children.removeAll()
        updateMannequinEntities(in: anchor)
    }

    private func updateMannequinEntities(in anchor: AnchorEntity) {
        let mannequinMaterial = SimpleMaterial(
            color: UIColor.systemGray4.withAlphaComponent(0.85),
            roughness: 0.4,
            isMetallic: false
        )

        // 1. Manken Standı (Taban)
        let baseMesh = MeshResource.generateBox(width: 0.36, height: 0.03, depth: 0.26, cornerRadius: 0.01)
        let baseEntity = ModelEntity(mesh: baseMesh, materials: [mannequinMaterial])
        baseEntity.position = SIMD3<Float>(0, 0.015, 0)
        anchor.addChild(baseEntity)

        // 2. Bacaklar
        let legMesh = MeshResource.generateBox(width: 0.10, height: 0.52, depth: 0.10, cornerRadius: 0.04)
        let leftLeg = ModelEntity(mesh: legMesh, materials: [mannequinMaterial])
        leftLeg.position = SIMD3<Float>(-0.07, 0.30, 0)
        let rightLeg = ModelEntity(mesh: legMesh, materials: [mannequinMaterial])
        rightLeg.position = SIMD3<Float>(0.07, 0.30, 0)
        anchor.addChild(leftLeg)
        anchor.addChild(rightLeg)

        // 3. Gövde (Torso)
        let torsoMesh = MeshResource.generateBox(width: 0.30, height: 0.44, depth: 0.14, cornerRadius: 0.05)
        let torsoEntity = ModelEntity(mesh: torsoMesh, materials: [mannequinMaterial])
        torsoEntity.position = SIMD3<Float>(0, 0.78, 0)
        anchor.addChild(torsoEntity)

        // 4. Baş (Head)
        let headMesh = MeshResource.generateSphere(radius: 0.085)
        let headEntity = ModelEntity(mesh: headMesh, materials: [mannequinMaterial])
        headEntity.position = SIMD3<Float>(0, 1.12, 0)
        anchor.addChild(headEntity)

        // 5. Kıyafet Katmanlarını 3D Mankenin Ön Yüzeyine Giydir
        if let shoesData = shoesImageData,
           let shoesPlane = createClothingPlaneEntity(from: shoesData, width: 0.28, height: 0.16) {
            shoesPlane.position = SIMD3<Float>(0, 0.10, 0.075)
            anchor.addChild(shoesPlane)
        }

        if let bottomData = bottomImageData,
           let bottomPlane = createClothingPlaneEntity(from: bottomData, width: 0.36, height: 0.52) {
            bottomPlane.position = SIMD3<Float>(0, 0.38, 0.08)
            anchor.addChild(bottomPlane)
        }

        if let topData = topImageData,
           let topPlane = createClothingPlaneEntity(from: topData, width: 0.42, height: 0.46) {
            topPlane.position = SIMD3<Float>(0, 0.78, 0.085)
            anchor.addChild(topPlane)
        }

        if let outerData = outerwearImageData,
           let outerPlane = createClothingPlaneEntity(from: outerData, width: 0.46, height: 0.48) {
            outerPlane.position = SIMD3<Float>(0, 0.78, 0.095)
            anchor.addChild(outerPlane)
        }
    }

    /// Şeffaf PNG kıyafet verisini RealityKit 3D düzlem dokusuna (TextureResource) dönüştürür
    private func createClothingPlaneEntity(from data: Data, width: Float, height: Float) -> ModelEntity? {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage,
              let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) else {
            return nil
        }

        let mesh = MeshResource.generatePlane(width: width, height: height)
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))

        return ModelEntity(mesh: mesh, materials: [material])
    }
}

#Preview {
    VirtualTryOnView()
        .modelContainer(for: [ClothingItem.self, SavedOutfit.self], inMemory: true)
}

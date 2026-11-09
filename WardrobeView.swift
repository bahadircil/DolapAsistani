import SwiftUI
import SwiftData

struct WardrobeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var clothingItems: [ClothingItem]

    private let categories = ["Üst", "Alt", "Ayakkabı", "Dış Giyim"]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(categories, id: \.self) { category in
                        let itemsInCategory = clothingItems.filter { $0.category == category }
                        CategoryRowSection(
                            category: category,
                            items: itemsInCategory,
                            onDelete: deleteItem
                        )
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dolabım")
        }
    }

    private func deleteItem(_ item: ClothingItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}

private struct CategoryRowSection: View {
    let category: String
    let items: [ClothingItem]
    let onDelete: (ClothingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(category, systemImage: iconName(for: category))
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Text("\(items.count) parça")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            if items.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: iconName(for: category))
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("Bu kategoride henüz kıyafet yok")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(items) { item in
                            ClothingCardView(item: item)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(item)
                                    } label: {
                                        Label("Dolaptan Sil", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func iconName(for category: String) -> String {
        switch category {
        case "Üst": return "tshirt.fill"
        case "Alt": return "figure.walk"
        case "Ayakkabı": return "shoe.fill"
        case "Dış Giyim": return "jacket.fill"
        default: return "tag.fill"
        }
    }
}

private struct ClothingCardView: View {
    let item: ClothingItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(width: 145, height: 165)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)

                if let uiImage = UIImage(data: item.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 125, height: 145)
                        .padding(10)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: item.dominantColorHex))
                    .frame(width: 10, height: 10)
                Text(item.styleTag)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(8)
        }
    }
}

#Preview {
    WardrobeView()
        .modelContainer(for: [ClothingItem.self, SavedOutfit.self], inMemory: true)
}


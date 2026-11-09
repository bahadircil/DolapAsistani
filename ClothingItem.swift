import Foundation
import SwiftData

@Model
final class ClothingItem {
    var id: UUID
    @Attribute(.externalStorage) var imageData: Data
    var category: String
    var styleTag: String
    var dominantColorHex: String

    init(
        id: UUID = UUID(),
        imageData: Data,
        category: String,
        styleTag: String = "Günlük",
        dominantColorHex: String = "#808080"
    ) {
        self.id = id
        self.imageData = imageData
        self.category = category
        self.styleTag = styleTag
        self.dominantColorHex = dominantColorHex
    }
}

@Model
final class SavedOutfit {
    var id: UUID
    var createdAt: Date
    var styleTag: String
    var weatherSummary: String
    var topID: UUID?
    var bottomID: UUID?
    var shoesID: UUID?
    var outerwearID: UUID?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        styleTag: String,
        weatherSummary: String,
        topID: UUID?,
        bottomID: UUID?,
        shoesID: UUID?,
        outerwearID: UUID? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.styleTag = styleTag
        self.weatherSummary = weatherSummary
        self.topID = topID
        self.bottomID = bottomID
        self.shoesID = shoesID
        self.outerwearID = outerwearID
    }
}

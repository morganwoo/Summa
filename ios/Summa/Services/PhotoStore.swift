import Foundation
import UIKit

/// Progress photos on disk. They stay in the app's own protected storage, are never uploaded,
/// and leave the device only if the person adds one to a card and shares it themselves.
enum PhotoStore {
    private static var directory: URL? {
        // The developer preview keeps its photos in a temporary folder, apart from the real diary.
        if DevSandbox.isActive {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SummaPreviewPhotos", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let folder = base.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Empties the developer preview's temporary photo folder.
    static func clearPreview() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("SummaPreviewPhotos", isDirectory: true))
    }

    /// Stores a downscaled JPEG and returns its file name.
    static func save(_ data: Data) -> String? {
        guard let directory, let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            // Readable after the first unlock, so a photo saved moments before the screen locks is not lost.
            try jpeg.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch {
            return nil
        }
    }

    static func image(_ fileName: String) -> UIImage? {
        guard let directory else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(fileName).path)
    }

    static func delete(_ fileName: String) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    static func deleteAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

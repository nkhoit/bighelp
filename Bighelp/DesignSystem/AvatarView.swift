import ImageIO
import SwiftUI
import UIKit

enum AvatarFileURL {
    static func resolve(fileName: String?, in directory: URL?) -> URL? {
        guard
            let fileName,
            !fileName.isEmpty,
            fileName != ".",
            fileName != "..",
            !fileName.contains("/"),
            !fileName.contains("\\")
        else {
            return nil
        }
        guard let directory else { return nil }
        return directory.appending(path: fileName, directoryHint: .notDirectory)
    }
}

struct AvatarView: View {
    enum Kind { case agent, person }

    let stableID: String
    let displayName: String
    let imageURL: URL?
    var size: CGFloat
    var kind: Kind
    var state: AgentLiveState?

    init(
        stableID: String,
        displayName: String,
        imageURL: URL? = nil,
        size: CGFloat = 44,
        kind: Kind = .agent,
        state: AgentLiveState? = nil
    ) {
        self.stableID = stableID
        self.displayName = displayName
        self.imageURL = imageURL
        self.size = size
        self.kind = kind
        self.state = state
    }

    var body: some View {
        Group {
            if let imageURL, let image = AvatarImageCache.image(at: imageURL, side: size, scale: displayScale) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
                    .overlay(alignment: .topTrailing) {
                        if state == .nudge {
                            Circle().fill(EmberBrand.ember)
                                .frame(width: size * 0.24, height: size * 0.24)
                                .overlay(Circle().stroke(.white, lineWidth: max(1, size * 0.03)))
                        }
                    }
            } else if kind == .agent {
                // Agents are organic blobs and orbs; the avatar is their live status.
                AgentPersonaAvatar(persona: AgentPersona(stableID: stableID), state: state ?? .idle, size: size)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: size, height: size)
                    .background(theme.incomingMessageBackground, in: .circle)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(displayName)
        .accessibilityIdentifier("avatar.\(stableID)")
    }

    private var initials: String {
        let words = displayName.split(whereSeparator: \.isWhitespace)
        let characters = words.prefix(2).compactMap { $0.first }.map(String.init)
        return characters.isEmpty ? "?" : characters.joined().uppercased()
    }

    @BighelpThemeReader private var theme
    @Environment(\.displayScale) private var displayScale
}

/// Agent pictures, read and shrunk to their circle once each. A body runs on
/// every update (each streamed word under a chat header), and reading and
/// decoding the full file there every time held up the main thread.
@MainActor
enum AvatarImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func image(at url: URL, side: CGFloat, scale: CGFloat) -> UIImage? {
        let path = url.bighelpFileSystemPath
        // A new picture can be saved under the same name, so its date and size are in the key.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let pixels = max(1, Int((side * max(scale, 1)).rounded(.up)))
        let key = "\(path)|\(modified)|\(bytes)|\(pixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        // The circle fills with the short side, so the long side gets its share too.
        var maximumPixels = pixels
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           min(width, height) > 0 {
            let aspect = Double(max(width, height)) / Double(min(width, height))
            maximumPixels = Int((Double(pixels) * min(aspect, 4)).rounded(.up))
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = UIImage(cgImage: thumbnail)
        cache.setObject(image, forKey: key)
        return image
    }
}

struct AvatarStack: View {
    struct Avatar: Identifiable {
        let stableID: String
        let displayName: String
        let imageURL: URL?

        var id: String { stableID }
    }

    let avatars: [Avatar]
    var size: CGFloat
    var outlineColor: Color

    init(avatars: [Avatar], size: CGFloat = 32, outlineColor: Color = .white) {
        self.avatars = avatars
        self.size = size
        self.outlineColor = outlineColor
    }

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(avatars) { avatar in
                AvatarView(
                    stableID: avatar.stableID,
                    displayName: avatar.displayName,
                    imageURL: avatar.imageURL,
                    size: size
                )
                .overlay(Circle().stroke(outlineColor, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

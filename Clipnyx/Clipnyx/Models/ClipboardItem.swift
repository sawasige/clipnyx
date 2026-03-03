import AppKit
import CryptoKit
import UniformTypeIdentifiers

struct RepresentationInfo: Sendable, Equatable {
    let type: String
    let size: Int
}

struct ClipboardItem: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: ClipboardContentCategory
    let previewText: String
    let thumbnailData: Data?
    let totalDataSize: Int
    let contentHash: Data
    let representationInfos: [RepresentationInfo]

    private static let maxCaptureSize: Int = 500 * 1024 * 1024 // 500MB safety cap
    private static let maxThumbnailDimension: CGFloat = 200.0

    // MARK: - Capture from NSPasteboard

    static func capture(from pasteboard: NSPasteboard) -> (item: ClipboardItem, representations: [PasteboardRepresentation])? {
        guard let types = pasteboard.types, !types.isEmpty else { return nil }

        // Collect all representations
        var reps: [PasteboardRepresentation] = []
        var totalSize = 0
        for type in types {
            guard let data = pasteboard.data(forType: type) else { continue }
            totalSize += data.count
            if totalSize > maxCaptureSize { break }
            reps.append(PasteboardRepresentation(type: type, data: data))
        }
        guard !reps.isEmpty else { return nil }

        // Determine category with priority
        let typeSet = Set(types.map(\.rawValue))
        let category = classifyCategory(types: typeSet, pasteboard: pasteboard)

        // Generate preview text
        let previewText = generatePreviewText(
            category: category,
            pasteboard: pasteboard,
            types: typeSet
        )

        // Generate thumbnail for images/PDFs
        let thumbnailData = generateThumbnail(
            category: category,
            pasteboard: pasteboard
        )

        // Compute content hash (SHA256 of all representation data)
        var hasher = SHA256()
        for rep in reps {
            hasher.update(data: rep.data)
        }
        let contentHash = Data(hasher.finalize())

        let item = ClipboardItem(
            id: UUID(),
            timestamp: Date(),
            category: category,
            previewText: previewText,
            thumbnailData: thumbnailData,
            totalDataSize: reps.reduce(0) { $0 + $1.data.count },
            contentHash: contentHash,
            representationInfos: reps.map { RepresentationInfo(type: $0.typeRawValue, size: $0.data.count) }
        )

        return (item, reps)
    }

    // MARK: - Category Classification (11-level priority)

    private static func classifyCategory(types: Set<String>, pasteboard: NSPasteboard) -> ClipboardContentCategory {
        // 1. File URLs (Finder のファイルコピーは tiff アイコンも含むため最優先)
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            return .fileURL
        }

        // 2. Color
        if types.contains(NSPasteboard.PasteboardType.color.rawValue) {
            return .color
        }

        // 3. PDF
        if types.contains(NSPasteboard.PasteboardType.pdf.rawValue) || types.contains("com.adobe.pdf") {
            return .pdf
        }

        // 4. Image types (テキストが同時に含まれる場合は画像扱いしない)
        let hasText = types.contains(NSPasteboard.PasteboardType.string.rawValue)
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        for imgType in imageTypes {
            if types.contains(imgType.rawValue) && !hasText {
                return .image
            }
        }
        if (types.contains("public.jpeg") || types.contains("public.heic")) && !hasText {
            return .image
        }

        // 5. URL (check before rich text)
        if types.contains(NSPasteboard.PasteboardType.URL.rawValue) {
            if let str = pasteboard.string(forType: .string),
               let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)),
               url.scheme != nil {
                return .url
            }
        }

        // 6. HTML
        if types.contains(NSPasteboard.PasteboardType.html.rawValue) || types.contains("public.html") {
            return .html
        }

        // 7. RTF / RTFD
        if types.contains(NSPasteboard.PasteboardType.rtf.rawValue) ||
           types.contains(NSPasteboard.PasteboardType.rtfd.rawValue) {
            return .richText
        }

        // 8. CSV / TSV
        if types.contains("public.comma-separated-values-text") ||
           types.contains("public.tab-separated-values-text") {
            return .csv
        }

        // 9. Source code
        if types.contains("public.source-code") || types.contains("com.apple.dt.document.source-code") {
            return .sourceCode
        }

        // 10. Plain text (check content for source code / URL patterns)
        if types.contains(NSPasteboard.PasteboardType.string.rawValue) {
            if let text = pasteboard.string(forType: .string) {
                // Check if it looks like a URL
                if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   let scheme = url.scheme,
                   ["http", "https", "ftp", "ssh"].contains(scheme) {
                    return .url
                }
                // Check if it looks like source code
                if looksLikeSourceCode(text) {
                    return .sourceCode
                }
            }
            return .plainText
        }

        // 11. Other
        return .other
    }

    private static func looksLikeSourceCode(_ text: String) -> Bool {
        let codePatterns = [
            "func ", "class ", "struct ", "enum ", "import ",
            "def ", "return ", "if (", "for (", "while (",
            "const ", "let ", "var ", "function ",
            "public ", "private ", "protected ",
            "#!/", "=> {", "-> {",
        ]
        let lines = text.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return false }
        var matchCount = 0
        for line in lines.prefix(20) {
            for pattern in codePatterns {
                if line.contains(pattern) {
                    matchCount += 1
                    break
                }
            }
        }
        return matchCount >= 2
    }

    // MARK: - Preview Text Generation

    private static func generatePreviewText(
        category: ClipboardContentCategory,
        pasteboard: NSPasteboard,
        types: Set<String>
    ) -> String {
        switch category {
        case .plainText, .sourceCode, .csv:
            if let text = pasteboard.string(forType: .string) {
                return String(text.prefix(500))
            }
            return String(localized: "(No Text)")

        case .richText:
            if let text = pasteboard.string(forType: .string) {
                return String(text.prefix(500))
            }
            if let rtfData = pasteboard.data(forType: .rtf),
               let attrStr = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                return String(attrStr.string.prefix(500))
            }
            return String(localized: "(Rich Text)")

        case .html:
            if let text = pasteboard.string(forType: .string) {
                return String(text.prefix(500))
            }
            if let htmlData = pasteboard.data(forType: .html),
               let htmlStr = String(data: htmlData, encoding: .utf8) {
                return String(htmlStr.prefix(500))
            }
            return String(localized: "(HTML)")

        case .url:
            if let text = pasteboard.string(forType: .string) {
                return String(text.prefix(500))
            }
            return String(localized: "(URL)")

        case .image:
            if let tiffData = pasteboard.data(forType: .tiff),
               let image = NSImage(data: tiffData) {
                let size = image.size
                return String(localized: "Image \(Int(size.width))×\(Int(size.height))")
            }
            return String(localized: "Image")

        case .pdf:
            return String(localized: "PDF Document")

        case .fileURL:
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                let names = urls.prefix(5).map(\.lastPathComponent)
                let result = names.joined(separator: ", ")
                if urls.count > 5 {
                    return result + " " + String(localized: "and \(urls.count - 5) more")
                }
                return result
            }
            return String(localized: "(File)")

        case .color:
            if let colorData = pasteboard.data(forType: .color),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
                let rgb = color.usingColorSpace(.sRGB)
                if let rgb {
                    return String(
                        format: "#%02X%02X%02X",
                        Int(rgb.redComponent * 255),
                        Int(rgb.greenComponent * 255),
                        Int(rgb.blueComponent * 255)
                    )
                }
            }
            return String(localized: "(Color)")

        case .other:
            return String(localized: "(Data)")
        }
    }

    // MARK: - Thumbnail Generation

    private static func generateThumbnail(
        category: ClipboardContentCategory,
        pasteboard: NSPasteboard
    ) -> Data? {
        switch category {
        case .image:
            guard let tiffData = pasteboard.data(forType: .tiff),
                  let image = NSImage(data: tiffData) else { return nil }
            return resizedPNGData(from: image)

        case .pdf:
            guard let pdfData = pasteboard.data(forType: .pdf) else { return nil }
            guard let imageRep = NSPDFImageRep(data: pdfData) else { return nil }
            let image = NSImage(size: imageRep.bounds.size)
            image.addRepresentation(imageRep)
            return resizedPNGData(from: image)

        default:
            return nil
        }
    }

    private static func resizedPNGData(from image: NSImage) -> Data? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let maxDim = maxThumbnailDimension
        let scale: CGFloat
        if originalSize.width > maxDim || originalSize.height > maxDim {
            scale = min(maxDim / originalSize.width, maxDim / originalSize.height)
        } else {
            scale = 1.0
        }

        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
    }

    // MARK: - Content Comparison

    func hasSameContent(as other: ClipboardItem) -> Bool {
        contentHash == other.contentHash
    }

    // MARK: - Formatted Data Size

    var formattedDataSize: String {
        let bytes = totalDataSize
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

import AppKit
import Vision
import os

/// 画像・PDF からテキストを抽出する OCR ユーティリティ。
/// Vision フレームワークでオンデバイス実行し、外部送信は一切行わない。
enum TextRecognizer {
    private static let logger = Logger(subsystem: "com.himatsubu.Clipnyx", category: "TextRecognizer")

    /// OCR にかける画像の最大辺。これより大きい場合は縮小して処理を軽くする
    /// （文字認識の精度を大きく損なわない範囲で速度を確保する）。
    private static let maxDimension: CGFloat = 2500

    /// 画像データから文字を認識する。認識できなければ空文字を返す。
    /// ブロッキング処理のため呼び出し側はバックグラウンドの Task から呼ぶこと。
    static func recognizeText(imageData: Data) -> String {
        guard let image = NSImage(data: imageData),
              let cgImage = downscaledCGImage(from: image) else { return "" }
        return recognize(cgImage: cgImage)
    }

    /// PDF データの1ページ目から文字を認識する。
    static func recognizeText(pdfData: Data) -> String {
        guard let rep = NSPDFImageRep(data: pdfData) else { return "" }
        let image = NSImage(size: rep.bounds.size)
        image.addRepresentation(rep)
        guard let cgImage = downscaledCGImage(from: image) else { return "" }
        return recognize(cgImage: cgImage)
    }

    // MARK: - Private

    private static func recognize(cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ja", "en"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("OCR failed: \(error.localizedDescription)")
            return ""
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// NSImage を CGImage 化し、大きすぎる場合は縮小する。
    private static func downscaledCGImage(from image: NSImage) -> CGImage? {
        guard var cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        let longest = max(width, height)
        guard longest > maxDimension else { return cgImage }

        let scale = maxDimension / longest
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)
        guard newWidth > 0, newHeight > 0,
              let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return cgImage
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        if let scaled = context.makeImage() {
            cgImage = scaled
        }
        return cgImage
    }
}

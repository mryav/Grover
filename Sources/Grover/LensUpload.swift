import AppKit
import UniformTypeIdentifiers

/// Builds a Google Lens image-search request (the same multipart upload that
/// lens.google.com's own "upload an image" uses). Best effort: the endpoint is
/// not a public API.
enum LensUpload {
    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to search with Google Lens"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func request(for imageURL: URL) -> URLRequest? {
        guard let image = NSImage(contentsOf: imageURL),
              let (jpeg, size) = jpegData(image, maxDimension: 1000)
        else { return nil }

        let boundary = "Grover-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"encoded_image\"; filename=\"image.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        body.append("\r\n")
        field("processed_image_dimensions", "\(Int(size.width)),\(Int(size.height))")
        body.append("--\(boundary)--\r\n")

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        var request = URLRequest(url: URL(string: "https://lens.google.com/v3/upload?hl=en&st=\(timestamp)")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private static func jpegData(_ image: NSImage, maxDimension: CGFloat) -> (Data, CGSize)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxDimension / CGFloat(max(cg.width, cg.height)))
        let size = CGSize(width: (CGFloat(cg.width) * scale).rounded(), height: (CGFloat(cg.height) * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSImage(cgImage: cg, size: size).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        return (data, size)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

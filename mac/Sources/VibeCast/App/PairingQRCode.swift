import AppKit
import CoreImage

/// Encodes locally; the pairing URL never leaves the Mac to generate a QR image.
enum PairingQRCode {
    static func image(for url: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        // Four white modules on every edge, including in dark mode.
        let extent = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        let scale = max(1, floor(244 / extent.width))
        let output = code.composited(over: white).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let bitmap = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
    }
}

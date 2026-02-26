import AppKit
import CoreImage

enum QRCodeGenerator {
    static func generate(from string: String, size: CGFloat = 200) -> NSImage? {
        guard let data = string.data(using: .utf8),
            let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = qrFilter.outputImage else { return nil }

        // Map transparent light modules to white and dark modules to black
        // so the QR code is always scannable regardless of macOS appearance
        guard let falseColor = CIFilter(name: "CIFalseColor") else { return nil }
        falseColor.setValue(ciImage, forKey: kCIInputImageKey)
        falseColor.setValue(CIColor.black, forKey: "inputColor0")
        falseColor.setValue(CIColor.white, forKey: "inputColor1")
        guard let coloredImage = falseColor.outputImage else { return nil }

        let extent = coloredImage.extent.width
        let intScale = max(1, Int(floor(size / extent)))
        let scaleFactor = CGFloat(intScale)
        let scaled = coloredImage.transformed(
            by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        let scaledSize = scaleFactor * extent
        let padding = floor((size - scaledSize) / 2)

        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: NSSize(width: size, height: size))
        nsImage.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        rep.draw(
            in: NSRect(x: padding, y: padding, width: scaledSize, height: scaledSize))
        nsImage.unlockFocus()
        return nsImage
    }
}

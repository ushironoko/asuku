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

        let scale = size / coloredImage.extent.width
        let scaled = coloredImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}

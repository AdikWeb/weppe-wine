import CoreGraphics
import Foundation
import ImageIO

let bytesPerPixel = 4
let darkChannelLimit = 16
let brightLumaLimit = 160
let lumaWeights = (red: 299, green: 587, blue: 114, scale: 1000)
let permille = 1000
let screencapture = "/usr/sbin/screencapture"

func fail(_ message: String) -> Never {
    print("error: \(message)")
    exit(2)
}

func onScreenWindows() -> [[String: Any]] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
}

func listWindows() {
    for window in onScreenWindows() {
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        let name = window[kCGWindowName as String] as? String ?? ""
        print("  \(id) \(owner): \(name)")
    }
}

func findWindow(titled title: String) -> (id: Int, owner: String, bounds: String)? {
    for window in onScreenWindows() {
        let name = window[kCGWindowName as String] as? String ?? ""
        guard name.localizedCaseInsensitiveContains(title),
              let id = window[kCGWindowNumber as String] as? Int
        else { continue }
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return (id, owner, "\(bounds)")
    }
    return nil
}

func capture(windowID: Int, to path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: screencapture)
    process.arguments = ["-x", "-o", "-l\(windowID)", path]
    do { try process.run() } catch { fail("screencapture: \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("screencapture exited with \(process.terminationStatus)") }
}

func describe(_ path: String) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("could not read \(path)") }
    let rowBytes = image.width * bytesPerPixel
    var data = [UInt8](repeating: 0, count: rowBytes * image.height)
    let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
    }
    guard drawn else { fail("could not decode \(path)") }
    let pixelCount = image.width * image.height
    var dark = 0
    var bright = 0
    for index in 0..<pixelCount {
        let offset = index * bytesPerPixel
        let red = Int(data[offset]), green = Int(data[offset + 1]), blue = Int(data[offset + 2])
        if red < darkChannelLimit && green < darkChannelLimit && blue < darkChannelLimit { dark += 1 }
        let luma = (red * lumaWeights.red + green * lumaWeights.green + blue * lumaWeights.blue) / lumaWeights.scale
        if luma > brightLumaLimit { bright += 1 }
    }
    print("size \(image.width)x\(image.height)")
    print("dark permille \(dark * permille / max(pixelCount, 1))")
    print("bright permille \(bright * permille / max(pixelCount, 1))")
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: window-shot <window-title-part> <image.png>") }
guard let window = findWindow(titled: arguments[1]) else {
    print("no window titled \(arguments[1]); on screen:")
    listWindows()
    exit(1)
}
print("window \(window.id) of \(window.owner) at \(window.bounds)")
capture(windowID: window.id, to: arguments[2])
describe(arguments[2])

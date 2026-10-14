import CoreGraphics
import Foundation
import ImageIO

let bytesPerPixel = 4
let channelTolerance = 40
let hexColorLength = 6

func fail(_ message: String) -> Never {
    print("error: \(message)")
    exit(2)
}

func parse(_ hex: String) -> [Int] {
    guard hex.count == hexColorLength, let value = Int(hex, radix: 16) else { fail("\(hex) is not an rrggbb color") }
    return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]
}

func pixels(of path: String) -> (data: [UInt8], count: Int) {
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
    return (data, image.width * image.height)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: count-colors <image.png> <rrggbb>...") }
let colors = arguments.dropFirst(2).map { ($0, parse($0)) }
let (data, pixelCount) = pixels(of: arguments[1])
var counts = [Int](repeating: 0, count: colors.count)
for index in 0..<pixelCount {
    let offset = index * bytesPerPixel
    for (colorIndex, color) in colors.enumerated() {
        let channels = color.1
        if abs(Int(data[offset]) - channels[0]) <= channelTolerance,
           abs(Int(data[offset + 1]) - channels[1]) <= channelTolerance,
           abs(Int(data[offset + 2]) - channels[2]) <= channelTolerance {
            counts[colorIndex] += 1
        }
    }
}
for (colorIndex, color) in colors.enumerated() {
    print("\(color.0) \(counts[colorIndex])")
}

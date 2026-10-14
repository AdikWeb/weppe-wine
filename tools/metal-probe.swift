import AppKit
import ImageIO
import Metal
import QuartzCore

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

let textureSize = 64
let bytesPerPixel = 4
let offscreenClear = MTLClearColor(red: 0, green: 0, blue: 1, alpha: 1)
let redInBGRA: [UInt8] = [0, 0, 255, 255]
let windowClear = MTLClearColor(red: 0, green: 1, blue: 0, alpha: 1)
let windowFrame = NSRect(x: 200, y: 200, width: 320, height: 240)
let settleTime: TimeInterval = 0.5
let presentationTime: TimeInterval = 2
let eventPollInterval: TimeInterval = 0.05
let brightChannel: UInt8 = 200
let darkChannel: UInt8 = 60
let screencapture = "/usr/sbin/screencapture"

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Vertex { float4 position [[position]]; };

vertex Vertex vertex_main(uint id [[vertex_id]]) {
    const float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    Vertex out;
    out.position = float4(corners[id], 0, 1);
    return out;
}

fragment float4 fragment_main() { return float4(1, 0, 0, 1); }
"""

func describe(_ device: MTLDevice) {
    print("devices: \(MTLCopyAllDevices().map(\.name))")
    print("default device: \(device.name)")
    print("low power: \(device.isLowPower), headless: \(device.isHeadless), unified memory: \(device.hasUnifiedMemory)")
    let families: [(String, MTLGPUFamily)] = [
        ("apple6", .apple6), ("apple7", .apple7), ("apple8", .apple8), ("apple9", .apple9),
        ("mac2", .mac2), ("common3", .common3), ("metal3", .metal3),
    ]
    for (name, family) in families {
        print("family \(name): \(device.supportsFamily(family))")
    }
    print("argument buffers tier 2: \(device.argumentBuffersSupport == .tier2)")
    print("raytracing: \(device.supportsRaytracing)")
    print("max buffer length: \(device.maxBufferLength)")
    print("recommended max working set: \(device.recommendedMaxWorkingSetSize)")
}

func makePipeline(_ device: MTLDevice, format: MTLPixelFormat) throws -> MTLRenderPipelineState {
    let library = try device.makeLibrary(source: shaderSource, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
    descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
    descriptor.colorAttachments[0].pixelFormat = format
    return try device.makeRenderPipelineState(descriptor: descriptor)
}

func clearingPass(_ texture: MTLTexture, to color: MTLClearColor) -> MTLRenderPassDescriptor {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = color
    pass.colorAttachments[0].storeAction = .store
    return pass
}

func finish(_ commands: MTLCommandBuffer) throws {
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error {
        throw ProbeFailure(description: "command buffer failed: \(error)")
    }
}

func renderOffscreen(_ device: MTLDevice, _ queue: MTLCommandQueue) throws {
    let format = MTLPixelFormat.bgra8Unorm
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: textureSize, height: textureSize, mipmapped: false)
    descriptor.usage = [.renderTarget]
    descriptor.storageMode = .private
    let rowBytes = textureSize * bytesPerPixel
    guard let texture = device.makeTexture(descriptor: descriptor),
          let readback = device.makeBuffer(length: rowBytes * textureSize, options: .storageModeShared),
          let commands = queue.makeCommandBuffer(),
          let encoder = commands.makeRenderCommandEncoder(descriptor: clearingPass(texture, to: offscreenClear))
    else { throw ProbeFailure(description: "could not create the offscreen target") }
    encoder.setRenderPipelineState(try makePipeline(device, format: format))
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    guard let blit = commands.makeBlitCommandEncoder() else {
        throw ProbeFailure(description: "could not create a blit encoder")
    }
    blit.copy(
        from: texture, sourceSlice: 0, sourceLevel: 0,
        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceSize: MTLSize(width: textureSize, height: textureSize, depth: 1),
        to: readback, destinationOffset: 0,
        destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * textureSize)
    blit.endEncoding()
    try finish(commands)
    let center = (textureSize / 2) * rowBytes + (textureSize / 2) * bytesPerPixel
    let bytes = readback.contents().assumingMemoryBound(to: UInt8.self)
    let pixel = Array(UnsafeBufferPointer(start: bytes + center, count: bytesPerPixel))
    print("offscreen center pixel (BGRA): \(pixel)")
    guard pixel == redInBGRA else {
        throw ProbeFailure(description: "the red triangle was not drawn")
    }
}

func pumpEvents(for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        let event = NSApp.nextEvent(
            matching: .any, until: Date().addingTimeInterval(eventPollInterval), inMode: .default, dequeue: true)
        if let event {
            NSApp.sendEvent(event)
        }
    }
}

func openMetalWindow(_ device: MTLDevice) -> (NSWindow, CAMetalLayer) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.finishLaunching()
    let window = NSWindow(contentRect: windowFrame, styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "metal-probe"
    let layer = CAMetalLayer()
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    let view = NSView(frame: NSRect(origin: .zero, size: windowFrame.size))
    view.layer = layer
    view.wantsLayer = true
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    pumpEvents(for: settleTime)
    let scale = window.backingScaleFactor
    layer.drawableSize = CGSize(width: windowFrame.width * scale, height: windowFrame.height * scale)
    return (window, layer)
}

func capture(windowNumber: Int, to path: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: screencapture)
    process.arguments = ["-x", "-o", "-l\(windowNumber)", path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ProbeFailure(description: "screencapture exited with \(process.terminationStatus)")
    }
}

func centerPixel(of path: String) throws -> [UInt8] {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw ProbeFailure(description: "could not read \(path)") }
    let width = image.width
    let height = image.height
    let rowBytes = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: rowBytes * height)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { throw ProbeFailure(description: "could not decode \(path)") }
    print("window capture: \(width)x\(height)")
    let offset = (height / 2) * rowBytes + (width / 2) * bytesPerPixel
    return Array(pixels[offset..<offset + bytesPerPixel])
}

func renderInWindow(_ device: MTLDevice, _ queue: MTLCommandQueue, capturePath: String) throws {
    let (window, layer) = openMetalWindow(device)
    guard let drawable = layer.nextDrawable() else {
        throw ProbeFailure(description: "CAMetalLayer gave no drawable")
    }
    guard let commands = queue.makeCommandBuffer(),
          let encoder = commands.makeRenderCommandEncoder(descriptor: clearingPass(drawable.texture, to: windowClear))
    else { throw ProbeFailure(description: "could not encode the window frame") }
    encoder.endEncoding()
    commands.present(drawable)
    try finish(commands)
    pumpEvents(for: presentationTime)
    try capture(windowNumber: window.windowNumber, to: capturePath)
    let pixel = try centerPixel(of: capturePath)
    print("window center pixel (RGBA): \(pixel)")
    guard pixel[0] < darkChannel, pixel[1] > brightChannel, pixel[2] < darkChannel else {
        throw ProbeFailure(description: "the window does not show the green frame")
    }
}

guard CommandLine.arguments.count == 2 else {
    print("usage: metal-probe <window-capture.png>")
    exit(2)
}
let capturePath = CommandLine.arguments[1]
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    print("FAIL: no Metal device")
    exit(1)
}
describe(device)

let checks: [(String, () throws -> Void)] = [
    ("offscreen render", { try renderOffscreen(device, queue) }),
    ("window presentation", { try renderInWindow(device, queue, capturePath: capturePath) }),
]
var failed = 0
for (name, check) in checks {
    do {
        try check()
        print("\(name): ok")
    } catch {
        print("\(name): FAIL: \(error)")
        failed += 1
    }
}
exit(failed == 0 ? 0 : 1)

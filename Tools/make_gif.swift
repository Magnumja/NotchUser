// Turns a screen recording into a looping GIF for the README.
// Usage: swift Tools/make_gif.swift recording.mov Assets/demo.gif [width] [fps]
import AVFoundation
import AppKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let width = args.count > 3 ? Double(args[3])! : 800
let fps = args.count > 4 ? Double(args[4])! : 8

let asset = AVURLAsset(url: input)
let duration = CMTimeGetSeconds(asset.duration)
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: width, height: width * 4)
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero

let frames = Int(duration * fps)
guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
    fatalError("can't write \(output.path)")
}
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary

for i in 0..<frames {
    let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
    guard let img = try? gen.copyCGImage(at: t, actualTime: nil) else { continue }
    CGImageDestinationAddImage(dest, img, frameProps)
}
guard CGImageDestinationFinalize(dest) else { fatalError("GIF failed") }
print("gif: \(output.path) (\(frames) frames)")

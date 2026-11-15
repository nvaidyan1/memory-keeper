// Joins a folder of numbered PNG frames into an H.264 .mp4.
// Usage: swift encode_movie.swift <frames folder> <output.mp4> <fps>
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let fps = Int32(args[3]) else {
    print("usage: swift encode_movie.swift <frames folder> <output.mp4> <fps>")
    exit(1)
}
let folder = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard let first = files.first, let firstImage = NSImage(contentsOf: first)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("no frames found")
    exit(1)
}
let width = firstImage.width, height = firstImage.height
try? FileManager.default.removeItem(at: output)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for (index, file) in files.enumerated() {
    guard let image = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let pixels = buffer else { continue }
    CVPixelBufferLockBaseAddress(pixels, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    CVPixelBufferUnlockBaseAddress(pixels, [])
    while !input.isReadyForMoreMediaData { usleep(2000) }
    adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print("wrote \(files.count) frames to \(output.path)")

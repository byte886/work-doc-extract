// ocr_vision.swift — macOS Vision 框架单图 OCR
// 用法：swift scripts/ocr_vision.swift <图片路径>
//   识别文本输出到 stdout；无文字时输出 "未识别到文字"
// 说明：图片型 PDF 先由 PyMuPDF 转 PNG，再用本工具逐页识别。
//   中英混合（zh-Hans + en-US），accurate 模式，开启语言纠错。
import Vision
import AppKit
import Foundation

func recognizeText(in imagePath: String) -> String {
    guard let image = NSImage(contentsOfFile: imagePath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return "ERROR: 无法加载图片"
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do { try handler.perform([request]) } catch { return "ERROR: \(error)" }
    var lines: [String] = []
    for observation in request.results ?? [] {
        if let candidate = observation.topCandidates(1).first {
            lines.append(candidate.string)
        }
    }
    return lines.isEmpty ? "未识别到文字" : lines.joined(separator: "\n")
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("用法: ocr_vision.swift <图片路径>\n".data(using: .utf8)!)
    exit(2)
}
print(recognizeText(in: args[1]))

import AppKit
import Foundation

enum ScreenshotCaptureService {
    static func captureToClipboard() async throws {
        try await runScreencapture(arguments: ["-i", "-c"])
    }

    static func captureAndSave(in folderURL: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let destinationURL = uniqueScreenshotURL(in: folderURL)

        do {
            try await runScreencapture(arguments: ["-i", "-x", destinationURL.path(percentEncoded: false)])
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) else {
            throw CancellationError()
        }

        return destinationURL
    }

    static func savePNGData(_ data: Data, in folderURL: URL, kind: CaptureKind = .saved) throws -> URL {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let destinationURL = uniqueScreenshotURL(in: folderURL, kind: kind)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func save(_ image: NSImage, in folderURL: URL, kind: CaptureKind = .saved) throws -> URL {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let destinationURL = uniqueScreenshotURL(in: folderURL, kind: kind)
        try ImageEditingService.write(image, to: destinationURL)
        return destinationURL
    }

    private static func runScreencapture(arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = arguments
            process.terminationHandler = { process in
                let status = process.terminationStatus

                if status == 0 {
                    continuation.resume()
                } else if status == 1 {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: ScreenshotCaptureError.commandFailed(status))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func uniqueScreenshotURL(in folderURL: URL, kind: CaptureKind = .saved) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

        let baseName = "\(kind.filePrefix) Screenshot \(formatter.string(from: Date()))"
        var candidate = folderURL.appending(path: "\(baseName).png")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folderURL.appending(path: "\(baseName) \(suffix).png")
            suffix += 1
        }

        return candidate
    }
}

enum ScreenshotCaptureError: LocalizedError {
    case commandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let status):
            return "Screen capture failed with exit code \(status)."
        }
    }
}

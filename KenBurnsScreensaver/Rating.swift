import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Errors

enum XMPRatingError: Error, LocalizedError {
    case fileNotFound(URL)
    case unreadableSource(URL)
    case unreadableProperties(URL)
    case invalidRating(Int)
    case unsupportedFormat(URL)
    case writeFailed(URL)
    case destinationCreationFailed(URL)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):        return "File not found: \(url.lastPathComponent)"
        case .unreadableSource(let url):    return "Cannot create image source: \(url.lastPathComponent)"
        case .unreadableProperties(let url):return "Cannot read image properties: \(url.lastPathComponent)"
        case .invalidRating(let r):         return "Rating \(r) is out of range — must be 0–5 (0 = unrated, -1 = rejected)"
        case .unsupportedFormat(let url):   return "Unsupported image format: \(url.lastPathComponent)"
        case .writeFailed(let url):         return "Failed to write image data: \(url.lastPathComponent)"
        case .destinationCreationFailed(let url): return "Cannot create image destination: \(url.lastPathComponent)"
        }
    }
}

struct ToolLocator {
    static let exifToolURL: URL? = {
        do {
            // Check both Homebrew locations (Intel and Apple Silicon).
            let candidates = [
                "/usr/local/bin/exiftool",
                "/opt/homebrew/bin/exiftool",
            ]
            for path in candidates {
                if FileManager.default.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
            // Fall back to `which exiftool` for non-Homebrew installs.
            let which = Process()
            which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            which.arguments = ["exiftool"]
            let pipe = Pipe()
            which.standardOutput = pipe
            try which.run()
            which.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if output.isEmpty {
                print("No 'exiftool' found!")
                return nil
            }
            return URL(fileURLWithPath: output)
        } catch {
            print("Exception: No 'exiftool' found!")
            return nil
        }
    }()
}


// MARK: - XMPRating

/// Reads and writes the XMP `xmp:Rating` field embedded in image files.
///
/// The rating scale follows the XMP specification:
///   -1 = Rejected, 0 = Unrated, 1–5 = Star rating
///
/// Supported formats: JPEG, TIFF, PNG, HEIC, DNG, and most RAW formats
/// that ImageIO can open and rewrite.
///
/// **Important:** This rewrites the entire file. Always keep a backup, or
/// pass `writingTo:` to write to a separate output file.
enum XMPRating {

    // MARK: Reading

    /// Returns the XMP rating for the image at `url`, or `nil` if unset.
    static func read(from url: URL) throws -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XMPRatingError.fileNotFound(url)
        }

        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            throw XMPRatingError.unreadableSource(url)
        }

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw XMPRatingError.unreadableProperties(url)
        }

        // XMP metadata lives under the "{XMP}" key in ImageIO properties.
        if let xmp = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
           let rating = xmp["StarRating" as CFString] as? Int {
            return rating
        }

        return nil
    }

    // MARK: Writing

    /// Writes an XMP rating into the image file at `url`, overwriting in place.
    ///
    /// - Parameters:
    ///   - rating: -1 (rejected), 0 (unrated), or 1–5 stars.
    ///   - url: Source image file.
    static func write(_ rating: Int, to url: URL) throws {
        try write(rating, from: url, writingTo: url)
    }

    static func write(_ rating: Int, from source: URL, writingTo destination: URL) throws {
        guard rating >= 0 && rating <= 5 else {
            throw XMPRatingError.invalidRating(rating)
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XMPRatingError.fileNotFound(source)
        }

        // If writing to a different destination, copy first so exiftool edits in place.
        if destination.path != source.path {
            try FileManager.default.copyItem(at: source, to: destination)
        }

        let process = Process()
        process.executableURL = ToolLocator.exifToolURL!
        process.arguments = [
            "-overwrite_original",
            "-xmp:Rating=\(rating)",
            destination.path
        ]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw XMPRatingError.writeFailed(destination)
        }
    }

    // TONY: Update this to cache.
    private static func exiftoolURL() throws -> URL {
        // Check both Homebrew locations (Intel and Apple Silicon).
        let candidates = [
            "/usr/local/bin/exiftool",
            "/opt/homebrew/bin/exiftool",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Fall back to `which exiftool` for non-Homebrew installs.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["exiftool"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try which.run()
        which.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else {
            throw XMPRatingError.writeFailed(URL(fileURLWithPath: "exiftool not found"))
        }
        return URL(fileURLWithPath: output)
    }
    
    /// Note: Stomps EXIF metadata for ComfyUI, etc.
    static func writeUnsafe(_ rating: Int, from source: URL, writingTo destination: URL) throws {
        guard rating >= -1 && rating <= 5 else {
            throw XMPRatingError.invalidRating(rating)
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XMPRatingError.fileNotFound(source)
        }

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, sourceOptions as CFDictionary) else {
            throw XMPRatingError.unreadableSource(source)
        }

        guard let uti = CGImageSourceGetType(imageSource) else {
            throw XMPRatingError.unsupportedFormat(source)
        }

        // Read existing properties and patch only the IPTC rating key.
        var props = (CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]) ?? [:]
        var iptc  = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        iptc["StarRating" as CFString] = String(rating)
        props[kCGImagePropertyIPTCDictionary] = iptc

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(destination.pathExtension)

        guard let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, uti, 1, nil) else {
            throw XMPRatingError.destinationCreationFailed(destination)
        }

        // Pass the patched properties dict — this merges on top of the source metadata.
        CGImageDestinationAddImageFromSource(dest, imageSource, 0, props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw XMPRatingError.writeFailed(destination)
        }

        _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
    }
    
    // MARK: Convenience

    /// Prints a human-readable summary of the rating in a file.
    static func describe(_ rating: Int?) -> String {
        guard let rating else { return "No rating set" }
        switch rating {
        case -1:       return "Rejected (✗)"
        case 0:        return "Unrated"
        case 1...5:    return String(repeating: "★", count: rating) +
                              String(repeating: "☆", count: 5 - rating) +
                              " (\(rating)/5)"
        default:       return "Unknown rating: \(rating)"
        }
    }
}

// MARK: - Batch helpers

extension XMPRating {

    /// Returns all image URLs in a directory together with their current ratings.
    static func readAll(in directory: URL, recursive: Bool = false) throws -> [(url: URL, rating: Int?)] {
        let fm = FileManager.default
        let supportedExtensions: Set<String> = ["jpg", "jpeg", "tiff", "tif", "png", "heic", "heif", "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2"]

        let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        )

        var results: [(url: URL, rating: Int?)] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            let rating = try? XMPRating.read(from: fileURL)
            results.append((url: fileURL, rating: rating))
        }

        return results.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// Applies the same rating to all matching images in a directory.
    static func writeAll(_ rating: Int, in directory: URL, extensions: [String] = ["jpg", "jpeg"]) throws {
        let fm = FileManager.default
        let extSet = Set(extensions.map { $0.lowercased() })
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        for url in contents where extSet.contains(url.pathExtension.lowercased()) {
            try write(rating, to: url)
        }
    }
}

// MARK: - Usage Examples

/*

 // ── Read ──────────────────────────────────────────────────────────────────
 let imageURL = URL(fileURLWithPath: "/path/to/photo.jpg")

 do {
     let rating = try XMPRating.read(from: imageURL)
     print(XMPRating.describe(rating))
     // e.g. "★★★☆☆ (3/5)"
 } catch {
     print("Read error:", error.localizedDescription)
 }


 // ── Write ─────────────────────────────────────────────────────────────────
 do {
     try XMPRating.write(4, to: imageURL)
     print("Rating written.")
 } catch {
     print("Write error:", error.localizedDescription)
 }


 // ── Write to a separate output file ──────────────────────────────────────
 let outputURL = URL(fileURLWithPath: "/path/to/output.jpg")
 try XMPRating.write(5, from: imageURL, writingTo: outputURL)


 // ── Clear ─────────────────────────────────────────────────────────────────
 try XMPRating.clear(from: imageURL)


 // ── Mark as rejected ─────────────────────────────────────────────────────
 try XMPRating.write(-1, to: imageURL)


 // ── Batch read a folder ───────────────────────────────────────────────────
 let folder = URL(fileURLWithPath: "/path/to/photos")
 let results = try XMPRating.readAll(in: folder, recursive: true)
 for (url, rating) in results {
     print("\(url.lastPathComponent): \(XMPRating.describe(rating))")
 }


 // ── Batch write a folder ──────────────────────────────────────────────────
 try XMPRating.writeAll(3, in: folder, extensions: ["jpg", "jpeg", "heic"])

*/

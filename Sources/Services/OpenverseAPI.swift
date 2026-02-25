import AppKit
import Foundation

// MARK: - Response Types

/// Top-level search response from Openverse.
struct OpenverseSearchResponse: Codable {
    let resultCount: Int
    let pageCount: Int
    let results: [OpenverseImage]

    enum CodingKeys: String, CodingKey {
        case resultCount = "result_count"
        case pageCount = "page_count"
        case results
    }
}

/// A single image result from Openverse.
struct OpenverseImage: Codable, Identifiable {
    let id: String
    let title: String?
    let url: String
    let thumbnail: String?
    let creator: String?
    let creatorUrl: String?
    let license: String
    let licenseVersion: String?
    let licenseUrl: String?
    let attribution: String?
    let width: Int?
    let height: Int?
    let filesize: Int?
    let filetype: String?
    let tags: [OpenverseTag]?

    enum CodingKeys: String, CodingKey {
        case id, title, url, thumbnail, creator
        case creatorUrl = "creator_url"
        case license
        case licenseVersion = "license_version"
        case licenseUrl = "license_url"
        case attribution, width, height, filesize, filetype, tags
    }

    /// Convert to an ImageAttribution for storage and export.
    func toAttribution() -> ImageAttribution {
        ImageAttribution(
            title: title,
            creator: creator,
            creatorUrl: creatorUrl,
            license: license,
            licenseVersion: licenseVersion,
            licenseUrl: licenseUrl,
            attribution: attribution,
            sourceUrl: url
        )
    }
}

struct OpenverseTag: Codable {
    let name: String
}

// MARK: - Search Parameters

/// User-configurable search filters mapped to Openverse query parameters.
struct OpenverseSearchParams {
    var query: String = ""
    var pageSize: Int = 20
    var page: Int = 1
    var size: OpenverseSize? = nil
    var category: OpenverseCategory? = nil

    enum OpenverseSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
    }

    enum OpenverseCategory: String, CaseIterable, Identifiable {
        case photograph
        case illustration
        case digitizedArtwork = "digitized_artwork"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .photograph: return "Photograph"
            case .illustration: return "Illustration"
            case .digitizedArtwork: return "Digitised Artwork"
            }
        }
    }
}

// MARK: - Errors

enum OpenverseError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidURL(String)
    case imageDecodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Openverse."
        case .httpError(let code):
            if code == 429 {
                return "Openverse rate limit reached. Anonymous usage allows 100 requests per day and 5 per hour. Please wait before searching again."
            }
            return "Openverse returned HTTP \(code)."
        case .invalidURL(let url):
            return "Invalid image URL: \(url)"
        case .imageDecodeFailed:
            return "Failed to decode the downloaded image."
        }
    }
}

// MARK: - API Client

/// Openverse image search API client. No instances needed.
enum OpenverseAPI {
    private static let baseURL = "https://api.openverse.org/v1/images/"

    /// Search Openverse for images matching the given parameters.
    static func search(params: OpenverseSearchParams) async throws -> OpenverseSearchResponse {
        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: params.query),
            URLQueryItem(name: "page_size", value: String(params.pageSize)),
            URLQueryItem(name: "page", value: String(params.page)),
            URLQueryItem(name: "mature", value: "false"),
        ]
        if let size = params.size {
            queryItems.append(URLQueryItem(name: "size", value: size.rawValue))
        }
        if let category = params.category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("JigsawPuzzleGenerator/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenverseError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw OpenverseError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(OpenverseSearchResponse.self, from: data)
    }

    /// Download an image, saving to a temp file for best quality with PuzzleGenerator.
    /// Returns the NSImage and the temp file URL.
    static func downloadImage(from urlString: String) async throws -> (NSImage, URL) {
        guard let url = URL(string: urlString) else {
            throw OpenverseError.invalidURL(urlString)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = NSImage(data: data) else {
            throw OpenverseError.imageDecodeFailed
        }

        // Save to temp file so PuzzleGenerator can use CGImageSourceCreateWithURL
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openverse_\(UUID().uuidString).\(ext)")
        try data.write(to: tempURL)

        return (image, tempURL)
    }
}

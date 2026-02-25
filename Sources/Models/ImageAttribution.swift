import Foundation

/// Attribution and licence information for an image sourced from Openverse.
struct ImageAttribution: Codable, Equatable {
    let title: String?
    let creator: String?
    let creatorUrl: String?
    let license: String
    let licenseVersion: String?
    let licenseUrl: String?
    /// Pre-formatted attribution text from Openverse.
    let attribution: String?
    /// The original image URL.
    let sourceUrl: String
}

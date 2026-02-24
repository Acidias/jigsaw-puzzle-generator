import Foundation

/// Describes how one edge of a jigsaw piece connects to its neighbour.
/// - `flat`: Straight edge (border pieces only)
/// - `tab`: Protrudes outward (the knob)
/// - `blank`: Indents inward (the socket that receives a tab)
enum EdgeType: String, Codable, CaseIterable {
    case flat
    case tab
    case blank

    /// The complementary edge type. A tab's neighbour must be a blank, and vice versa.
    var complement: EdgeType {
        switch self {
        case .flat: return .flat
        case .tab: return .blank
        case .blank: return .tab
        }
    }
}

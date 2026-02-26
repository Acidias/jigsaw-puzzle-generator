import Foundation

/// Where training should run - locally or on a remote cloud GPU via SSH.
enum TrainingTarget: String, Codable, CaseIterable, Equatable {
    case local
    case cloud

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .cloud: return "Cloud (SSH)"
        }
    }

    var icon: String {
        switch self {
        case .local: return "laptopcomputer"
        case .cloud: return "cloud"
        }
    }
}

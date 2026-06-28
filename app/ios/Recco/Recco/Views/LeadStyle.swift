import SwiftUI

/// Shared color language for lead priority + follow-up. Restrained, graphite-
/// friendly, and red-free (red is reserved for errors).
extension LeadPriority {
    var color: Color {
        switch self {
        case .hot: return Color(red: 0.30, green: 0.86, blue: 0.70)   // mint / cyan
        case .warm: return Color(red: 0.97, green: 0.72, blue: 0.36)  // amber
        case .cold: return Color(red: 0.62, green: 0.66, blue: 0.72)  // cool grey
        case .needsInfo: return Color(red: 0.82, green: 0.76, blue: 0.52) // muted yellow-grey
        }
    }
}

enum LeadStyle {
    /// Green used for the "Sent" badge / status.
    static let sent = Color(red: 0.40, green: 0.82, blue: 0.56)
}

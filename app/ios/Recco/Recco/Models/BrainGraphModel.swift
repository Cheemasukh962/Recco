import CoreGraphics
import Foundation

/// Intermediate view model for the Brain graph. Pure data — no SwiftUI, no
/// layout math — so the rendering layer (`BrainGraphView`) and the physics
/// layer (`BrainGraphLayoutEngine`) can stay small and testable. Built from the
/// app's `[ScanMemoryDTO]` by `BrainGraphBuilder`.

// MARK: - Node / edge kinds

/// What a node represents. Drives its visual treatment.
enum BrainNodeKind: Equatable, Hashable {
    /// The central "Event" hub — everything hangs off it.
    case eventHub
    /// One resolved person / scan memory.
    case memory
    /// A cluster node (company / school / source / confidence bucket).
    case group(BrainGroupKind)
}

/// The dimension a group node clusters on.
enum BrainGroupKind: String, Equatable, Hashable {
    case company, school, source, confidence

    var systemImage: String {
        switch self {
        case .company: return "building.2"
        case .school: return "graduationcap"
        case .source: return "dot.radiowaves.left.and.right"
        case .confidence: return "seal"
        }
    }
}

// MARK: - Grouping dimension (user-selectable lens)

/// The active clustering lens. `none` is a clean hub-and-spoke (great for a
/// handful of memories); the others surface emergent structure as the memory
/// count grows. Company/school clusters only form when ≥2 memories share a
/// value, so distinct singletons stay attached to the hub instead of spraying
/// noise nodes.
enum BrainGraphGrouping: String, CaseIterable, Identifiable {
    case none, company, source, confidence, school

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Hub"
        case .company: return "Company"
        case .source: return "Source"
        case .confidence: return "Confidence"
        case .school: return "School"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "circle.hexagongrid"
        case .company: return "building.2"
        case .source: return "dot.radiowaves.left.and.right"
        case .confidence: return "seal"
        case .school: return "graduationcap"
        }
    }
}

// MARK: - Graph primitives

/// A single node. `memoryId` is set only for `.memory` nodes and is the bridge
/// back to `appModel.memory(id:)` when the node is tapped.
struct BrainGraphNode: Identifiable, Equatable {
    let id: String
    let kind: BrainNodeKind
    let title: String
    let subtitle: String?
    /// For `.memory` nodes: the underlying scan memory id.
    let memoryId: String?
    /// For `.memory` / confidence-group nodes: the confidence bucket.
    let confidence: ScanConfidence?
    let hasLinkedIn: Bool
    /// Members represented (memories under a group, or scan count on a memory).
    let memberCount: Int
    /// Relative mass / size hint in 0…1 (verified people read a touch larger).
    let weight: Double

    var isMemory: Bool { if case .memory = kind { return true }; return false }
    var isHub: Bool { kind == .eventHub }
}

/// A connection. `strength` (0…1) drives both spring stiffness in the physics
/// layer and stroke opacity in the renderer — verified links read stronger.
struct BrainGraphEdge: Identifiable, Equatable {
    let source: String
    let target: String
    let strength: Double
    var id: String { "\(source)→\(target)" }
}

/// The built graph plus cheap adjacency lookups for selection/highlighting.
struct BrainGraphModel: Equatable {
    var nodes: [BrainGraphNode]
    var edges: [BrainGraphEdge]

    static let empty = BrainGraphModel(nodes: [], edges: [])

    /// Node ids directly connected to `id` (either edge direction).
    func neighbors(of id: String) -> Set<String> {
        var result = Set<String>()
        for e in edges {
            if e.source == id { result.insert(e.target) }
            else if e.target == id { result.insert(e.source) }
        }
        return result
    }

    /// Memory-node ids reachable under a group/hub node (its direct memory
    /// members). Used to decide whether a cluster should dim under a filter.
    func memoryMembers(of id: String) -> Set<String> {
        let memoryIds = Set(nodes.filter { $0.isMemory }.map(\.id))
        return neighbors(of: id).filter { memoryIds.contains($0) }
    }
}

// MARK: - Builder

enum BrainGraphBuilder {
    static let hubId = "event_hub"

    /// Spring/edge strength + size weight for a confidence bucket. Stronger for
    /// verified, weakest for unknown — matches the spec's edge-weight intent.
    static func weight(for confidence: ScanConfidence) -> Double {
        switch confidence {
        case .verified: return 1.0
        case .possible: return 0.72
        case .needsConfirmation: return 0.52
        case .unknown: return 0.4
        }
    }

    /// Build the graph for a set of memories under the given lens. Topology
    /// depends only on `(memories, grouping)` — never on the search query — so
    /// searching/filtering only dims nodes and never re-lays-out the graph.
    static func build(memories: [ScanMemoryDTO], grouping: BrainGraphGrouping) -> BrainGraphModel {
        guard !memories.isEmpty else { return .empty }

        var nodes: [BrainGraphNode] = []
        var edges: [BrainGraphEdge] = []

        // Central hub.
        nodes.append(BrainGraphNode(
            id: hubId, kind: .eventHub, title: "Event",
            subtitle: "\(memories.count) memor\(memories.count == 1 ? "y" : "ies")",
            memoryId: nil, confidence: nil, hasLinkedIn: false,
            memberCount: memories.count, weight: 1
        ))

        // Memory nodes.
        for m in memories {
            nodes.append(BrainGraphNode(
                id: m.id, kind: .memory, title: m.displayName,
                subtitle: m.roleCompanyLine, memoryId: m.id,
                confidence: m.confidence, hasLinkedIn: m.hasLinkedIn,
                memberCount: m.scanCount, weight: weight(for: m.confidence)
            ))
        }

        // Edges depend on the lens.
        switch grouping {
        case .none:
            for m in memories { edges.append(hubEdge(to: m)) }

        case .company:
            attachByField(memories, field: { $0.company }, kind: .company,
                          minCluster: 2, nodes: &nodes, edges: &edges)

        case .school:
            attachByField(memories, field: { $0.school }, kind: .school,
                          minCluster: 2, nodes: &nodes, edges: &edges)

        case .confidence:
            attachByConfidence(memories, nodes: &nodes, edges: &edges)

        case .source:
            attachBySource(memories, nodes: &nodes, edges: &edges)
        }

        return BrainGraphModel(nodes: nodes, edges: edges)
    }

    // MARK: - Edge helpers

    private static func hubEdge(to m: ScanMemoryDTO) -> BrainGraphEdge {
        BrainGraphEdge(source: hubId, target: m.id, strength: weight(for: m.confidence))
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Cluster on a single text field (company/school). A value becomes a group
    /// node only once `minCluster` memories share it; lone values attach to the
    /// hub directly so distinct singletons never spray noise nodes.
    private static func attachByField(
        _ memories: [ScanMemoryDTO],
        field: (ScanMemoryDTO) -> String?,
        kind: BrainGroupKind,
        minCluster: Int,
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        // Group memories by a normalized key, preserving the first display value.
        var buckets: [String: (display: String, members: [ScanMemoryDTO])] = [:]
        var order: [String] = []
        for m in memories {
            guard let value = clean(field(m)) else { continue }
            let key = value.lowercased()
            if buckets[key] == nil { buckets[key] = (value, []); order.append(key) }
            buckets[key]?.members.append(m)
        }

        var clustered = Set<String>()
        for key in order {
            guard let bucket = buckets[key], bucket.members.count >= minCluster else { continue }
            let groupId = "grp_\(kind.rawValue)_\(key)"
            let avg = bucket.members.map { weight(for: $0.confidence) }.reduce(0, +) / Double(bucket.members.count)
            nodes.append(groupNode(id: groupId, kind: kind, title: bucket.display, count: bucket.members.count))
            edges.append(BrainGraphEdge(source: hubId, target: groupId, strength: max(0.6, avg)))
            for m in bucket.members {
                edges.append(BrainGraphEdge(source: groupId, target: m.id, strength: weight(for: m.confidence)))
                clustered.insert(m.id)
            }
        }

        // Everything that didn't cluster hangs off the hub.
        for m in memories where !clustered.contains(m.id) {
            edges.append(hubEdge(to: m))
        }
    }

    /// One bucket node per confidence level present in the set.
    private static func attachByConfidence(
        _ memories: [ScanMemoryDTO],
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        let order: [ScanConfidence] = [.verified, .possible, .needsConfirmation, .unknown]
        for level in order {
            let members = memories.filter { $0.confidence == level }
            guard !members.isEmpty else { continue }
            let groupId = "grp_confidence_\(level.rawValue)"
            var node = groupNode(id: groupId, kind: .confidence, title: level.label, count: members.count)
            node = BrainGraphNode(
                id: node.id, kind: node.kind, title: node.title, subtitle: node.subtitle,
                memoryId: nil, confidence: level, hasLinkedIn: false,
                memberCount: node.memberCount, weight: node.weight
            )
            nodes.append(node)
            edges.append(BrainGraphEdge(source: hubId, target: groupId, strength: weight(for: level)))
            for m in members {
                edges.append(BrainGraphEdge(source: groupId, target: m.id, strength: weight(for: level)))
            }
        }
    }

    /// Source lens: a memory can carry several sources, so it links to each of
    /// its source clusters (badge/fiber/face/voice/roster). Multi-edges here are
    /// the point — they show how a person was pieced together.
    private static func attachBySource(
        _ memories: [ScanMemoryDTO],
        nodes: inout [BrainGraphNode],
        edges: inout [BrainGraphEdge]
    ) {
        var buckets: [String: Int] = [:]
        var order: [String] = []
        for m in memories {
            for s in m.sources where !s.isEmpty {
                if buckets[s] == nil { buckets[s] = 0; order.append(s) }
                buckets[s]? += 1
            }
        }
        for source in order {
            let groupId = "grp_source_\(source)"
            nodes.append(groupNode(id: groupId, kind: .source, title: source.capitalized, count: buckets[source] ?? 0))
            edges.append(BrainGraphEdge(source: hubId, target: groupId, strength: 0.7))
        }
        for m in memories {
            let sources = m.sources.filter { !$0.isEmpty }
            if sources.isEmpty {
                edges.append(hubEdge(to: m))
            } else {
                for s in sources {
                    edges.append(BrainGraphEdge(source: "grp_source_\(s)", target: m.id, strength: weight(for: m.confidence)))
                }
            }
        }
    }

    private static func groupNode(id: String, kind: BrainGroupKind, title: String, count: Int) -> BrainGraphNode {
        BrainGraphNode(
            id: id, kind: .group(kind), title: title,
            subtitle: "\(count)", memoryId: nil, confidence: nil,
            hasLinkedIn: false, memberCount: count, weight: 0.55
        )
    }
}

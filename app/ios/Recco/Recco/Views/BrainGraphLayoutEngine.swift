import CoreGraphics
import Foundation
import Observation

/// Deterministic force-directed layout for the Brain graph (a small,
/// self-contained Fruchterman-Reingold solver). It runs a short, cooling settle
/// when the topology changes — you watch it relax for ~0.8s — then freezes, so
/// the graph feels alive on entry but never bounces unreadably afterwards.
///
/// The hub is hard-pinned to the centre; dragged nodes pin under the finger and
/// neighbours follow. Sizing is area-aware so 3, 5, 20 or 50 nodes all read.
@MainActor
@Observable
final class BrainGraphLayoutEngine {

    /// Published node centres in graph-local coordinates. Assigned once per
    /// frame so a settle step is a single view update, not one per node.
    private(set) var positions: [String: CGPoint] = [:]

    // Working state — parallel arrays keyed by `ids` for a tight solver loop.
    @ObservationIgnored private var ids: [String] = []
    @ObservationIgnored private var index: [String: Int] = [:]
    @ObservationIgnored private var pts: [CGPoint] = []
    @ObservationIgnored private var rad: [CGFloat] = []
    @ObservationIgnored private var fixedPt: [CGPoint?] = []
    @ObservationIgnored private var edges: [(a: Int, b: Int, s: Double)] = []

    @ObservationIgnored private var size: CGSize = .zero
    @ObservationIgnored private var unit: CGFloat = 40
    @ObservationIgnored private var k: CGFloat = 90          // ideal edge length
    @ObservationIgnored private var temperature: CGFloat = 0
    @ObservationIgnored private var framesLeft = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var signature = ""
    /// User-dragged nodes stay pinned until `recenter()`; the hub is always pinned.
    @ObservationIgnored private var userPinned: Set<String> = []

    private let hubId = BrainGraphBuilder.hubId

    // MARK: - Public API

    func radius(_ id: String) -> CGFloat {
        guard let i = index[id] else { return 24 }
        return rad[i]
    }

    func position(_ id: String) -> CGPoint {
        positions[id] ?? CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Reconcile the engine with a (possibly new) graph and canvas size. Seeds
    /// only newly-appeared nodes, preserves the layout of nodes that persist,
    /// and re-runs the settle only when the topology or size actually changed.
    func update(nodes: [BrainGraphNode], edges newEdges: [BrainGraphEdge], size newSize: CGSize) {
        guard newSize.width > 1, newSize.height > 1 else { return }
        let newSignature = nodes.map(\.id).sorted().joined(separator: ",")
            + "|" + newEdges.map(\.id).sorted().joined(separator: ",")
        let sizeChanged = abs(newSize.width - size.width) > 0.5 || abs(newSize.height - size.height) > 0.5
        if newSignature == signature && !sizeChanged { return }

        let isReflow = newSignature == signature   // same graph, only the size moved
        signature = newSignature
        size = newSize

        let count = max(nodes.count, 1)
        let area = Double(newSize.width * newSize.height)
        unit = max(11, CGFloat((area * 0.16 / (Double(count) * .pi)).squareRoot()))
        k = unit * 2.3
        let center = CGPoint(x: newSize.width / 2, y: newSize.height / 2)

        // Preserve existing positions; seed the rest deterministically.
        let previous = positions
        ids = nodes.map(\.id)
        index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        pts = nodes.map { node in
            if let p = previous[node.id] { return p }
            return seed(for: node.id, center: center)
        }
        rad = nodes.map { radius(for: $0) }
        fixedPt = nodes.map { node -> CGPoint? in
            if node.id == hubId { return center }
            if userPinned.contains(node.id) { return previous[node.id] }
            return nil
        }
        edges = newEdges.compactMap { e -> (a: Int, b: Int, s: Double)? in
            guard let a = index[e.source], let b = index[e.target] else { return nil }
            return (a, b, e.strength)
        }
        clampAll()
        publish()

        // A pure reflow (rotation) re-settles gently; a new graph settles fully.
        kick(frames: isReflow ? 22 : 52, hot: isReflow ? 0.4 : 1.0)
    }

    /// Pin a node under the finger and keep neighbours flowing.
    func beginDrag(_ id: String) {
        userPinned.insert(id)
        kick(frames: 600, hot: 0.28)   // long, gentle — ended explicitly on release
    }

    func drag(_ id: String, to point: CGPoint) {
        guard let i = index[id] else { return }
        let p = clamp(point, r: rad[i])
        pts[i] = p
        fixedPt[i] = p
        positions[id] = p
    }

    func endDrag(_ id: String) {
        kick(frames: 36, hot: 0.3)     // let the rest relax around the new pin
    }

    /// Drop every user pin (keep the hub centred) and re-settle from current
    /// positions — the "recenter" affordance.
    func recenter() {
        userPinned.removeAll()
        for i in fixedPt.indices where ids[i] != hubId { fixedPt[i] = nil }
        kick(frames: 52, hot: 1.0)
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        framesLeft = 0
    }

    // MARK: - Settle loop

    private func kick(frames: Int, hot: CGFloat) {
        framesLeft = max(framesLeft, frames)
        temperature = max(temperature, unit * 1.6 * hot)
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while let self, await self.tick() {
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// One displayed frame (a couple of solver iterations). Returns false when
    /// the layout has cooled and the loop should stop.
    private func tick() -> Bool {
        guard framesLeft > 0, size.width > 1 else {
            ticker = nil
            return false
        }
        for _ in 0..<2 { iterate() }
        framesLeft -= 1
        temperature = max(unit * 0.05, temperature * 0.92)
        publish()
        if framesLeft <= 0 { ticker = nil; return false }
        return true
    }

    /// Fruchterman-Reingold step with mild gravity, capped by temperature.
    private func iterate() {
        let n = pts.count
        guard n > 1 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var disp = [CGVector](repeating: .zero, count: n)

        // Repulsion between every pair.
        var i = 0
        while i < n {
            var j = i + 1
            while j < n {
                var dx = pts[i].x - pts[j].x
                var dy = pts[i].y - pts[j].y
                var dist = (dx * dx + dy * dy).squareRoot()
                if dist < 0.01 {
                    // Deterministic nudge so coincident nodes separate the same way.
                    dx = CGFloat((i * 13 % 7) - 3) * 0.5
                    dy = CGFloat((j * 17 % 7) - 3) * 0.5
                    dist = max((dx * dx + dy * dy).squareRoot(), 0.01)
                }
                let force = k * k / dist
                let ux = dx / dist, uy = dy / dist
                disp[i].dx += ux * force; disp[i].dy += uy * force
                disp[j].dx -= ux * force; disp[j].dy -= uy * force
                j += 1
            }
            i += 1
        }

        // Attraction along edges (scaled by strength).
        for e in edges {
            let dx = pts[e.a].x - pts[e.b].x
            let dy = pts[e.a].y - pts[e.b].y
            let dist = max((dx * dx + dy * dy).squareRoot(), 0.01)
            let force = dist * dist / k * CGFloat(0.55 + 0.9 * e.s)
            let ux = dx / dist, uy = dy / dist
            disp[e.a].dx -= ux * force; disp[e.a].dy -= uy * force
            disp[e.b].dx += ux * force; disp[e.b].dy += uy * force
        }

        // Integrate (gravity keeps disconnected parts in frame; temp caps step).
        for idx in 0..<n {
            if let fp = fixedPt[idx] { pts[idx] = fp; continue }
            disp[idx].dx += (center.x - pts[idx].x) * 0.035
            disp[idx].dy += (center.y - pts[idx].y) * 0.035
            let mag = (disp[idx].dx * disp[idx].dx + disp[idx].dy * disp[idx].dy).squareRoot()
            guard mag > 0.0001 else { continue }
            let step = min(mag, temperature)
            pts[idx].x += disp[idx].dx / mag * step
            pts[idx].y += disp[idx].dy / mag * step
            pts[idx] = clamp(pts[idx], r: rad[idx])
        }
    }

    // MARK: - Helpers

    private func publish() {
        var dict = [String: CGPoint](minimumCapacity: ids.count)
        for (i, id) in ids.enumerated() { dict[id] = pts[i] }
        positions = dict
    }

    private func clampAll() {
        for i in pts.indices { pts[i] = clamp(pts[i], r: rad[i]) }
    }

    private func clamp(_ p: CGPoint, r: CGFloat) -> CGPoint {
        let inset = r + 6
        return CGPoint(
            x: min(max(p.x, inset), max(inset, size.width - inset)),
            y: min(max(p.y, inset), max(inset, size.height - inset))
        )
    }

    /// Deterministic seed on a ring around the hub (stable FNV hash, not Swift's
    /// per-launch-randomized `hashValue`).
    private func seed(for id: String, center: CGPoint) -> CGPoint {
        let h = Self.fnv1a(id)
        let angle = Double(h % 360) / 180.0 * .pi
        let r = Double(unit) * (1.6 + Double(h / 360 % 24) / 12.0)
        return CGPoint(x: center.x + CGFloat(cos(angle) * r), y: center.y + CGFloat(sin(angle) * r))
    }

    private func radius(for node: BrainGraphNode) -> CGFloat {
        switch node.kind {
        case .eventHub: return min(max(unit * 1.5, 38), 66)
        case .memory: return min(max(unit * CGFloat(0.82 + 0.34 * node.weight), 13), 44)
        case .group: return min(max(unit * 0.78, 12), 34)
        }
    }

    private static func fnv1a(_ s: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % 100_000)
    }
}

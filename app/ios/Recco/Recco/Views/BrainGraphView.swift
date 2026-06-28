import SwiftUI

/// The graph surface: force-laid nodes over Canvas-drawn edges, with pan, pinch
/// zoom, per-node drag, tap-to-open and search/selection dimming. Topology comes
/// from `BrainGraphBuilder`; motion from `BrainGraphLayoutEngine`. All chrome
/// (grouping, recenter, mode toggle) lives in `BrainView`, so nothing here can
/// overlap a control.
struct BrainGraphView: View {
    let memories: [ScanMemoryDTO]
    let grouping: BrainGraphGrouping
    let query: String
    /// The confidence filter from `BrainView` (returns true when a memory passes).
    let filterPasses: (ScanMemoryDTO) -> Bool
    /// Bumped by the recenter control in `BrainView`.
    let recenterToken: Int
    @Binding var selectedNodeId: String?
    let onOpenMemory: (String) -> Void

    @State private var engine = BrainGraphLayoutEngine()
    @State private var model = BrainGraphModel.empty

    // View transform.
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero

    // Per-node drag bookkeeping.
    @State private var dragNode: String?
    @State private var dragMoved = false

    private let space = "brainGraph"

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let positions = engine.positions
            let matches = matchingMemoryIds()
            let neighbors = selectedNodeId.map { model.neighbors(of: $0) } ?? []

            ZStack {
                backdrop

                // Background catcher: deselect on tap, recenter on double-tap, pan on drag.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { recenterView() }
                    .onTapGesture { select(nil) }

                edgeCanvas(positions: positions, matches: matches)

                ForEach(model.nodes) { node in
                    let id = node.id
                    BrainGraphNodeView(
                        node: node,
                        diameter: engine.radius(id) * 2,
                        selected: selectedNodeId == id,
                        dimmed: isDimmed(id, matches: matches, neighbors: neighbors)
                    )
                    .position(positions[id] ?? center(size))
                    .highPriorityGesture(nodeDrag(node))
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(zoom)
            .offset(pan)
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .clipped()
            .onAppear { rebuild(size: size) }
            .onChange(of: memories) { _, _ in rebuild(size: size) }
            .onChange(of: grouping) { _, _ in rebuild(size: size) }
            .onChange(of: size) { _, newSize in engine.update(nodes: model.nodes, edges: model.edges, size: newSize) }
            .onChange(of: recenterToken) { _, _ in recenterView() }
            .onDisappear { engine.stop() }
        }
    }

    // MARK: - Layers

    private var backdrop: some View {
        RadialGradient(
            colors: [Theme.accent.opacity(0.08), Color.clear],
            center: .center, startRadius: 8, endRadius: 420
        )
        .allowsHitTesting(false)
    }

    private func edgeCanvas(positions: [String: CGPoint], matches: Set<String>) -> some View {
        let sel = selectedNodeId
        let focusing = sel != nil
        let neighbors = sel.map { model.neighbors(of: $0) } ?? []
        return Canvas { ctx, _ in
            for edge in model.edges {
                guard let p1 = positions[edge.source], let p2 = positions[edge.target] else { continue }
                let hot = focusing && (edge.source == sel || edge.target == sel)
                let dim = isDimmed(edge.source, matches: matches, neighbors: neighbors)
                    || isDimmed(edge.target, matches: matches, neighbors: neighbors)
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                let opacity: Double = hot ? 0.85 : (dim ? 0.05 : 0.10 + 0.22 * edge.strength)
                let color: Color = hot ? Theme.accent : .white
                ctx.stroke(path, with: .color(color.opacity(opacity)), lineWidth: hot ? 2 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                pan = CGSize(width: committedPan.width + v.translation.width,
                             height: committedPan.height + v.translation.height)
            }
            .onEnded { _ in committedPan = pan }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoom = min(max(committedZoom * value, 0.55), 2.6) }
            .onEnded { _ in committedZoom = zoom }
    }

    /// One gesture per node handles both tap (select/open) and drag (pin). Reading
    /// the location in the graph's own coordinate space keeps drag correct under
    /// any pan/zoom without manual transform math.
    private func nodeDrag(_ node: BrainGraphNode) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if dragNode == nil {
                    dragNode = node.id
                    dragMoved = false
                    engine.beginDrag(node.id)
                }
                let moved = abs(value.translation.width) + abs(value.translation.height)
                if moved > 6 { dragMoved = true }
                if dragMoved { engine.drag(node.id, to: value.location) }
            }
            .onEnded { _ in
                let wasDrag = dragMoved
                if wasDrag {
                    engine.endDrag(node.id)
                } else {
                    tap(node)
                }
                dragNode = nil
                dragMoved = false
            }
    }

    private func tap(_ node: BrainGraphNode) {
        switch node.kind {
        case .memory:
            select(node.id)
            if let mid = node.memoryId { onOpenMemory(mid) }
        case .eventHub, .group:
            select(selectedNodeId == node.id ? nil : node.id)
        }
    }

    private func select(_ id: String?) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedNodeId = id }
    }

    private func recenterView() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            zoom = 1; committedZoom = 1; pan = .zero; committedPan = .zero
        }
        engine.recenter()
    }

    // MARK: - Model + dimming

    private func rebuild(size: CGSize) {
        model = BrainGraphBuilder.build(memories: memories, grouping: grouping)
        // Drop a selection that no longer exists.
        if let sel = selectedNodeId, !model.nodes.contains(where: { $0.id == sel }) {
            selectedNodeId = nil
        }
        engine.update(nodes: model.nodes, edges: model.edges, size: size)
    }

    private var hasActiveFilter: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || isFilterNarrowing
    }

    /// True when the confidence filter excludes at least one memory (i.e. it is
    /// not "All"). Derived without knowing the filter enum.
    private var isFilterNarrowing: Bool {
        memories.contains { !filterPasses($0) }
    }

    private func matchingMemoryIds() -> Set<String> {
        Set(memories.filter { $0.matches(query) && filterPasses($0) }.map(\.id))
    }

    /// Combined dimming: search/filter misses *and* out-of-focus nodes when a
    /// node is selected. The hub never dims.
    private func isDimmed(_ id: String, matches: Set<String>, neighbors: Set<String>) -> Bool {
        if id == BrainGraphBuilder.hubId { return false }
        let filteredOut = hasActiveFilter && !isActive(id, matches: matches)
        let outOfFocus: Bool = {
            guard let sel = selectedNodeId else { return false }
            return id != sel && !neighbors.contains(id)
        }()
        return filteredOut || outOfFocus
    }

    /// A memory is active when it matches; a group/hub is active when any of its
    /// member memories match.
    private func isActive(_ id: String, matches: Set<String>) -> Bool {
        guard let node = model.nodes.first(where: { $0.id == id }) else { return true }
        switch node.kind {
        case .eventHub: return true
        case .memory: return matches.contains(id)
        case .group: return !model.memoryMembers(of: id).isDisjoint(with: matches)
        }
    }

    private func center(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }
}

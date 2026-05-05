import SwiftUI

struct WorkflowEditorView: View {
    @Binding var graph: WorkflowGraph
    @ObservedObject var runner: WorkflowRunner

    var onRun:  (String) -> Void
    var onStop: () -> Void

    @State private var selection: Selection = .none
    @State private var dragState: DragState = .idle
    @State private var showingPrompt = false

    // MARK: - State types

    enum Selection: Equatable {
        case none, node(UUID), edge(UUID)
    }

    enum DragState {
        case idle
        case movingNode(UUID, startPos: CGPoint, startDrag: CGPoint)
        case creatingEdge(UUID, current: CGPoint)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
            if case .node(let id) = selection,
               let idx = graph.nodes.firstIndex(where: { $0.id == id }) {
                Divider()
                instructionPanel(nodeIndex: idx)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(graph.name)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                graph.addNode(agent: .claude, at: nextNodePosition())
            } label: {
                Label("claude", systemImage: "plus.circle")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .help("Add claude node")

            Button {
                graph.addNode(agent: .codex, at: nextNodePosition())
            } label: {
                Label("codex", systemImage: "plus.circle")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .help("Add codex node")

            Divider().frame(height: 16)

            Button(role: .destructive) { deleteSelection() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .disabled(selection == .none)
            .help("Delete selected (⌫)")

            Divider().frame(height: 16)

            if runner.isRunning {
                Button("Stop") { onStop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button("Run") { showingPrompt = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(graph.nodes.isEmpty)
                    .sheet(isPresented: $showingPrompt) {
                        WorkflowPromptView(graph: graph) { prompt in
                            onRun(prompt)
                        }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack {
            dotGrid

            // Edges drawn on a Canvas layer
            Canvas { ctx, _ in
                drawEdges(ctx: ctx)
                drawDraggingEdge(ctx: ctx)
            }
            .allowsHitTesting(false)

            // Nodes
            ForEach(graph.nodes) { node in
                nodeView(for: node)
                    .position(node.position)
                    .onTapGesture { selection = .node(node.id) }
            }
        }
        .coordinateSpace(name: "wf-canvas")
        .contentShape(Rectangle())
        .gesture(canvasGesture)
        .onTapGesture { selection = .none }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Dot grid background

    private var dotGrid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(.secondary.opacity(0.18))
                    )
                    y += step
                }
                x += step
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Node view

    private func nodeView(for node: WorkflowNode) -> some View {
        let isActive    = runner.activeNodeIds.contains(node.id)
        let isDone      = runner.completedNodeIds.contains(node.id)
        let isSelected  = selection == .node(node.id)
        let color: Color = node.agent == .claude ? .blue : .green
        let isDraggingFrom: Bool = {
            if case .creatingEdge(let id, _) = dragState { return id == node.id }
            return false
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? .white : color,
                                      lineWidth: isSelected ? 2.5 : 1.5)
                )

            if isActive {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(0.9), lineWidth: 2)
            }

            HStack(spacing: 6) {
                Image(systemName: node.agent.systemImage)
                    .foregroundStyle(color)
                Text(node.agent.label)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
            }

            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            } else if !node.instruction.isEmpty {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(color.opacity(0.7))
                    .font(.system(size: 9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .frame(width: WorkflowNode.size.width, height: WorkflowNode.size.height)
        // Input port (left)
        .overlay(alignment: .leading) {
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
                .offset(x: -5.5)
        }
        // Output port (right) — glow when dragging from
        .overlay(alignment: .trailing) {
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
                .offset(x: 5.5)
                .shadow(color: isDraggingFrom ? color : .clear, radius: 6)
        }
    }

    // MARK: - Canvas gesture (single gesture, manual hit-test)

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("wf-canvas"))
            .onChanged { val in
                switch dragState {
                case .idle:
                    // Determine drag intent from start location
                    if let node = graph.nodes.first(where: { $0.isNearOutputPort(val.startLocation) }) {
                        dragState = .creatingEdge(node.id, current: val.location)
                    } else if let node = graph.nodes.first(where: { $0.contains(val.startLocation) }) {
                        dragState = .movingNode(node.id,
                                               startPos: node.position,
                                               startDrag: val.startLocation)
                        selection = .node(node.id)
                    }

                case .movingNode(let id, let startPos, let startDrag):
                    guard let idx = graph.nodes.firstIndex(where: { $0.id == id }) else { break }
                    graph.nodes[idx].position = CGPoint(
                        x: startPos.x + val.location.x - startDrag.x,
                        y: startPos.y + val.location.y - startDrag.y
                    )

                case .creatingEdge(let fromId, _):
                    dragState = .creatingEdge(fromId, current: val.location)
                }
            }
            .onEnded { val in
                if case .creatingEdge(let fromId, _) = dragState,
                   let target = graph.nodes.first(where: { $0.contains(val.location) }),
                   target.id != fromId {
                    graph.addEdge(from: fromId, to: target.id)
                }
                dragState = .idle
            }
    }

    // MARK: - Edge drawing

    private func drawEdges(ctx: GraphicsContext) {
        for edge in graph.edges {
            guard let from = graph.nodes.first(where: { $0.id == edge.fromId }),
                  let to   = graph.nodes.first(where: { $0.id == edge.toId }) else { continue }
            let isSelected = selection == .edge(edge.id)
            drawArrow(ctx: ctx, from: from.outputPort, to: to.inputPort,
                      color: isSelected ? .white : Color(.secondaryLabelColor),
                      dashed: false)
        }
    }

    private func drawDraggingEdge(ctx: GraphicsContext) {
        guard case .creatingEdge(let fromId, let current) = dragState,
              let from = graph.nodes.first(where: { $0.id == fromId }) else { return }
        drawArrow(ctx: ctx, from: from.outputPort, to: current,
                  color: Color.accentColor, dashed: true)
    }

    private func drawArrow(ctx: GraphicsContext, from: CGPoint, to: CGPoint,
                           color: Color, dashed: Bool) {
        let dx = to.x - from.x
        let cp1 = CGPoint(x: from.x + dx * 0.5, y: from.y)
        let cp2 = CGPoint(x: to.x  - dx * 0.5, y: to.y)

        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: cp1, control2: cp2)

        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: 2, dash: dashed ? [6, 4] : []))

        // Arrowhead
        let angle = atan2(to.y - cp2.y, to.x - cp2.x)
        let len: CGFloat = 10, spread: CGFloat = 0.4
        var head = Path()
        head.move(to: CGPoint(x: to.x - len * cos(angle - spread),
                              y: to.y - len * sin(angle - spread)))
        head.addLine(to: to)
        head.addLine(to: CGPoint(x: to.x - len * cos(angle + spread),
                                 y: to.y - len * sin(angle + spread)))
        ctx.stroke(head, with: .color(color), lineWidth: 2)
    }

    // MARK: - Helpers

    private func deleteSelection() {
        switch selection {
        case .node(let id): graph.remove(nodeId: id)
        case .edge(let id): graph.remove(edgeId: id)
        case .none: break
        }
        selection = .none
    }

    // MARK: - Instruction panel

    private func instructionPanel(nodeIndex idx: Int) -> some View {
        let node = graph.nodes[idx]
        let color: Color = node.agent == .claude ? .blue : .green
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: node.agent.systemImage)
                    .foregroundStyle(color)
                    .font(.system(size: 11))
                Text("\(node.agent.label) · instruction")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("prepended to input")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            TextEditor(text: $graph.nodes[idx].instruction)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 72)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .overlay(alignment: .topLeading) {
                    if graph.nodes[idx].instruction.isEmpty {
                        Text("No instruction — agent receives prompt/output as-is")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func nextNodePosition() -> CGPoint {
        let offset = CGFloat(graph.nodes.count)
        return CGPoint(x: 160 + offset * 20, y: 180 + offset * 15)
    }
}

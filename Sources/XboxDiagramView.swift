import AppKit
import SwiftUI

extension PadInput {
    /// Minimalist short label for compact visual pills
    var minimalLabel: String {
        switch self {
        case .A: return "A"
        case .B: return "B"
        case .X: return "X"
        case .Y: return "Y"
        case .LB: return "LB"
        case .RB: return "RB"
        case .LT: return "LT"
        case .RT: return "RT"
        case .VIEW: return "View"
        case .MENU: return "Menu"
        case .LS: return "L3"
        case .RS: return "R3"
        case .DUP: return "D↑"
        case .DDOWN: return "D↓"
        case .DLEFT: return "D←"
        case .DRIGHT: return "D→"
        case .LUP: return "LS↑"
        case .LDOWN: return "LS↓"
        case .LLEFT: return "LS←"
        case .LRIGHT: return "LS→"
        case .RUP: return "RS↑"
        case .RDOWN: return "RS↓"
        case .RLEFT: return "RS←"
        case .RRIGHT: return "RS→"
        }
    }
}

/// Fixed-aspect-ratio local coordinates (in a 340×250 space centered at 0,0) for every physical input on the Xbox controller.
enum XboxLayout {
    static func localAnchor(for input: PadInput) -> CGPoint {
        switch input {
        case .LT:     return CGPoint(x: -74, y: -96)
        case .RT:     return CGPoint(x:  74, y: -96)
        case .LB:     return CGPoint(x: -82, y: -72)
        case .RB:     return CGPoint(x:  82, y: -72)
        case .VIEW:   return CGPoint(x: -26, y: -22)
        case .MENU:   return CGPoint(x:  26, y: -22)
        case .LS, .LUP, .LDOWN, .LLEFT, .LRIGHT:
                      return CGPoint(x: -72, y: -14)
        case .DUP:    return CGPoint(x: -38, y:  22)
        case .DDOWN:  return CGPoint(x: -38, y:  52)
        case .DLEFT:  return CGPoint(x: -53, y:  37)
        case .DRIGHT: return CGPoint(x: -23, y:  37)
        case .X:      return CGPoint(x:  72, y: -38)
        case .A:      return CGPoint(x:  96, y: -14)
        case .B:      return CGPoint(x:  72, y:  10)
        case .Y:      return CGPoint(x:  48, y: -14)
        case .RS, .RUP, .RDOWN, .RLEFT, .RRIGHT:
                      return CGPoint(x:  42, y:  37)
        }
    }

    static func scale(for canvasSize: CGSize) -> CGFloat {
        let sX = (canvasSize.width - 16) / 300.0
        let sY = (canvasSize.height - 16) / 235.0
        return max(0.58, min(1.12, min(sX, sY)))
    }

    static func point(_ lx: CGFloat, _ ly: CGFloat, in canvasSize: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(x: canvasSize.width * 0.5 + lx * scale, y: canvasSize.height * 0.50 + ly * scale)
    }

    static func anchor(for input: PadInput, in canvasSize: CGSize, scale: CGFloat) -> CGPoint {
        let local = localAnchor(for: input)
        return point(local.x, local.y, in: canvasSize, scale: scale)
    }
}

struct XboxControllerEditorSection: View {
    @EnvironmentObject var store: Store
    @State private var showAdvancedSheet = false
    @State private var showSaveProfileSheet = false
    @State private var showManageProfilesSheet = false

    var currentDevice: DeviceAssignment {
        store.padMap.devices[store.player]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1)),
                            Color(nsColor: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.15, alpha: 1)),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)

            VStack(spacing: 12) {
                // 1. Minimalist Top Device & Status Bar
                deviceAssignmentHeader
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                // 2. Compact Top Anatomical Dock: Shoulders/Triggers & System
                topShouldersAndSystemBar
                    .padding(.horizontal, 18)

                // 3. Spatial 3-Column Layout around the Controller:
                //    Left (Stick Izq. + Cruceta) | Center (Interactive Controller) | Right (Botones X Y A B + Stick Der.)
                HStack(alignment: .center, spacing: 12) {
                    // LEFT COLUMN
                    VStack(spacing: 10) {
                        MinimalStickCrossCard(
                            title: "Stick Izq.",
                            icon: "l.joystick.fill",
                            tint: .teal,
                            up: .LUP,
                            down: .LDOWN,
                            left: .LLEFT,
                            right: .LRIGHT,
                            clickControl: .LS,
                            onSwapWithDPad: { store.swapPadDpadAndLeftStick(player: store.player) }
                        )

                        MinimalDPadCrossCard(
                            onSwapWithStick: { store.swapPadDpadAndLeftStick(player: store.player) }
                        )
                    }
                    .frame(width: 214)

                    // CENTER COLUMN: Interactive Controller Visual
                    centerControllerStage
                        .frame(minWidth: 260, maxWidth: .infinity, minHeight: 330, maxHeight: 355)

                    // RIGHT COLUMN
                    VStack(spacing: 10) {
                        MinimalFaceDiamondCard()

                        MinimalStickCrossCard(
                            title: "Stick Der.",
                            icon: "r.joystick.fill",
                            tint: .indigo,
                            up: .RUP,
                            down: .RDOWN,
                            left: .RLEFT,
                            right: .RRIGHT,
                            clickControl: .RS,
                            onSwapWithDPad: nil
                        )
                    }
                    .frame(width: 214)
                }
                .padding(.horizontal, 18)

                // 4. Minimalist Bottom Bar
                bottomPresetsStrip
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showAdvancedSheet) {
            AdvancedGamepadSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSaveProfileSheet) {
            SaveProfileSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showManageProfilesSheet) {
            ProfilesManagerSheet()
                .environmentObject(store)
        }
    }

    // MARK: - 1. Controller Device Assignment Header

    private var deviceAssignmentHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(deviceIconColor)
                    .font(.system(size: 12))
                    .fixedSize()

                Text("J\(store.player + 1):")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Menu {
                    Button("Automático (Por orden de conexión)") {
                        store.setDeviceAssignment(.auto, forPlayer: store.player)
                    }
                    Button("Solo Teclado (Sin mando físico en J\(store.player + 1))") {
                        store.setDeviceAssignment(.none, forPlayer: store.player)
                    }
                    if !store.connectedPads.isEmpty {
                        Divider()
                        ForEach(0..<store.connectedPads.count, id: \.self) { idx in
                            Button("Mando #\(idx + 1): \(store.connectedPads[idx])") {
                                store.assignConnectedPad(index: idx, toPlayer: store.player)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        let connectedName = store.connectedControllerName(forPlayer: store.player)
                        Text(
                            connectedName != nil
                                ? (currentDevice == .auto ? "Auto (\(connectedName!))" : connectedName!)
                                : (currentDevice == .auto ? "Automático (Sin mando)" : "\(currentDevice.shortLabel) (Desconectado)")
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(connectedName != nil ? .green : .white.opacity(0.75))
                        .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if let cap = store.capturingPad {
                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text("Asignando «\(cap.control.shortBadge)»")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    Button {
                        store.clearPadControl(cap.control, player: cap.player)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Vaciar")
                                .font(.system(size: 10.5, weight: .bold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Color.red.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()

                    Button {
                        store.capturingPad = nil
                    } label: {
                        Text("Esc")
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            } else {
                if store.identifyingPadForPlayer == store.player {
                    Button {
                        store.cancelIdentifyingPad()
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text("Pulsa un botón… (Esc)")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.orange, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                } else {
                    Button {
                        store.startIdentifyingPad(forPlayer: store.player)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                            Text("Detectar")
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Presiona cualquier botón en el mando físico para asignarlo al Jugador \(store.player + 1)")
                }

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        store.showRemoteBanner.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 10.5, weight: .bold))
                        Text(store.showRemoteBanner ? "Ocultar QR" : "Móvil QR")
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(store.showRemoteBanner ? .black : .cyan)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(store.showRemoteBanner ? Color.cyan : Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.cyan.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Mostrar u ocultar el código QR y PIN de NX Remote")

                Spacer(minLength: 4)

                Text(store.connectedPads.isEmpty ? "Sin mandos" : "\(store.connectedPads.count) mando(s)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            PlayerLEDIndicator(player: store.player, isConnected: store.isPlayerConnected(store.player))
        }
        .frame(height: 26)
    }

    private var deviceIconColor: Color {
        if store.isPlayerConnected(store.player) {
            return .green
        }
        return .white.opacity(0.4)
    }

    // MARK: - 2. Minimalist Top Bar: Shoulders, Triggers & System

    private var topShouldersAndSystemBar: some View {
        HStack(spacing: 12) {
            // Left: ZL + L
            MinimalTopCluster(title: "Hombros Izq.", tint: .purple, controls: [.ZL, .L]) {
                HStack(spacing: 6) {
                    MinimalPadPill(control: .ZL, badge: "ZL", defaultInput: .LT)
                    MinimalPadPill(control: .L, badge: "L", defaultInput: .LB)
                }
            }
            .frame(width: 214)

            // Center: − Select, + Start, Agitar
            MinimalTopCluster(title: "Sistema", tint: .orange, controls: [.MINUS, .PLUS, .SHAKE]) {
                HStack(spacing: 6) {
                    MinimalPadPill(control: .MINUS, badge: "−", defaultInput: .VIEW)
                    MinimalPadPill(control: .PLUS, badge: "+", defaultInput: .MENU)
                    MinimalPadPill(control: .SHAKE, badge: "≋", defaultInput: .LS)
                }
            }
            .frame(maxWidth: .infinity)

            // Right: R + ZR
            MinimalTopCluster(title: "Hombros Der.", tint: .purple, controls: [.R, .ZR]) {
                HStack(spacing: 6) {
                    MinimalPadPill(control: .R, badge: "R", defaultInput: .RB)
                    MinimalPadPill(control: .ZR, badge: "ZR", defaultInput: .RT)
                }
            }
            .frame(width: 214)
        }
    }

    // MARK: - 3. Center Interactive Controller Stage

    private var highlightedInputs: Set<PadInput> {
        var set = store.pressedPadInputs
        if let cap = store.capturingPad, cap.player == store.player {
            let assigned = store.padMap.inputs[store.player][cap.control] ?? []
            set.formUnion(assigned)
        }
        if let hov = store.hoveredControl {
            let assigned = store.padMap.inputs[store.player][hov] ?? []
            set.formUnion(assigned)
        }
        return set
    }

    private var centerControllerStage: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let size = geo.size
                let scale = XboxLayout.scale(for: size)

                ZStack {
                    Canvas { ctx, canvasSize in
                        drawAmbientGlow(ctx: &ctx, size: canvasSize, scale: scale)
                        drawXboxController(ctx: &ctx, size: canvasSize, scale: scale)
                    }

                    // Clickable hotspots directly on the controller diagram
                    ForEach(clickableHotspots, id: \.self) { pi in
                        let pt = XboxLayout.anchor(for: pi, in: size, scale: scale)
                        let isPressed = store.pressedPadInputs.contains(pi)
                        let isHighlighted = highlightedInputs.contains(pi)
                        Button {
                            if store.capturingPad != nil {
                                store.handleXboxButtonPress(pi)
                            }
                        } label: {
                            Circle()
                                .fill(isHighlighted ? Color(nsColor: pi.xboxColor).opacity(0.24) : Color.clear)
                                .frame(width: 26 * scale, height: 26 * scale)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            isPressed
                                                ? Color.green
                                                : (isHighlighted ? Color.cyan : (store.capturingPad != nil ? Color.orange.opacity(0.55) : Color.clear)),
                                            lineWidth: isPressed || isHighlighted ? 2.2 : 1.4
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .position(pt)
                        .help(pi.xboxTitle)
                    }
                }
            }

            // Minimalist 1-line status pill under controller
            HStack(spacing: 6) {
                if let cap = store.capturingPad, cap.player == store.player {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Pulsa el botón para «\(cap.control.shortBadge)» o Supr para vaciar")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if !store.pressedPadInputs.isEmpty {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(store.pressedPadInputs.map(\.xboxLabel).sorted().joined(separator: " + "))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else if let hov = store.hoveredControl {
                    let bound = store.padMap.inputs[store.player][hov] ?? []
                    Circle().fill(Color.cyan).frame(width: 6, height: 6)
                    Text("\(hov.title) → " + (bound.isEmpty ? "Vacío" : bound.map(\.xboxLabel).joined(separator: " + ")))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                } else {
                    Text("Clic en un botón para reasignar • Clic en ✕ al pasar el cursor para vaciar")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 20)
        }
    }

    // MARK: - 4. Minimalist Bottom Presets Strip

    private var bottomPresetsStrip: some View {
        HStack(spacing: 8) {
            Menu {
                let gProfiles = store.customProfiles.filter { $0.isGamepad }
                if !gProfiles.isEmpty {
                    Section("Mis Perfiles de Mando") {
                        ForEach(gProfiles) { prof in
                            Button(prof.name) {
                                store.applyProfile(prof, to: store.player)
                            }
                        }
                    }
                    Divider()
                }
                Section("Guardar y Gestionar") {
                    Button("Guardar ajustes de J\(store.player + 1) como nuevo perfil…", systemImage: "plus.circle") {
                        showSaveProfileSheet = true
                    }
                    Button("Gestionar y renombrar perfiles…", systemImage: "pencil.and.list.clipboard") {
                        showManageProfilesSheet = true
                    }
                }
                Divider()
                Section("Plantillas de fábrica") {
                    Button("Estándar Switch (A→A, B→B, X→X, Y→Y)") {
                        store.applyPadPreset(PadMap.defaultPlayerDict, player: store.player)
                    }
                    Button("Invertido Xbox (B→A, A→B, Y→X, X→Y)") {
                        store.applyPadPreset(PadMap.xboxLabelsPlayerDict, player: store.player)
                    }
                    Button("Smash Bros Pro") {
                        store.applyPadPreset(PadMap.smashProPlayerDict, player: store.player)
                    }
                }
                Divider()
                Button("Invertir Cruceta ↔ Stick Izquierdo") {
                    store.swapPadDpadAndLeftStick(player: store.player)
                }
                Button("Restaurar controles al estándar") {
                    store.resetPlayerPadToDefault(store.player)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.cyan)
                    Text(store.currentProfileName(for: store.player, mode: .gamepad))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                store.swapPadDpadAndLeftStick(player: store.player)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 9.5))
                    Text("Cruceta ↔ Stick")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .fixedSize()

            Spacer(minLength: 8)

            Button {
                showAdvancedSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 10.5))
                    Text("Vista en lista")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private var clickableHotspots: [PadInput] {
        [.LT, .RT, .LB, .RB, .VIEW, .MENU, .LS, .RS, .DUP, .DDOWN, .DLEFT, .DRIGHT, .Y, .B, .A, .X]
    }

    // MARK: - Vector Controller Drawing

    private func drawAmbientGlow(ctx: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.50)
        let r = 155 * scale
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [Color.cyan.opacity(0.09), Color.indigo.opacity(0.03), .clear]),
                center: center,
                startRadius: 6,
                endRadius: r
            )
        )
    }

    private func drawXboxController(ctx: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        func pt(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            XboxLayout.point(lx, ly, in: size, scale: scale)
        }
        let hiSet = highlightedInputs

        // 1. Top Triggers (LT / RT)
        let ltHi = hiSet.contains(.LT)
        let rtHi = hiSet.contains(.RT)

        var lt = Path()
        lt.move(to: pt(-96, -74))
        lt.addQuadCurve(to: pt(-76, -106), control: pt(-96, -104))
        lt.addQuadCurve(to: pt(-52, -82), control: pt(-56, -106))
        lt.closeSubpath()
        ctx.fill(lt, with: .color(ltHi ? Color.purple.opacity(0.85) : Color(white: 0.20)))
        ctx.stroke(lt, with: .color(.white.opacity(ltHi ? 0.95 : 0.35)), lineWidth: 1.3)
        ctx.draw(Text("LT").font(.system(size: 8.5 * scale, weight: .bold)).foregroundStyle(.white.opacity(0.8)), at: pt(-74, -93))

        var rt = Path()
        rt.move(to: pt(96, -74))
        rt.addQuadCurve(to: pt(76, -106), control: pt(96, -104))
        rt.addQuadCurve(to: pt(52, -82), control: pt(56, -106))
        rt.closeSubpath()
        ctx.fill(rt, with: .color(rtHi ? Color.purple.opacity(0.85) : Color(white: 0.20)))
        ctx.stroke(rt, with: .color(.white.opacity(rtHi ? 0.95 : 0.35)), lineWidth: 1.3)
        ctx.draw(Text("RT").font(.system(size: 8.5 * scale, weight: .bold)).foregroundStyle(.white.opacity(0.8)), at: pt(74, -93))

        // 2. Shoulder Bumpers (LB / RB)
        let lbHi = hiSet.contains(.LB)
        let rbHi = hiSet.contains(.RB)

        var lb = Path()
        lb.move(to: pt(-112, -56))
        lb.addQuadCurve(to: pt(-48, -80), control: pt(-84, -84))
        lb.addLine(to: pt(-44, -66))
        lb.addQuadCurve(to: pt(-106, -44), control: pt(-78, -66))
        lb.closeSubpath()
        ctx.fill(lb, with: .color(lbHi ? Color.purple.opacity(0.85) : Color(white: 0.25)))
        ctx.stroke(lb, with: .color(.white.opacity(lbHi ? 0.95 : 0.42)), lineWidth: 1.3)
        ctx.draw(Text("LB").font(.system(size: 8.5 * scale, weight: .bold)).foregroundStyle(.white.opacity(0.85)), at: pt(-78, -68))

        var rb = Path()
        rb.move(to: pt(112, -56))
        rb.addQuadCurve(to: pt(48, -80), control: pt(84, -84))
        rb.addLine(to: pt(44, -66))
        rb.addQuadCurve(to: pt(106, -44), control: pt(78, -66))
        rb.closeSubpath()
        ctx.fill(rb, with: .color(rbHi ? Color.purple.opacity(0.85) : Color(white: 0.25)))
        ctx.stroke(rb, with: .color(.white.opacity(rbHi ? 0.95 : 0.42)), lineWidth: 1.3)
        ctx.draw(Text("RB").font(.system(size: 8.5 * scale, weight: .bold)).foregroundStyle(.white.opacity(0.85)), at: pt(78, -68))

        // 3. Proportional Controller Body
        var body = Path()
        body.move(to: pt(-48, -72))
        body.addQuadCurve(to: pt(48, -72), control: pt(0, -78))
        body.addQuadCurve(to: pt(112, -50), control: pt(86, -74))
        body.addCurve(to: pt(142, 82), control1: pt(138, -12), control2: pt(152, 42))
        body.addCurve(to: pt(88, 92), control1: pt(134, 118), control2: pt(102, 118))
        body.addCurve(to: pt(48, 66), control1: pt(74, 72), control2: pt(66, 66))
        body.addQuadCurve(to: pt(-48, 66), control: pt(0, 62))
        body.addCurve(to: pt(-88, 92), control1: pt(-66, 66), control2: pt(-74, 72))
        body.addCurve(to: pt(-142, 82), control1: pt(-102, 118), control2: pt(-134, 118))
        body.addCurve(to: pt(-112, -50), control1: pt(-152, 42), control2: pt(-138, -12))
        body.addQuadCurve(to: pt(-48, -72), control: pt(-86, -74))
        body.closeSubpath()

        ctx.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [
                    Color(nsColor: NSColor(calibratedRed: 0.19, green: 0.21, blue: 0.27, alpha: 1)),
                    Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.18, alpha: 1)),
                    Color(nsColor: NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1)),
                ]),
                startPoint: pt(0, -78),
                endPoint: pt(0, 115)
            )
        )
        ctx.stroke(
            body,
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.55), Color.cyan.opacity(0.28), Color.white.opacity(0.18)]),
                startPoint: pt(-120, -75),
                endPoint: pt(120, 110)
            ),
            lineWidth: 1.8
        )

        // 4. Center Guide Button
        let nexus = pt(0, -48)
        let nr = 11 * scale
        let nRect = CGRect(x: nexus.x - nr, y: nexus.y - nr, width: nr * 2, height: nr * 2)
        ctx.fill(Path(ellipseIn: nRect), with: .color(Color(white: 0.15)))
        ctx.stroke(Path(ellipseIn: nRect), with: .color(.white.opacity(0.8)), lineWidth: 1.4)

        // 5. View (⧉) & Menu (≡)
        drawSmallBtn(ctx: &ctx, center: pt(-26, -22), r: 8 * scale, hi: hiSet.contains(.VIEW), text: "⧉")
        drawSmallBtn(ctx: &ctx, center: pt(26, -22), r: 8 * scale, hi: hiSet.contains(.MENU), text: "≡")

        // 6. Left Stick & Right Stick
        let lsHi = [PadInput.LS, .LUP, .LDOWN, .LLEFT, .LRIGHT].contains { hiSet.contains($0) }
        let rsHi = [PadInput.RS, .RUP, .RDOWN, .RLEFT, .RRIGHT].contains { hiSet.contains($0) }
        drawStick(
            ctx: &ctx,
            center: pt(-72, -14),
            r: 23 * scale,
            deflection: store.leftStick,
            hi: lsHi,
            tint: .teal,
            label: "LS"
        )
        drawStick(
            ctx: &ctx,
            center: pt(42, 37),
            r: 23 * scale,
            deflection: store.rightStick,
            hi: rsHi,
            tint: .indigo,
            label: "RS"
        )

        // 7. Hybrid Faceted D-Pad
        drawDPad(
            ctx: &ctx,
            center: pt(-38, 37),
            r: 23 * scale,
            hiSet: hiSet
        )

        // 8. Face Buttons (Switch Layout: X Top, A Right, B Bottom, Y Left)
        let fr = 12 * scale
        drawFaceBtn(ctx: &ctx, center: pt(72, -38), r: fr, input: .X, hi: hiSet.contains(.X))
        drawFaceBtn(ctx: &ctx, center: pt(96, -14), r: fr, input: .A, hi: hiSet.contains(.A))
        drawFaceBtn(ctx: &ctx, center: pt(72,  10), r: fr, input: .B, hi: hiSet.contains(.B))
        drawFaceBtn(ctx: &ctx, center: pt(48, -14), r: fr, input: .Y, hi: hiSet.contains(.Y))
    }

    private func drawSmallBtn(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, hi: Bool, text: String) {
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(hi ? Color.orange : Color(white: 0.22)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(hi ? 1 : 0.50)), lineWidth: 1.2)
        ctx.draw(Text(text).font(.system(size: r * 1.0, weight: .bold)).foregroundStyle(.white), at: center)
    }

    private func drawStick(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, deflection: CGPoint, hi: Bool, tint: Color, label: String) {
        let outer = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: outer), with: .color(Color(white: 0.08)))
        ctx.stroke(Path(ellipseIn: outer), with: .color(hi ? tint : .white.opacity(0.28)), lineWidth: hi ? 2.2 : 1.2)

        let capCenter = CGPoint(x: center.x + deflection.x * r * 0.34, y: center.y - deflection.y * r * 0.34)
        let capR = r * 0.74
        let cap = CGRect(x: capCenter.x - capR, y: capCenter.y - capR, width: capR * 2, height: capR * 2)
        ctx.fill(Path(ellipseIn: cap), with: .color(hi ? tint.opacity(0.55) : Color(white: 0.22)))
        ctx.stroke(Path(ellipseIn: cap), with: .color(.white.opacity(hi ? 0.95 : 0.40)), lineWidth: 1.3)
        ctx.draw(Text(label).font(.system(size: max(8, r * 0.36), weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9)), at: capCenter)
    }

    private func drawDPad(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, hiSet: Set<PadInput>) {
        let anyHi = [PadInput.DUP, .DDOWN, .DLEFT, .DRIGHT].contains { hiSet.contains($0) }
        let dish = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: dish), with: .color(Color(white: 0.09)))
        ctx.stroke(Path(ellipseIn: dish), with: .color(anyHi ? .cyan : .white.opacity(0.26)), lineWidth: anyHi ? 2.0 : 1.2)

        let armW = r * 0.54
        let armL = r * 0.86
        let vRect = CGRect(x: center.x - armW / 2, y: center.y - armL, width: armW, height: armL * 2)
        let hRect = CGRect(x: center.x - armL, y: center.y - armW / 2, width: armL * 2, height: armW)
        ctx.fill(Path(roundedRect: vRect, cornerRadius: 3), with: .color(Color(white: 0.22)))
        ctx.fill(Path(roundedRect: hRect, cornerRadius: 3), with: .color(Color(white: 0.22)))
        ctx.stroke(Path(roundedRect: vRect, cornerRadius: 3), with: .color(.white.opacity(0.35)), lineWidth: 1)
        ctx.stroke(Path(roundedRect: hRect, cornerRadius: 3), with: .color(.white.opacity(0.35)), lineWidth: 1)

        if hiSet.contains(.DUP) {
            let upRect = CGRect(x: center.x - armW / 2, y: center.y - armL, width: armW, height: armL * 0.75)
            ctx.fill(Path(roundedRect: upRect, cornerRadius: 3), with: .color(Color.cyan.opacity(0.85)))
        }
        if hiSet.contains(.DDOWN) {
            let downRect = CGRect(x: center.x - armW / 2, y: center.y + armL * 0.25, width: armW, height: armL * 0.75)
            ctx.fill(Path(roundedRect: downRect, cornerRadius: 3), with: .color(Color.cyan.opacity(0.85)))
        }
        if hiSet.contains(.DLEFT) {
            let leftRect = CGRect(x: center.x - armL, y: center.y - armW / 2, width: armL * 0.75, height: armW)
            ctx.fill(Path(roundedRect: leftRect, cornerRadius: 3), with: .color(Color.cyan.opacity(0.85)))
        }
        if hiSet.contains(.DRIGHT) {
            let rightRect = CGRect(x: center.x + armL * 0.25, y: center.y - armW / 2, width: armL * 0.75, height: armW)
            ctx.fill(Path(roundedRect: rightRect, cornerRadius: 3), with: .color(Color.cyan.opacity(0.85)))
        }
    }

    private func drawFaceBtn(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, input: PadInput, hi: Bool) {
        let color = Color(nsColor: input.xboxColor)
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        if hi {
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(color.opacity(0.45)))
        }
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(hi ? 1 : 0.70)), lineWidth: hi ? 2.4 : 1.3)
        let textColor: Color = (input == .B) ? .black : .white
        ctx.draw(Text(input.xboxLabel).font(.system(size: r * 0.95, weight: .heavy, design: .rounded)).foregroundStyle(textColor), at: center)
    }
}

// MARK: - Minimalist Anatomical Group Cards

struct MinimalTopCluster<Content: View>: View {
    @EnvironmentObject var store: Store
    let title: String
    let tint: Color
    let controls: [Control]
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Menu {
                    Button("Restaurar por defecto", systemImage: "arrow.counterclockwise") {
                        store.resetPadGroup(controls, player: store.player)
                    }
                    Button("Vaciar grupo", systemImage: "trash", role: .destructive) {
                        store.clearPadGroup(controls, player: store.player)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 16, height: 14)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Minimalist Cruceta (D-Pad) Cross Card (▲, ◀, ▶, ▼)
struct MinimalDPadCrossCard: View {
    @EnvironmentObject var store: Store
    let onSwapWithStick: () -> Void
    private let controls: [Control] = [.UP, .DOWN, .LEFT, .RIGHT]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "dpad.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.cyan)
                Text("Cruceta")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Menu {
                    Button("Intercambiar con Stick Izq.", systemImage: "arrow.left.arrow.right") {
                        onSwapWithStick()
                    }
                    Divider()
                    Button("Restaurar Cruceta", systemImage: "arrow.counterclockwise") {
                        store.resetPadGroup(controls, player: store.player)
                    }
                    Button("Vaciar Cruceta", systemImage: "trash", role: .destructive) {
                        store.clearPadGroup(controls, player: store.player)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 16, height: 14)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Cross Formation
            VStack(spacing: 5) {
                MinimalPadPill(control: .UP, badge: "▲", defaultInput: .DUP, width: 88)

                HStack(spacing: 6) {
                    MinimalPadPill(control: .LEFT, badge: "◀", defaultInput: .DLEFT, width: 88)
                    Circle()
                        .fill(Color.cyan.opacity(0.25))
                        .frame(width: 5, height: 5)
                    MinimalPadPill(control: .RIGHT, badge: "▶", defaultInput: .DRIGHT, width: 88)
                }

                MinimalPadPill(control: .DOWN, badge: "▼", defaultInput: .DDOWN, width: 88)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color.cyan.opacity(0.20), lineWidth: 1)
        )
    }
}

/// Minimalist Face Buttons (X, Y, A, B) Diamond Card
struct MinimalFaceDiamondCard: View {
    @EnvironmentObject var store: Store
    private let controls: [Control] = [.X, .Y, .A, .B]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.green)
                Text("Acción")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Menu {
                    Button("Estándar Switch (A→A, B→B, X→X, Y→Y)") {
                        store.bindPadInput(.A, player: store.player, control: .A)
                        store.bindPadInput(.B, player: store.player, control: .B)
                        store.bindPadInput(.X, player: store.player, control: .X)
                        store.bindPadInput(.Y, player: store.player, control: .Y)
                    }
                    Button("Invertido Xbox (B→A, A→B, Y→X, X→Y)") {
                        store.bindPadInput(.B, player: store.player, control: .A)
                        store.bindPadInput(.A, player: store.player, control: .B)
                        store.bindPadInput(.Y, player: store.player, control: .X)
                        store.bindPadInput(.X, player: store.player, control: .Y)
                    }
                    Divider()
                    Button("Vaciar X, Y, A, B", systemImage: "trash", role: .destructive) {
                        store.clearPadGroup(controls, player: store.player)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 16, height: 14)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Diamond Formation: X Top, Y Left + A Right, B Bottom
            VStack(spacing: 5) {
                MinimalPadPill(control: .X, badge: "X", defaultInput: .X, width: 88)

                HStack(spacing: 6) {
                    MinimalPadPill(control: .Y, badge: "Y", defaultInput: .Y, width: 88)
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 5, height: 5)
                    MinimalPadPill(control: .A, badge: "A", defaultInput: .A, width: 88)
                }

                MinimalPadPill(control: .B, badge: "B", defaultInput: .B, width: 88)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color.green.opacity(0.20), lineWidth: 1)
        )
    }
}

/// Minimalist Analog Stick Cross Card (↑, ←, →, ↓ + L3/R3 Click pill in header)
struct MinimalStickCrossCard: View {
    @EnvironmentObject var store: Store
    let title: String
    let icon: String
    let tint: Color
    let up: Control
    let down: Control
    let left: Control
    let right: Control
    let clickControl: Control
    let onSwapWithDPad: (() -> Void)?

    private var allControls: [Control] { [up, down, left, right, clickControl] }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Compact L3 / R3 Click Pill right in the header
                MinimalPadPill(
                    control: clickControl,
                    badge: clickControl.label,
                    defaultInput: clickControl == .LS ? .LS : .RS,
                    width: 72
                )

                Menu {
                    if let swap = onSwapWithDPad {
                        Button("Intercambiar con Cruceta", systemImage: "arrow.left.arrow.right") {
                            swap()
                        }
                        Divider()
                    }
                    Button("Restaurar \(title)", systemImage: "arrow.counterclockwise") {
                        store.resetPadGroup(allControls, player: store.player)
                    }
                    Button("Vaciar \(title)", systemImage: "trash", role: .destructive) {
                        store.clearPadGroup(allControls, player: store.player)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 14, height: 14)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Cross Formation: ↑ Top, ← Left + → Right, ↓ Bottom
            VStack(spacing: 5) {
                MinimalPadPill(
                    control: up,
                    badge: "↑",
                    defaultInput: up == .LUP ? .LUP : .RUP,
                    width: 88
                )

                HStack(spacing: 6) {
                    MinimalPadPill(
                        control: left,
                        badge: "←",
                        defaultInput: left == .LLEFT ? .LLEFT : .RLEFT,
                        width: 88
                    )
                    Circle()
                        .fill(tint.opacity(0.3))
                        .frame(width: 5, height: 5)
                    MinimalPadPill(
                        control: right,
                        badge: "→",
                        defaultInput: right == .LRIGHT ? .LRIGHT : .RRIGHT,
                        width: 88
                    )
                }

                MinimalPadPill(
                    control: down,
                    badge: "↓",
                    defaultInput: down == .LDOWN ? .LDOWN : .RDOWN,
                    width: 88
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(tint.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Ultra-Clean Minimalist Button Pill ([Switch Badge] [Mapped Button] + Hover ✕)

struct MinimalPadPill: View {
    @EnvironmentObject var store: Store
    let control: Control
    let badge: String
    let defaultInput: PadInput
    var width: CGFloat? = nil

    var isCapturing: Bool {
        store.capturingPad?.player == store.player && store.capturingPad?.control == control
    }
    var isHovered: Bool {
        store.hoveredControl == control
    }
    var assignedInputs: [PadInput] {
        store.padMap.inputs[store.player][control] ?? []
    }
    var primaryInput: PadInput {
        assignedInputs.first ?? defaultInput
    }
    var isPressed: Bool {
        assignedInputs.contains { store.pressedPadInputs.contains($0) }
    }
    var switchColor: Color {
        Color(nsColor: control.tint)
    }
    var xboxColor: Color {
        Color(nsColor: primaryInput.xboxColor)
    }

    var pillBackgroundColor: Color {
        if isCapturing { return Color.orange.opacity(0.22) }
        if isPressed { return xboxColor.opacity(0.28) }
        if isHovered { return Color.white.opacity(0.11) }
        return Color.white.opacity(0.05)
    }

    var pillStrokeColor: Color {
        if isCapturing { return Color.orange }
        if isPressed { return Color.green }
        if isHovered { return xboxColor.opacity(0.75) }
        return Color.white.opacity(0.08)
    }

    var body: some View {
        HStack(spacing: 0) {
            pillMainButton
            pillClearButton
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: 26)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(RoundedRectangle(cornerRadius: 7).fill(pillBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(pillStrokeColor, lineWidth: isCapturing || isPressed || isHovered ? 1.3 : 0.8)
        )
        .contextMenu { pillContextMenu }
        .onHover { h in
            store.hoveredControl = h ? control : (store.hoveredControl == control ? nil : store.hoveredControl)
        }
        .help("\(control.title) — Clic para cambiar • Clic en ✕ para dejar vacío")
    }

    private var pillMainButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.14)) {
                store.capturingPad = isCapturing ? nil : (store.player, control)
            }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(switchColor.opacity(isCapturing || isPressed ? 0.35 : 0.20))
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(switchColor)
                        .lineLimit(1)
                }
                .frame(width: 19, height: 19)
                .fixedSize()

                Spacer(minLength: 2)

                pillValueView

                Spacer(minLength: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pillValueView: some View {
        if isCapturing {
            Text("•••")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .fixedSize()
        } else if assignedInputs.isEmpty {
            Text("—")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.22))
                .lineLimit(1)
                .fixedSize()
        } else {
            HStack(spacing: 3) {
                Circle()
                    .fill(xboxColor)
                    .frame(width: 4.5, height: 4.5)
                Text(assignedInputs.map(\.minimalLabel).joined(separator: "+"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    private var pillClearButton: some View {
        if (!assignedInputs.isEmpty && isHovered) || isCapturing {
            Button {
                withAnimation(.snappy(duration: 0.14)) {
                    store.clearPadControl(control, player: store.player)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundStyle(isCapturing ? Color.red : Color.white.opacity(0.75))
                    .frame(width: 14, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Vaciar \(control.title)")
        }
    }

    @ViewBuilder
    private var pillContextMenu: some View {
        Button {
            store.capturingPad = (store.player, control)
        } label: {
            Label("Asignar \(control.title)…", systemImage: "gamecontroller")
        }
        if !assignedInputs.isEmpty {
            Button(role: .destructive) {
                store.clearPadControl(control, player: store.player)
            } label: {
                Label("Dejar vacío", systemImage: "trash")
            }
        }
        Divider()
        Button {
            store.bindPadInput(defaultInput, player: store.player, control: control, replace: true)
        } label: {
            Label("Restaurar (\(defaultInput.xboxLabel))", systemImage: "arrow.counterclockwise")
        }
    }
}

// MARK: - Switch 4-LED Player Indicator

struct PlayerLEDIndicator: View {
    let player: Int
    var isConnected: Bool = true

    private static let patterns: [[Bool]] = [
        [true,  false, false, false],
        [true,  true,  false, false],
        [true,  true,  true,  false],
        [true,  true,  true,  true],
        [true,  false, false, true],
        [true,  false, true,  false],
        [true,  false, true,  true],
        [false, true,  true,  false],
    ]

    var body: some View {
        let pat = Self.patterns[min(max(0, player), 7)]
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let lit = isConnected && pat[i]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(lit ? Color.green : Color.white.opacity(0.15))
                        .frame(width: 5.5, height: 5.5)
                        .shadow(color: lit ? Color.green.opacity(0.8) : .clear, radius: 2.5)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.35), in: Capsule())
        }
        .fixedSize()
    }
}

// MARK: - Advanced Granular Sheet (Fixed 2-Column Non-Colliding Grid)

struct AdvancedGamepadSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    private let columns: [GridItem] = [
        GridItem(.flexible(minimum: 390, maximum: 540), spacing: 18, alignment: .top),
        GridItem(.flexible(minimum: 390, maximum: 540), spacing: 18, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Todos los ejes y botones (Jugador \(store.player + 1))")
                        .font(.title3.bold())
                    Text("Haz clic en + para añadir un botón adicional, o en la papelera para vaciar ese control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restaurar estándar") {
                    store.resetPlayerPadToDefault(store.player)
                }
                .buttonStyle(.bordered)

                Button("Listo") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(ControlGroup.all) { group in
                        GamepadGroupCard(group: group)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .padding(22)
        .frame(minWidth: 880, idealWidth: 920, minHeight: 580, idealHeight: 640)
    }
}

struct GamepadGroupCard: View {
    @EnvironmentObject var store: Store
    let group: ControlGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(group.title, systemImage: group.symbol)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Vaciar grupo") {
                    store.clearPadGroup(group.controls, player: store.player)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Divider()
            VStack(spacing: 6) {
                ForEach(group.controls) { GamepadControlRow(control: $0) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
    }
}

struct GamepadControlRow: View {
    @EnvironmentObject var store: Store
    let control: Control

    var boundInputs: [PadInput] { store.padMap.inputs[store.player][control] ?? [] }
    var isCapturing: Bool { store.capturingPad?.player == store.player && store.capturingPad?.control == control }
    var isActive: Bool { boundInputs.contains { store.pressedPadInputs.contains($0) } }

    var body: some View {
        HStack(spacing: 8) {
            Glyph(control: control, active: isActive)
                .fixedSize()

            Text(control.title)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if isCapturing {
                        Text("Pulsa en tu mando…")
                            .font(.caption.italic().bold())
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if boundInputs.isEmpty {
                        Text("Sin asignar")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    ForEach(boundInputs) { pi in
                        PadInputChip(input: pi, control: control)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if !boundInputs.isEmpty {
                    Button {
                        store.clearPadControl(control, player: store.player)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Desasignar todos los botones de \(control.title)")
                }

                Button {
                    store.capturingPad = isCapturing ? nil : (store.player, control)
                } label: {
                    Image(systemName: isCapturing ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(isCapturing ? "Cancelar captura" : "Asignar botón")
            }
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCapturing ? Color.orange.opacity(0.15) : (isActive ? Color.green.opacity(0.12) : .clear))
        )
    }
}

struct PadInputChip: View {
    @EnvironmentObject var store: Store
    let input: PadInput
    let control: Control
    @State private var hover = false

    var isPressed: Bool { store.pressedPadInputs.contains(input) }

    var body: some View {
        let col = Color(nsColor: input.xboxColor)
        HStack(spacing: 4) {
            Circle()
                .fill(col)
                .frame(width: 6, height: 6)
            Text(input.xboxLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            Button {
                store.removePadInput(input, player: store.player, control: control)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(hover ? Color.red : Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isPressed ? Color.green : Color.white.opacity(0.18), lineWidth: isPressed ? 1.6 : 1)
        )
        .onHover { hover = $0 }
        .help("Xbox \(input.xboxTitle) — Haz clic en ✕ para desasignar")
    }
}

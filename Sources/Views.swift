import AppKit
import SwiftUI

@main
struct NXControlesApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("NX Controles") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 920, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) {} }
        Settings { SettingsView().environmentObject(store) }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 205, ideal: 235, max: 275)
        } detail: {
            if store.selectedID == RemoteStore.sidebarID {
                NXRemoteDashboardView(remote: store.remote)
            } else if let g = store.selection {
                EditorView(game: g).id(g.id)
            } else {
                Text("Elige un juego").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            Picker("Categoría", selection: $store.gameFilter) {
                Text("Todos (\(store.games.count))").tag(GameFilter.all)
                Text("Nativos (\(store.nativeGamesCount))").tag(GameFilter.native)
                Text("Astris (\(store.astrisGamesCount))").tag(GameFilter.astris)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            List(selection: $store.selectedID) {
                Section("Mando Móvil (NX Remote)") {
                    NavigationLink(value: RemoteStore.sidebarID) {
                        RemoteSidebarRow(remote: store.remote)
                    }
                }
                Section("Perfil Global") {
                    NavigationLink(value: "") {
                        GameRow(game: .global)
                    }
                }
                Section("Juegos (\(store.filteredGames.count))") {
                    ForEach(store.filteredGames) { g in
                        NavigationLink(value: g.id) {
                            GameRow(game: g)
                        }
                    }
                    if store.filteredGames.isEmpty {
                        Text(emptyFilterMessage)
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .toolbar {
            ToolbarItem {
                Button { store.scan(); store.refreshControllers(); store.remote.refreshNetworkInfo() } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }.help("Volver a buscar juegos y mandos")
            }
        }
    }

    private var emptyFilterMessage: String {
        switch store.gameFilter {
        case .all: return "No se encontraron juegos. Añade tu carpeta en Ajustes (⌘,)."
        case .native: return "No hay juegos nativos instalados."
        case .astris: return "No hay juegos de Astris encontrados en /Volumes/Externo/Games/Astris Games."
        }
    }
}

struct RemoteSidebarRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject var remote: RemoteStore

    var isSelected: Bool {
        store.selectedID == RemoteStore.sidebarID
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Conectar Móvil")
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Text(remote.isConnected ? "Activo • \(remote.pps) Hz" : "Código QR y PIN (\(remote.pairingCode))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(remote.isConnected ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(remote.isConnected || !store.connectedPads.isEmpty ? Color.green : Color.cyan)
                .frame(width: 8, height: 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedID = RemoteStore.sidebarID
        }
        .padding(.vertical, 4)
    }
}

struct GameRow: View {
    @EnvironmentObject var store: Store
    let game: Game
    var isSelected: Bool {
        game.isGlobal ? (store.selectedID ?? "").isEmpty : store.selectedID == game.id
    }

    var body: some View {
        HStack(spacing: 10) {
            GameIcon(game: game, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(game.name)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if game.engine == "Astris" {
                        Text("Astris")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                Text(game.isGlobal ? "Base para todos los juegos" : game.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 5) {
                if store.hasOwnPadMap(game) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(.cyan)
                        .font(.caption)
                }
                if store.hasOwnKeyMap(game) {
                    Image(systemName: "keyboard.fill")
                        .foregroundStyle(.tint)
                        .font(.caption)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedID = game.id
        }
        .padding(.vertical, 4)
    }
}

struct GameIcon: View {
    let game: Game; let size: CGFloat
    var body: some View {
        Group {
            if let url = game.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(game.isGlobal ? Color.accentColor.gradient : Color.gray.gradient)
                    .overlay(
                        Image(systemName: game.isGlobal ? "globe" : "gamecontroller.fill")
                            .font(.system(size: size * 0.45))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Main Editor View

struct EditorView: View {
    @EnvironmentObject var store: Store
    let game: Game
    @State private var confirmReset = false
    @State private var showSaveProfileSheet = false
    @State private var showManageProfilesSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBar

                NXRemoteExpandableBanner(remote: store.remote, isExpanded: $store.showRemoteBanner)
                playerSelectorBar

                if let err = store.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if store.deviceMode == .gamepad {
                    XboxControllerEditorSection()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18, alignment: .top)], spacing: 18) {
                        ForEach(ControlGroup.all) { GroupCard(group: $0) }
                    }
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(game.name)
        .toolbar { toolbar }
        .sheet(isPresented: $showSaveProfileSheet) {
            SaveProfileSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showManageProfilesSheet) {
            ProfilesManagerSheet()
                .environmentObject(store)
        }
        .confirmationDialog(
            "¿Restablecer los controles de \(store.deviceMode.rawValue) de \(game.name)?",
            isPresented: $confirmReset
        ) {
            Button("Restablecer", role: .destructive) { store.resetToInherited() }
        } message: {
            Text(
                game.isGlobal
                    ? "Volverán a los controles de fábrica de nxnative."
                    : "Volverá a usar el mapa global o el estándar de nxnative."
            )
        }
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            GameIcon(game: game, size: 52)
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    if game.engine == "Astris" {
                        Text("Astris")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    sourceBadge
                    if !game.isGlobal {
                        Text(game.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if game.engine == "Astris", let rom = game.romURL {
                Button {
                    AstrisConfig.ensureDSUConfigured()
                    let astrisApp = URL(fileURLWithPath: "/Volumes/Externo/Games/Astris.app")
                    if FileManager.default.fileExists(atPath: astrisApp.path) {
                        let config = NSWorkspace.OpenConfiguration()
                        config.activates = true
                        NSWorkspace.shared.open([rom], withApplicationAt: astrisApp, configuration: config, completionHandler: nil)
                    } else {
                        NSWorkspace.shared.open(rom)
                    }
                } label: {
                    Label("Jugar en Astris", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 10)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else if let url = game.appURL, url.pathExtension == "app" {
                Button {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                } label: {
                    Label("Jugar", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 10)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var sourceBadge: some View {
        let (t, c): (String, Color) = switch store.activeSource {
        case .own: ("Perfil personalizado", .green)
        case .global: ("Usa el perfil global", .blue)
        case .builtIn: ("Controles estándar", .secondary)
        }
        return Text(t)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(c.opacity(0.15), in: Capsule())
            .foregroundStyle(c)
    }

    private var playerSelectorBar: some View {
        VStack(spacing: 10) {
            // Row 1: Player 1-8 Selection with device icons
            HStack(spacing: 8) {
                playerRow()

                Spacer(minLength: 8)

                Menu {
                    ForEach(0..<kPlayers, id: \.self) { p in
                        if p != store.player {
                            Button("Copiar del Jugador \(p + 1)") {
                                store.copyPlayer(p, to: store.player)
                            }
                        }
                    }
                    Divider()
                    Section("Perfiles de Controles") {
                        Button("Guardar ajustes de J\(store.player + 1) como perfil…") {
                            showSaveProfileSheet = true
                        }
                        Button("Gestionar y renombrar perfiles…") {
                            showManageProfilesSheet = true
                        }
                    }
                    Divider()
                    if store.deviceMode == .gamepad {
                        Button("Restaurar Jugador \(store.player + 1) al estándar") {
                            store.resetPlayerPadToDefault(store.player)
                        }
                    } else {
                        Button("Vaciar teclado Jugador \(store.player + 1)", role: .destructive) {
                            store.clearPlayer(store.player)
                        }
                    }
                } label: {
                    Label("Opciones J\(store.player + 1)", systemImage: "ellipsis.circle")
                        .lineLimit(1)
                }
                .fixedSize()
            }

            // Row 2: Device Switcher + Unified Profile Menu (Never wraps, never overflows)
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Dispositivo:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        ForEach(InputDeviceMode.allCases) { mode in
                            let active = store.deviceMode == mode
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    store.setPlayerMode(mode, for: store.player)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(mode == .gamepad ? "Mando" : "Teclado")
                                        .font(.system(size: 11, weight: active ? .bold : .medium))
                                }
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .foregroundStyle(active ? .white : .primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(active ? Color.accentColor : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                }

                Divider().frame(height: 16)

                // Unified Profile Menu: displays active profile name AND lets you change it in 1 click!
                Menu {
                    let profs = store.customProfiles.filter { store.deviceMode == .gamepad ? $0.isGamepad : !$0.isGamepad }
                    if !profs.isEmpty {
                        Section("Mis Perfiles") {
                            ForEach(profs) { prof in
                                Button(prof.name) {
                                    store.applyProfile(prof, to: store.player)
                                }
                            }
                        }
                        Divider()
                    }
                    Section("Gestión de Perfiles") {
                        Button("Guardar ajustes actuales como nuevo perfil…", systemImage: "plus.circle") {
                            showSaveProfileSheet = true
                        }
                        Button("Gestionar y renombrar perfiles…", systemImage: "pencil.and.list.clipboard") {
                            showManageProfilesSheet = true
                        }
                    }
                    Divider()
                    if store.deviceMode == .keyboard {
                        Section("Plantillas de fábrica") {
                            Button("WASD estándar (Recomendado para Jugador 1)") {
                                store.applyKeyboardPreset(KeyMap.builtIn.keys[0], player: store.player)
                            }
                            Button("Flechas + Teclado Numérico (Recomendado para Jugador 2)") {
                                store.applyKeyboardPreset(KeyMap.player2ArrowsPreset(), player: store.player)
                            }
                            Button("IJKL + Teclado (Alternativo para Jugador 2)") {
                                store.applyKeyboardPreset(KeyMap.player2IJKLPreset(), player: store.player)
                            }
                        }
                        Divider()
                        Button("Vaciar todas las teclas de J\(store.player + 1)", role: .destructive) {
                            store.clearPlayer(store.player)
                        }
                    } else {
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
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.2.square")
                            .font(.system(size: 11))
                            .foregroundStyle(store.deviceMode == .gamepad ? .cyan : .orange)
                        Text("Perfil:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(store.currentProfileName(for: store.player, mode: store.deviceMode))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(store.deviceMode == .gamepad ? .cyan : .orange)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder((store.deviceMode == .gamepad ? Color.cyan : Color.orange).opacity(0.35))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                if store.deviceMode == .keyboard {
                    Button {
                        store.clearPlayer(store.player)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Vaciar")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    private func playerRow() -> some View {
        let connectedByPlayer = store.resolvedConnectedPadsByPlayer()
        return HStack(spacing: 5) {
            ForEach(0..<kPlayers, id: \.self) { p in
                let selected = store.player == p
                let pMode = store.playerDeviceModes[p]
                let connectedPadName = connectedByPlayer[p]
                let isConnected = pMode == .keyboard ? store.map.hasKeys(for: p) : (connectedPadName != nil || store.isPlayerConnected(p))
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        store.player = p
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: (pMode == .gamepad || connectedPadName != nil) ? "gamecontroller.fill" : "keyboard.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(selected ? .white : (isConnected ? .green : (pMode == .gamepad ? .cyan.opacity(0.65) : .orange.opacity(0.65))))

                        Text("J\(p + 1)")
                            .font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
                            .lineLimit(1)

                        if isConnected {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .shadow(color: Color.green.opacity(0.8), radius: 2)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(selected ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : (isConnected ? Color.green.opacity(0.45) : Color.primary.opacity(0.10)))
                    )
                }
                .buttonStyle(.plain)
                .help(
                    connectedPadName != nil
                        ? "Jugador \(p + 1): Conectado a «\(connectedPadName!)»"
                        : "Jugador \(p + 1): Sin mando conectado"
                )
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    store.showRemoteBanner.toggle()
                }
            } label: {
                Label("Conectar Móvil (QR)", systemImage: "qrcode.viewfinder")
            }
            .help("Mostrar u ocultar el código QR y PIN de NX Remote para conectar teléfonos")

            Button {
                showManageProfilesSheet = true
            } label: {
                Label("Perfiles", systemImage: "folder.badge.gearshape")
            }
            .help("Gestionar y renombrar perfiles guardados")

            Menu {
                if store.deviceMode == .gamepad {
                    Button("Mando estándar de Switch") { store.copyPad(from: .builtIn) }
                    if !game.isGlobal, let g = store.readPadMap(.global) {
                        Button("Mapa de mando global") { store.copyPad(from: g) }
                    }
                    let others = store.games.filter { $0 != game && store.hasOwnPadMap($0) }
                    if !others.isEmpty {
                        Divider()
                        ForEach(others) { o in
                            Button(o.name) { if let m = store.readPadMap(o) { store.copyPad(from: m) } }
                        }
                    }
                } else {
                    Button("Teclado por defecto de nxnative") { store.copy(from: .builtIn) }
                    if !game.isGlobal, let g = store.readKeyMap(.global) {
                        Button("Mapa de teclado global") { store.copy(from: g) }
                    }
                    let others = store.games.filter { $0 != game && store.hasOwnKeyMap($0) }
                    if !others.isEmpty {
                        Divider()
                        ForEach(others) { o in
                            Button(o.name) { if let m = store.readKeyMap(o) { store.copy(from: m) } }
                        }
                    }
                }
            } label: {
                Label("Copiar de…", systemImage: "doc.on.doc")
            }

            Button {
                let target: URL = if store.deviceMode == .gamepad {
                    store.hasOwnPadMap(game) ? Paths.padmap(game) : Paths.support
                } else {
                    store.hasOwnKeyMap(game) ? Paths.keymap(game) : Paths.support
                }
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } label: {
                Label("Mostrar en Finder", systemImage: "folder")
            }

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Restablecer", systemImage: "arrow.uturn.backward")
            }
            .disabled(store.activeSource != .own)
        }
    }
}

// MARK: - Keyboard Cards

struct GroupCard: View {
    @EnvironmentObject var store: Store
    let group: ControlGroup
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(group.title, systemImage: group.symbol).font(.headline)
            VStack(spacing: 8) { ForEach(group.controls) { ControlRow(control: $0) } }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

struct ControlRow: View {
    @EnvironmentObject var store: Store
    let control: Control
    var keys: [UInt16] { store.map.keys[store.player][control] ?? [] }
    var isCapturing: Bool { store.capturing?.player == store.player && store.capturing?.control == control }
    var isActive: Bool { keys.contains { store.pressed.contains($0) } }

    var body: some View {
        HStack(spacing: 8) {
            Glyph(control: control, active: isActive)
            Text(control.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 128, alignment: .leading)
            FlowKeys(keys: keys, control: control)
            Spacer(minLength: 4)
            Button {
                store.capturing = isCapturing ? nil : (store.player, control)
            } label: {
                Image(systemName: isCapturing ? "xmark" : "plus").frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered).controlSize(.small).help(isCapturing ? "Cancelar" : "Añadir tecla")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(isCapturing ? Color.accentColor.opacity(0.15) : isActive ? Color(nsColor: control.tint).opacity(0.12) : .clear))
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

struct Glyph: View {
    let control: Control; let active: Bool
    var body: some View {
        let tint = Color(nsColor: control.tint)
        let round = [.A, .B, .X, .Y, .LS, .RS, .PLUS, .MINUS, .SHAKE].contains(control)
        ZStack {
            if round { Circle().fill(active ? tint : tint.opacity(0.18)) }
            else { RoundedRectangle(cornerRadius: 6).fill(active ? tint : tint.opacity(0.18)) }
            Text(control.label).font(.system(size: control.label.count > 1 ? 11 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(active ? .white : tint)
        }
        .frame(width: 30, height: 30)
        .scaleEffect(active ? 1.12 : 1)
    }
}

struct FlowKeys: View {
    @EnvironmentObject var store: Store
    let keys: [UInt16]; let control: Control
    var body: some View {
        HStack(spacing: 5) {
            if store.capturing?.player == store.player && store.capturing?.control == control {
                Text("Pulsa una tecla…")
                    .font(.callout.italic())
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .phaseAnimator([0.4, 1.0]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.6) }
            } else if keys.isEmpty {
                Text("Sin asignar")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            ForEach(keys, id: \.self) { KeyChip(key: $0, control: control) }
        }
    }
}

struct KeyChip: View {
    @EnvironmentObject var store: Store
    let key: UInt16; let control: Control
    @State private var hover = false
    var body: some View {
        let others = store.uses(of: key).filter { !($0.0 == store.player && $0.1 == control) }
        let pressed = store.pressed.contains(key)
        HStack(spacing: 4) {
            if !others.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            Text(KeyNames.name(key))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if hover {
                Button { store.remove(key, player: store.player, control: control) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(pressed ? Color.accentColor.opacity(0.35) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.18)))
        .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
        .onHover { hover = $0 }
        .help(others.isEmpty ? "Clic en ✕ para quitar" : "También asignada a: " + others.map { "J\($0.0 + 1) \($0.1.title)" }.joined(separator: ", "))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var sel: String?
    var body: some View {
        Form {
            Section("Carpetas donde buscar las apps de los juegos (.app de nxnative)") {
                List(store.scanFolders, id: \.self, selection: $sel) { Text($0).font(.callout.monospaced()) }.frame(height: 160)
                HStack {
                    Button("Añadir carpeta…") {
                        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
                        if p.runModal() == .OK { store.scanFolders += p.urls.map(\.path).filter { !store.scanFolders.contains($0) } }
                    }
                    Button("Quitar") { if let s = sel { store.scanFolders.removeAll { $0 == s } } }.disabled(sel == nil)
                }
            }
        }
        .padding().frame(width: 520)
    }
}

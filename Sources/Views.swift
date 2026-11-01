import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first {
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
        }
    }
}

@main
struct NXControlesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("NX Controles") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
        Settings { SettingsView().environmentObject(store) }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ZStack {
            // 1. Lienzo Cósmico Full-Bleed (Azul Neón & Rojo Neón)
            CosmicCanvasBackground()

            HStack(spacing: 0) {
                // 2. Navigation Rail de Cristal Bespoke
                Sidebar()
                    .frame(width: 250)

                Rectangle()
                    .fill(MacProTheme.glassBorder)
                    .frame(width: 0.5)
                    .ignoresSafeArea()

                // Área de Detalle Principal
                ZStack {
                    if store.selectedID == RemoteStore.sidebarID {
                        NXRemoteDashboardView(remote: store.remote)
                    } else if let g = store.selection {
                        EditorView(game: g).id(g.id)
                    } else {
                        emptySelectionView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 5. Botón Maestro Flotante Inferior Dual Azul & Rojo
            VStack {
                Spacer()
                floatingMasterBar
            }
            .ignoresSafeArea(.keyboard)
        }
    }

    private var emptySelectionView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MacProTheme.glassFill)
                    .frame(width: 84, height: 84)
                HStack(spacing: 4) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(MacProTheme.neonBlue)
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(MacProTheme.neonRed)
                }
                .font(.system(size: 28))
            }
            Text("Selecciona un juego para configurar sus controles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Text("Elige un juego de la barra lateral o configura el perfil global.")
                .font(.system(size: 12))
                .foregroundColor(MacProTheme.glassTextMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Floating Master Bar
    private var floatingMasterBar: some View {
        HStack(spacing: 14) {
            // Botón auxiliar: Actualizar
            circularGlassButton(icon: "arrow.clockwise", help: "Escanear juegos y mandos conectados") {
                store.scan()
                store.refreshControllers()
                store.remote.refreshNetworkInfo()
            }

            // Botón Maestro Central Glow en Azul & Rojo
            Button {
                if let g = store.selection {
                    if g.engine == "Astris", let rom = g.romURL {
                        AstrisConfig.ensureDSUConfigured()
                        let astrisApp = URL(fileURLWithPath: "/Volumes/Externo/Games/Astris.app")
                        if FileManager.default.fileExists(atPath: astrisApp.path) {
                            let config = NSWorkspace.OpenConfiguration()
                            config.activates = true
                            NSWorkspace.shared.open([rom], withApplicationAt: astrisApp, configuration: config, completionHandler: nil)
                        } else {
                            NSWorkspace.shared.open(rom)
                        }
                    } else if let url = g.appURL, url.pathExtension == "app" {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    } else {
                        store.selectedID = RemoteStore.sidebarID
                    }
                } else {
                    store.selectedID = RemoteStore.sidebarID
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: (store.selection != nil && store.selection?.isGlobal == false) ? "play.fill" : "gamecontroller.fill")
                        .font(.system(size: 15, weight: .bold))

                    Text(masterButtonTitle)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(MacProTheme.switchDualGradient)
                )
                .shadow(
                    color: MacProTheme.neonBlue.opacity(0.45),
                    radius: 16,
                    x: -4,
                    y: 3
                )
                .shadow(
                    color: MacProTheme.neonRed.opacity(0.45),
                    radius: 16,
                    x: 4,
                    y: 3
                )
            }
            .buttonStyle(.plain)

            // Botón auxiliar: Conectar Móvil
            circularGlassButton(icon: "qrcode.viewfinder", help: "Abrir conexión con mandos móviles") {
                withAnimation(.snappy(duration: 0.2)) {
                    store.selectedID = RemoteStore.sidebarID
                }
            }
        }
        .padding(.bottom, 22)
    }

    private var masterButtonTitle: String {
        if let g = store.selection, !g.isGlobal {
            return g.engine == "Astris" ? "Jugar en Astris" : "Jugar a \(g.name)"
        }
        return "Conectar Teléfonos / Mando"
    }

    private func circularGlassButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(MacProTheme.glassFill)
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(MacProTheme.glassBorder, lineWidth: 0.5)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Sidebar Bespoke de Cristal

struct Sidebar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            // Header con espacio despejado para los semáforos de macOS
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Logo Joy-Con Azul & Rojo
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MacProTheme.switchDualGradient)
                            .frame(width: 28, height: 28)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("NX")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundColor(MacProTheme.neonBlue)
                            Text("Controles")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundColor(MacProTheme.neonRed)
                        }
                        .lineLimit(1)

                        Text("Pro Gamepad Studio")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(MacProTheme.glassTextMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 42)
            .padding(.bottom, 16)

            // Filtro Segmentado Glass
            HStack(spacing: 4) {
                categoryTab(title: "Todos", count: store.games.count, tag: .all)
                categoryTab(title: "Nativos", count: store.nativeGamesCount, tag: .native)
                categoryTab(title: "Astris", count: store.astrisGamesCount, tag: .astris)
            }
            .padding(4)
            .background(MacProTheme.glassFill)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MacProTheme.glassBorder, lineWidth: 0.5))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            // Contenedor de Lista Bespoke (Sin List de Apple)
            ScrollView {
                VStack(spacing: 4) {
                    // Sección: Mando Móvil
                    sectionHeader("MANDO MÓVIL (NX REMOTE)")
                    RemoteSidebarRow(remote: store.remote)

                    // Sección: Perfil Global
                    sectionHeader("PERFIL GLOBAL")
                    GameRow(game: .global)

                    // Sección: Juegos
                    sectionHeader("JUEGOS (\(store.filteredGames.count))")
                    ForEach(store.filteredGames) { g in
                        GameRow(game: g)
                    }

                    if store.filteredGames.isEmpty {
                        Text(emptyFilterMessage)
                            .font(.system(size: 11))
                            .foregroundColor(MacProTheme.glassTextMuted)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 24)
            }

            Spacer()

            // Hardware Status Pill Inferior
            hardwareStatusPill
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
    }

    private func categoryTab(title: String, count: Int, tag: GameFilter) -> some View {
        let isSelected = store.gameFilter == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                store.gameFilter = tag
            }
        } label: {
            Text("\(title) (\(count))")
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : MacProTheme.glassTextMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? MacProTheme.blueGradient : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? MacProTheme.neonBlue.opacity(0.6) : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.40))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var hardwareStatusPill: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill((store.remote.isConnected || !store.connectedPads.isEmpty) ? MacProTheme.emeraldGreen : MacProTheme.neonRed)
                    .frame(width: 8, height: 8)
                    .shadow(color: ((store.remote.isConnected || !store.connectedPads.isEmpty) ? MacProTheme.emeraldGreen : MacProTheme.neonRed).opacity(0.8), radius: 5)

                Text(store.remote.isConnected ? "Mando Móvil Conectado" : (!store.connectedPads.isEmpty ? "Mando Físico Activo" : "Esperando Mando"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }

            if !store.connectedPads.isEmpty {
                Text(store.connectedPads.joined(separator: ", "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(MacProTheme.neonBlue)
                    .lineLimit(1)
            } else {
                Text("UDP Bridge Activo · Puerto 8765")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(MacProTheme.glassTextMuted)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 12)
    }

    private var emptyFilterMessage: String {
        switch store.gameFilter {
        case .all: return "No se encontraron juegos instalados."
        case .native: return "No hay juegos nativos en las carpetas."
        case .astris: return "No hay juegos de Astris encontrados."
        }
    }
}

// MARK: - Filas Bespoke de la Barra Lateral

struct RemoteSidebarRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject var remote: RemoteStore

    var isSelected: Bool {
        store.selectedID == RemoteStore.sidebarID
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                store.selectedID = RemoteStore.sidebarID
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MacProTheme.switchDualGradient)
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Conectar Móvil")
                        .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))
                        .lineLimit(1)
                    Text(remote.isConnected ? "Activo · \(remote.pps) Hz" : "QR / PIN (\(remote.pairingCode))")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(remote.isConnected ? MacProTheme.emeraldGreen : MacProTheme.neonBlue)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)

                Circle()
                    .fill(remote.isConnected ? MacProTheme.emeraldGreen : MacProTheme.neonBlue)
                    .frame(width: 6, height: 6)
                    .shadow(color: (remote.isConnected ? MacProTheme.emeraldGreen : MacProTheme.neonBlue).opacity(0.8), radius: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? MacProTheme.glassSelected : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? MacProTheme.neonBlue.opacity(0.5) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GameRow: View {
    @EnvironmentObject var store: Store
    let game: Game

    var isSelected: Bool {
        game.isGlobal ? (store.selectedID ?? "").isEmpty : store.selectedID == game.id
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                store.selectedID = game.isGlobal ? "" : game.id
            }
        } label: {
            HStack(spacing: 10) {
                GameIcon(game: game, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(game.name)
                            .font(.system(size: 12.5, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))
                            .lineLimit(1)

                        if game.engine == "Astris" {
                            Text("Astris")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(MacProTheme.neonRed.opacity(0.85))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text(game.isGlobal ? "Base para todos los juegos" : game.id)
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundColor(MacProTheme.glassTextMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    if store.hasOwnPadMap(game) {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundColor(MacProTheme.neonBlue)
                            .font(.system(size: 10))
                    }
                    if store.hasOwnKeyMap(game) {
                        Image(systemName: "keyboard.fill")
                            .foregroundColor(MacProTheme.neonRed)
                            .font(.system(size: 10))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? MacProTheme.glassSelected : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? (game.isGlobal ? MacProTheme.neonBlue : MacProTheme.neonRed).opacity(0.4) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GameIcon: View {
    let game: Game
    let size: CGFloat

    var body: some View {
        Group {
            if let url = game.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(game.isGlobal ? MacProTheme.blueGradient : MacProTheme.redGradient)
                    .overlay(
                        Image(systemName: game.isGlobal ? "globe" : "gamecontroller.fill")
                            .font(.system(size: size * 0.45))
                            .foregroundColor(.white)
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
                        .foregroundColor(MacProTheme.neonRed)
                        .font(.system(size: 12))
                }

                if store.deviceMode == .gamepad {
                    XboxControllerEditorSection()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18, alignment: .top)], spacing: 18) {
                        ForEach(ControlGroup.all) { GroupCard(group: $0) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 90)
        }
        .sheet(isPresented: $showSaveProfileSheet) {
            SaveProfileSheet().environmentObject(store)
        }
        .sheet(isPresented: $showManageProfilesSheet) {
            ProfilesManagerSheet().environmentObject(store)
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
            GameIcon(game: game, size: 54)
                .shadow(color: MacProTheme.neonBlue.opacity(0.25), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if game.engine == "Astris" {
                        Text("Astris")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MacProTheme.neonRed.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    sourceBadge
                    if !game.isGlobal {
                        Text(game.id)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(MacProTheme.glassTextMuted)
                            .lineLimit(1)
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
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(MacProTheme.redGradient)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: MacProTheme.neonRed.opacity(0.45), radius: 8)
                }
                .buttonStyle(.plain)
            } else if let url = game.appURL, url.pathExtension == "app" {
                Button {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                } label: {
                    Label("Jugar", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(MacProTheme.blueGradient)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: MacProTheme.neonBlue.opacity(0.45), radius: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private var sourceBadge: some View {
        let (t, c): (String, Color) = switch store.activeSource {
        case .own: ("Perfil personalizado", MacProTheme.neonRed)
        case .global: ("Usa perfil global", MacProTheme.neonBlue)
        case .builtIn: ("Controles estándar", MacProTheme.glassTextMuted)
        }
        return Text(t)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(c.opacity(0.15))
            .foregroundColor(c)
            .clipShape(Capsule())
    }

    private var playerSelectorBar: some View {
        VStack(spacing: 10) {
            // Fila 1: Jugadores 1-8
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MacProTheme.neonBlue)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Fila 2: Conmutador de Dispositivo & Menú de Perfiles
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Dispositivo:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
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
                                .foregroundColor(active ? .white : Color.white.opacity(0.7))
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(active ? (mode == .gamepad ? MacProTheme.neonBlue.opacity(0.85) : MacProTheme.neonRed.opacity(0.85)) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(active ? Color.white.opacity(0.4) : Color.clear, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(MacProTheme.glassFill)
                    .cornerRadius(8)
                }

                Divider().frame(height: 16)

                // Menú unificado de perfil
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
                            .foregroundColor(store.deviceMode == .gamepad ? MacProTheme.neonBlue : MacProTheme.neonRed)
                        Text("Perfil:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(MacProTheme.glassTextMuted)
                        Text(store.currentProfileName(for: store.player, mode: store.deviceMode))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(store.deviceMode == .gamepad ? MacProTheme.neonBlue : MacProTheme.neonRed)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(MacProTheme.glassTextMuted)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassCard(cornerRadius: 7)
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
                        .foregroundColor(MacProTheme.neonRed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassCard(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCard(cornerRadius: 11)
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
                let playerColor = (p % 2 == 0) ? MacProTheme.neonBlue : MacProTheme.neonRed
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        store.player = p
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: (pMode == .gamepad || connectedPadName != nil) ? "gamecontroller.fill" : "keyboard.fill")
                            .font(.system(size: 10))
                            .foregroundColor(selected ? .white : (isConnected ? MacProTheme.emeraldGreen : playerColor.opacity(0.70)))

                        Text("J\(p + 1)")
                            .font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
                            .lineLimit(1)

                        if isConnected {
                            Circle()
                                .fill(MacProTheme.emeraldGreen)
                                .frame(width: 5, height: 5)
                                .shadow(color: MacProTheme.emeraldGreen.opacity(0.8), radius: 3)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundColor(selected ? .white : Color.white.opacity(0.75))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? playerColor : MacProTheme.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Keyboard Cards

struct GroupCard: View {
    @EnvironmentObject var store: Store
    let group: ControlGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(group.title, systemImage: group.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MacProTheme.neonBlue)
                .lineLimit(1)

            VStack(spacing: 6) {
                ForEach(group.controls) { ControlRow(control: $0) }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            FlowKeys(keys: keys, control: control)

            Spacer(minLength: 4)

            Button {
                store.capturing = isCapturing ? nil : (store.player, control)
            } label: {
                Image(systemName: isCapturing ? "xmark" : "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .glassCard(cornerRadius: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCapturing ? MacProTheme.neonBlue.opacity(0.20) : (isActive ? MacProTheme.neonRed.opacity(0.20) : Color.clear))
        )
    }
}

struct Glyph: View {
    let control: Control
    let active: Bool

    var body: some View {
        let isRightOrRed = [.A, .X, .R, .ZR, .PLUS, .RS].contains(control)
        let glyphColor = isRightOrRed ? MacProTheme.neonRed : MacProTheme.neonBlue
        let round = [.A, .B, .X, .Y, .LS, .RS, .PLUS, .MINUS, .SHAKE].contains(control)
        ZStack {
            if round {
                Circle().fill(active ? glyphColor : glyphColor.opacity(0.20))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(active ? glyphColor : glyphColor.opacity(0.20))
            }
            Text(control.label)
                .font(.system(size: control.label.count > 1 ? 10 : 13, weight: .bold, design: .rounded))
                .foregroundColor(active ? .white : glyphColor)
        }
        .frame(width: 28, height: 28)
        .scaleEffect(active ? 1.10 : 1.0)
    }
}

struct FlowKeys: View {
    @EnvironmentObject var store: Store
    let keys: [UInt16]
    let control: Control

    var body: some View {
        HStack(spacing: 5) {
            if store.capturing?.player == store.player && store.capturing?.control == control {
                Text("Pulsa una tecla…")
                    .font(.system(size: 11).italic())
                    .foregroundColor(MacProTheme.neonBlue)
                    .lineLimit(1)
            } else if keys.isEmpty {
                Text("Sin asignar")
                    .font(.system(size: 11))
                    .foregroundColor(MacProTheme.glassTextMuted)
                    .lineLimit(1)
            }
            ForEach(keys, id: \.self) { KeyChip(key: $0, control: control) }
        }
    }
}

struct KeyChip: View {
    @EnvironmentObject var store: Store
    let key: UInt16
    let control: Control
    @State private var hover = false

    var body: some View {
        let others = store.uses(of: key).filter { !($0.0 == store.player && $0.1 == control) }
        let pressed = store.pressed.contains(key)
        HStack(spacing: 4) {
            if !others.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(MacProTheme.neonRed)
            }
            Text(KeyNames.name(key))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            if hover {
                Button { store.remove(key, player: store.player, control: control) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(MacProTheme.glassTextMuted)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(pressed ? MacProTheme.neonBlue.opacity(0.40) : MacProTheme.glassFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(MacProTheme.glassBorder, lineWidth: 0.5)
        )
        .onHover { hover = $0 }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var sel: String?

    var body: some View {
        ZStack {
            CosmicCanvasBackground()

            Form {
                Section {
                    List(store.scanFolders, id: \.self, selection: $sel) {
                        Text($0).font(.system(size: 11, design: .monospaced))
                    }
                    .frame(height: 160)
                    .glassCard(cornerRadius: 10)

                    HStack {
                        Button("Añadir carpeta…") {
                            let p = NSOpenPanel()
                            p.canChooseDirectories = true
                            p.canChooseFiles = false
                            p.allowsMultipleSelection = true
                            if p.runModal() == .OK {
                                store.scanFolders += p.urls.map(\.path).filter { !store.scanFolders.contains($0) }
                            }
                        }
                        .glassCard(cornerRadius: 6)

                        Button("Quitar") {
                            if let s = sel { store.scanFolders.removeAll { $0 == s } }
                        }
                        .disabled(sel == nil)
                        .glassCard(cornerRadius: 6)
                    }
                } header: {
                    Text("Carpetas donde buscar apps de juegos (.app de nxnative)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(24)
            .frame(width: 520)
        }
    }
}

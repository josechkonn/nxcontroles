import AppKit
import Combine
import CoreGraphics
import CoreImage
import Foundation
import IOBluetooth
import Network
import QuartzCore
import SwiftUI

// MARK: - JoyCon State & Key Injector

public struct JoyConState: Equatable {
    public var mode: String = "grip"
    public var player: Int = 0 // 0 = Player 1, 1 = Player 2
    public var pressedButtons: Set<String> = []
    public var lx: Double = 0.0
    public var ly: Double = 0.0
    public var rx: Double = 0.0
    public var ry: Double = 0.0
    public var ax: Double = 0.0
    public var ay: Double = 0.0
    public var az: Double = 0.0
    public var gx: Double = 0.0
    public var gy: Double = 0.0
    public var gz: Double = 0.0
    public var isShaking: Bool = false
    public var lastPacketDate: Date = Date()
    public var packetsPerSecond: Int = 0

    static func from(padInputs: Set<PadInput>, ls: CGPoint, rs: CGPoint, player: Int) -> JoyConState {
        var buttons = Set<String>()
        if padInputs.contains(.A) { buttons.insert("A") }
        if padInputs.contains(.B) { buttons.insert("B") }
        if padInputs.contains(.X) { buttons.insert("X") }
        if padInputs.contains(.Y) { buttons.insert("Y") }
        if padInputs.contains(.LB) { buttons.insert("L") }
        if padInputs.contains(.RB) { buttons.insert("R") }
        if padInputs.contains(.LT) { buttons.insert("ZL") }
        if padInputs.contains(.RT) { buttons.insert("ZR") }
        if padInputs.contains(.VIEW) { buttons.insert("MINUS") }
        if padInputs.contains(.MENU) { buttons.insert("PLUS") }
        if padInputs.contains(.LS) { buttons.insert("LS") }
        if padInputs.contains(.RS) { buttons.insert("RS") }
        if padInputs.contains(.DUP) { buttons.insert("UP") }
        if padInputs.contains(.DDOWN) { buttons.insert("DOWN") }
        if padInputs.contains(.DLEFT) { buttons.insert("LEFT") }
        if padInputs.contains(.DRIGHT) { buttons.insert("RIGHT") }
        return JoyConState(
            player: player,
            pressedButtons: buttons,
            lx: Double(ls.x),
            ly: Double(ls.y),
            rx: Double(rs.x),
            ry: Double(rs.y)
        )
    }
}

public final class KeyInjector {
    public static let nxnativeMapping: [String: CGKeyCode] = [
        "A": 38,     // J
        "B": 40,     // K
        "X": 32,     // U
        "Y": 34,     // I
        "L": 12,     // Q
        "R": 14,     // E
        "ZL": 6,     // Z
        "ZR": 8,     // C
        "PLUS": 36,  // Return
        "MINUS": 48, // Tab
        "LS": 3,     // F
        "RS": 5,     // G
        "UP": 126,   // Arrow Up
        "DOWN": 125, // Arrow Down
        "LEFT": 123, // Arrow Left
        "RIGHT": 124,// Arrow Right
        "LUP": 13,   // W
        "LDOWN": 1,  // S
        "LLEFT": 0,  // A
        "LRIGHT": 2, // D
        "SL": 12,    // Map to L
        "SR": 14,    // Map to R
        "SHAKE": 49  // Spacebar (DM_BTN_SHAKE)
    ]

    public static let player2Mapping: [String: CGKeyCode] = [
        "A": 83,     // Num 1
        "B": 84,     // Num 2
        "X": 86,     // Num 4
        "Y": 87,     // Num 5
        "L": 89,     // Num 7
        "R": 91,     // Num 8
        "ZL": 82,    // Num 0
        "ZR": 65,    // Num .
        "PLUS": 76,  // Num Enter
        "MINUS": 78, // Num -
        "LS": 71,    // Num Clear
        "RS": 81,    // Num =
        "UP": 126,   // Arrow Up
        "DOWN": 125, // Arrow Down
        "LEFT": 123, // Arrow Left
        "RIGHT": 124,// Arrow Right
        "LUP": 126,  // Arrow Up
        "LDOWN": 125,// Arrow Down
        "LLEFT": 123,// Arrow Left
        "LRIGHT": 124,// Arrow Right
        "SL": 89,    // Map to L
        "SR": 91,    // Map to R
        "SHAKE": 71  // Num Clear
    ]

    public static let astrisMapping: [String: CGKeyCode] = [
        "A": 6,      // Z
        "B": 7,      // X
        "X": 8,      // C
        "Y": 9,      // V
        "L": 14,     // E
        "R": 32,     // U
        "ZL": 12,    // Q
        "ZR": 31,    // O
        "PLUS": 24,  // = / Plus
        "MINUS": 27, // - / Minus
        "LS": 3,     // F
        "RS": 4,     // H
        "UP": 126,   // Arrow Up
        "DOWN": 125, // Arrow Down
        "LEFT": 123, // Arrow Left
        "RIGHT": 124,// Arrow Right
        "LUP": 13,   // W
        "LDOWN": 1,  // S
        "LLEFT": 0,  // A
        "LRIGHT": 2, // D
        "RUP": 34,   // I
        "RDOWN": 40, // K
        "RLEFT": 38, // J
        "RRIGHT": 37,// L
        "SL": 15,    // R
        "SR": 17,    // T
        "SHAKE": 49  // Spacebar
    ]

    private var playerMappings: [[String: CGKeyCode]] = [
        KeyInjector.nxnativeMapping, // J1
        KeyInjector.player2Mapping,  // J2
        [:],                         // J3
        [:],                         // J4
        [:],                         // J5
        [:],                         // J6
        [:],                         // J7
        [:]                          // J8
    ]
    public private(set) var currentlyPressedKeys: [Int: Set<CGKeyCode>] = [
        0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []
    ]

    public var hasActivePressedKeys: Bool {
        currentlyPressedKeys.values.contains { !$0.isEmpty }
    }

    public init() {
        loadCustomKeymapIfExists()
    }

    public func loadCustomKeymapIfExists() {
        let keymapUrl = Paths.support.appendingPathComponent("keymap.tsv")
        if let content = try? String(contentsOf: keymapUrl, encoding: .utf8) {
            parseKeymapTSV(content)
        }
    }

    private func parseKeymapTSV(_ tsv: String) {
        for line in tsv.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.components(separatedBy: "\t")
            if parts.count >= 3, let p = Int(parts[0]), p >= 1, p <= 8 {
                let control = parts[1]
                if let code = UInt16(parts[2]) {
                    playerMappings[p - 1][control] = CGKeyCode(code)
                }
            }
        }
        for p in 0..<8 {
            if let lCode = playerMappings[p]["L"] { playerMappings[p]["SL"] = lCode }
            if let rCode = playerMappings[p]["R"] { playerMappings[p]["SR"] = rCode }
        }
    }

    public func updateState(_ state: JoyConState, isAstris: Bool = false) {
        let p = max(0, min(7, state.player))
        let activeMap = isAstris ? Self.astrisMapping : playerMappings[p]
        var desiredKeys: Set<CGKeyCode> = []

        for btn in state.pressedButtons {
            if let keyCode = activeMap[btn] {
                desiredKeys.insert(keyCode)
            }
        }

        if state.isShaking, let k = activeMap["SHAKE"] {
            desiredKeys.insert(k)
        }

        let threshold = 0.35
        if state.ly > threshold, let k = activeMap["LUP"] { desiredKeys.insert(k) }
        if state.ly < -threshold, let k = activeMap["LDOWN"] { desiredKeys.insert(k) }
        if state.lx < -threshold, let k = activeMap["LLEFT"] { desiredKeys.insert(k) }
        if state.lx > threshold, let k = activeMap["LRIGHT"] { desiredKeys.insert(k) }

        if state.ry > threshold, let k = activeMap["RUP"] { desiredKeys.insert(k) }
        if state.ry < -threshold, let k = activeMap["RDOWN"] { desiredKeys.insert(k) }
        if state.rx < -threshold, let k = activeMap["RLEFT"] { desiredKeys.insert(k) }
        if state.rx > threshold, let k = activeMap["RRIGHT"] { desiredKeys.insert(k) }

        let previous = currentlyPressedKeys[p] ?? []
        let toPress = desiredKeys.subtracting(previous)
        for key in toPress {
            postKey(key, isDown: true)
        }

        let toRelease = previous.subtracting(desiredKeys)
        for key in toRelease {
            postKey(key, isDown: false)
        }

        currentlyPressedKeys[p] = desiredKeys
    }

    func updateFromPadInputs(_ inputs: Set<PadInput>, ls: CGPoint, rs: CGPoint, player: Int = 0, isAstris: Bool = false) {
        let p = max(0, min(7, player))
        let activeMap = isAstris ? Self.astrisMapping : playerMappings[p]
        var desiredKeys: Set<CGKeyCode> = []

        for pi in inputs {
            let keyName: String
            switch pi {
            case .A: keyName = "A"
            case .B: keyName = "B"
            case .X: keyName = "X"
            case .Y: keyName = "Y"
            case .LB: keyName = "L"
            case .RB: keyName = "R"
            case .LT: keyName = "ZL"
            case .RT: keyName = "ZR"
            case .MENU: keyName = "PLUS"
            case .VIEW: keyName = "MINUS"
            case .LS: keyName = "LS"
            case .RS: keyName = "RS"
            case .DUP: keyName = "UP"
            case .DDOWN: keyName = "DOWN"
            case .DLEFT: keyName = "LEFT"
            case .DRIGHT: keyName = "RIGHT"
            case .LUP: keyName = "LUP"
            case .LDOWN: keyName = "LDOWN"
            case .LLEFT: keyName = "LLEFT"
            case .LRIGHT: keyName = "LRIGHT"
            case .RUP: keyName = "RUP"
            case .RDOWN: keyName = "RDOWN"
            case .RLEFT: keyName = "RLEFT"
            case .RRIGHT: keyName = "RRIGHT"
            }
            if let code = activeMap[keyName] {
                desiredKeys.insert(code)
            }
        }

        let threshold = 0.35
        if ls.y > threshold, let k = activeMap["LUP"] { desiredKeys.insert(k) }
        if ls.y < -threshold, let k = activeMap["LDOWN"] { desiredKeys.insert(k) }
        if ls.x < -threshold, let k = activeMap["LLEFT"] { desiredKeys.insert(k) }
        if ls.x > threshold, let k = activeMap["LRIGHT"] { desiredKeys.insert(k) }

        if rs.y > threshold, let k = activeMap["RUP"] { desiredKeys.insert(k) }
        if rs.y < -threshold, let k = activeMap["RDOWN"] { desiredKeys.insert(k) }
        if rs.x < -threshold, let k = activeMap["RLEFT"] { desiredKeys.insert(k) }
        if rs.x > threshold, let k = activeMap["RRIGHT"] { desiredKeys.insert(k) }

        let previous = currentlyPressedKeys[p] ?? []
        let toPress = desiredKeys.subtracting(previous)
        for key in toPress {
            postKey(key, isDown: true)
        }

        let toRelease = previous.subtracting(desiredKeys)
        for key in toRelease {
            postKey(key, isDown: false)
        }

        currentlyPressedKeys[p] = desiredKeys
    }

    private func postKey(_ key: CGKeyCode, isDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else { return }
        event.post(tap: .cghidEventTap)
    }

    public func releaseAll(player: Int? = nil) {
        if let p = player {
            if let keys = currentlyPressedKeys[p] {
                for key in keys { postKey(key, isDown: false) }
                currentlyPressedKeys[p] = []
            }
        } else {
            for (p, keys) in currentlyPressedKeys {
                for key in keys { postKey(key, isDown: false) }
                currentlyPressedKeys[p] = []
            }
        }
    }
}

// MARK: - Shared Motion for nxnative

public struct NxMotionShared {
    public var timestamp: UInt64
    public var ax: Float
    public var ay: Float
    public var az: Float
    public var gx: Float
    public var gy: Float
    public var gz: Float
    public var isShaking: UInt32

    private static var motionFds: [Int32] = [-1, -1, -1, -1, -1, -1, -1, -1]
    public static func writeShared(_ state: JoyConState, player: Int = 0) {
        let p = max(0, min(7, player))
        if motionFds[p] < 0 {
            let path = "/tmp/nx_motion_p\(p + 1).dat"
            motionFds[p] = open(path, O_RDWR | O_CREAT, 0o666)
        }
        guard motionFds[p] >= 0 else { return }
        var pkt = NxMotionShared(
            timestamp: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW),
            ax: Float(state.ax),
            ay: Float(state.ay),
            az: Float(state.az),
            gx: Float(state.gx),
            gy: Float(state.gy),
            gz: Float(state.gz),
            isShaking: state.isShaking ? 1 : 0
        )
        _ = withUnsafeBytes(of: &pkt) { ptr in
            pwrite(motionFds[p], ptr.baseAddress, ptr.count, 0)
        }
    }

    public static func clear(player: Int = 0) {
        let p = max(0, min(7, player))
        if motionFds[p] < 0 {
            let path = "/tmp/nx_motion_p\(p + 1).dat"
            motionFds[p] = open(path, O_RDWR | O_CREAT, 0o666)
        }
        guard motionFds[p] >= 0 else { return }
        var pkt = NxMotionShared(
            timestamp: 0,
            ax: 0,
            ay: 0,
            az: 0,
            gx: 0,
            gy: 0,
            gz: 0,
            isShaking: 0
        )
        _ = withUnsafeBytes(of: &pkt) { ptr in
            pwrite(motionFds[p], ptr.baseAddress, ptr.count, 0)
        }
    }
}

// MARK: - Shared Gamepad State for nxnative

public struct NxPadShared {
    public var timestamp: UInt64
    public var buttons: UInt64
    public var lx: Int32
    public var ly: Int32
    public var rx: Int32
    public var ry: Int32

    private static var padFds: [Int32] = [-1, -1, -1, -1, -1, -1, -1, -1]

    public static func writeShared(_ state: JoyConState, player: Int = 0) {
        let p = max(0, min(7, player))
        if padFds[p] < 0 {
            let path = "/tmp/nx_pad_p\(p + 1).dat"
            padFds[p] = open(path, O_RDWR | O_CREAT, 0o666)
        }
        guard padFds[p] >= 0 else { return }

        var btns: UInt64 = 0
        if state.pressedButtons.contains("A") { btns |= (1 << 0) }
        if state.pressedButtons.contains("B") { btns |= (1 << 1) }
        if state.pressedButtons.contains("X") { btns |= (1 << 2) }
        if state.pressedButtons.contains("Y") { btns |= (1 << 3) }
        if state.pressedButtons.contains("LS") { btns |= (1 << 4) }
        if state.pressedButtons.contains("RS") { btns |= (1 << 5) }
        if state.pressedButtons.contains("L") { btns |= (1 << 6) }
        if state.pressedButtons.contains("R") { btns |= (1 << 7) }
        if state.pressedButtons.contains("ZL") { btns |= (1 << 8) }
        if state.pressedButtons.contains("ZR") { btns |= (1 << 9) }
        if state.pressedButtons.contains("PLUS") { btns |= (1 << 10) }
        if state.pressedButtons.contains("MINUS") { btns |= (1 << 11) }
        if state.pressedButtons.contains("LEFT") { btns |= (1 << 12) }
        if state.pressedButtons.contains("UP") { btns |= (1 << 13) }
        if state.pressedButtons.contains("RIGHT") { btns |= (1 << 14) }
        if state.pressedButtons.contains("DOWN") { btns |= (1 << 15) }
        if state.pressedButtons.contains("SL") { btns |= (1 << 6) | (1 << 24) | (1 << 26) }
        if state.pressedButtons.contains("SR") { btns |= (1 << 7) | (1 << 25) | (1 << 27) }

        // Analog stick deflection clamped to -32767..32767
        var clx = Int32(clamping: Int(max(-1.0, min(1.0, state.lx)) * 32767.0))
        var cly = Int32(clamping: Int(max(-1.0, min(1.0, state.ly)) * 32767.0))
        var crx = Int32(clamping: Int(max(-1.0, min(1.0, state.rx)) * 32767.0))
        var cry = Int32(clamping: Int(max(-1.0, min(1.0, state.ry)) * 32767.0))

        // Mario Party Jamboree only: D-pad and sticks all map to left stick so
        // Joy-Con works in both horizontal and vertical orientation for minigames and menus.
        let frontExe = NSWorkspace.shared.frontmostApplication?.executableURL?.lastPathComponent ?? ""
        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let isMarioParty = frontBundle.contains("Jamboree") || frontBundle.contains("0100965017338000") || frontExe == "dmhost" && {
            // Read the active game stamp to confirm it's Jamboree
            let stamp = (try? String(contentsOfFile: "\(NSHomeDirectory())/nxnative/dm/host/gen/game.stamp", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stamp == "0100965017338000"
        }()
        if isMarioParty {
            // D-pad → left stick (when left stick is centered)
            if clx == 0 && cly == 0 {
                if state.pressedButtons.contains("UP")    { cly += 32767 }
                if state.pressedButtons.contains("DOWN")  { cly -= 32767 }
                if state.pressedButtons.contains("LEFT")  { clx -= 32767 }
                if state.pressedButtons.contains("RIGHT") { clx += 32767 }
            }
            // Right stick → left stick (when left stick is centered), for horizontal Joy-Con
            if clx == 0 && cly == 0 && (crx != 0 || cry != 0) {
                clx = crx; cly = cry
            }
        }

        var pkt = NxPadShared(
            timestamp: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW),
            buttons: btns,
            lx: clx,
            ly: cly,
            rx: crx,
            ry: cry
        )
        _ = withUnsafeBytes(of: &pkt) { ptr in
            pwrite(padFds[p], ptr.baseAddress, ptr.count, 0)
        }
    }

    public static func clear(player: Int = 0) {
        let p = max(0, min(7, player))
        if padFds[p] < 0 {
            let path = "/tmp/nx_pad_p\(p + 1).dat"
            padFds[p] = open(path, O_RDWR | O_CREAT, 0o666)
        }
        guard padFds[p] >= 0 else { return }
        var pkt = NxPadShared(
            timestamp: 0,
            buttons: 0,
            lx: 0,
            ly: 0,
            rx: 0,
            ry: 0
        )
        _ = withUnsafeBytes(of: &pkt) { ptr in
            pwrite(padFds[p], ptr.baseAddress, ptr.count, 0)
        }
    }
}

// MARK: - UDP Server (Port 8765)

public final class UDPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.nxnative.udpserver", qos: .userInteractive)
    public var onPacketReceived: ((JoyConState, String) -> Void)?
    public var onHeartbeatReceived: ((String) -> Void)?
    public var onDiscovered: ((String) -> Void)?
    public var getPairingInfo: (() -> (ip: String, port: UInt16, pin: String))?

    public init(port: UInt16 = 8765) {
        if let saved = UserDefaults.standard.dictionary(forKey: "NXRemoteClientPlayerMap") as? [String: Int] {
            clientPlayerMap = saved
        }
        start(port: port)
    }

    private func savePlayerMap() {
        UserDefaults.standard.set(clientPlayerMap, forKey: "NXRemoteClientPlayerMap")
    }

    public func start(port: UInt16) {
        stop()
        do {
            let params = NWParameters.udp
            params.allowFastOpen = true
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("UDP Server error: \(error)")
        }
    }

    private var activeConnections: [String: NWConnection] = [:]
    private var clientPlayerMap: [String: Int] = [:]
    private var clientLastSeen: [String: Date] = [:]
    public var onClientListChanged: (([String: Int]) -> Void)?
    public var onResolvePlayerForName: ((String) -> Int?)?

    private func extractHost(from endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            let s = "\(host)"
            return s.components(separatedBy: "%").first ?? s
        default:
            return "Android"
        }
    }

    public func setPlayer(for address: String, to player: Int) {
        let p = max(0, min(7, player))
        if let prevP = clientPlayerMap[address], prevP != p {
            NxPadShared.clear(player: prevP)
            NxMotionShared.clear(player: prevP)
        }
        // Reassign any conflicting client to avoid two devices sharing one player
        for (otherAddr, otherP) in clientPlayerMap where otherAddr != address && otherP == p {
            let used = Set(clientPlayerMap.values).union([p])
            let fallback = (0..<8).first(where: { !used.contains($0) }) ?? ((p + 1) % 8)
            clientPlayerMap[otherAddr] = fallback
            if let conn = activeConnections[otherAddr] {
                sendPlayerAssignment(to: conn, player: fallback)
            }
        }
        clientPlayerMap[address] = p
        savePlayerMap()
        if let conn = activeConnections[address] {
            sendPlayerAssignment(to: conn, player: p)
        }
        onClientListChanged?(clientPlayerMap)
    }

    public func sendPlayerAssignment(to connection: NWConnection, player: Int) {
        let msg: [String: Any] = [
            "type": "assign_player",
            "player": player
        ]
        if let data = try? JSONSerialization.data(withJSONObject: msg) {
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    public func broadcastPacket(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        for (_, conn) in activeConnections {
            conn.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self = self else { return }

            let clientHost = self.extractHost(from: connection.endpoint)
            let now = Date()
            let isNewConnection = (self.activeConnections[clientHost] == nil)
            self.clientLastSeen[clientHost] = now
            self.activeConnections[clientHost] = connection

            // Purge inactive connections after 15s of silence AND release their player slots so dead IPs never block active players
            let stale = self.clientLastSeen.filter { now.timeIntervalSince($0.value) > 15.0 }.map { $0.key }
            if !stale.isEmpty {
                for s in stale {
                    if let oldP = self.clientPlayerMap.removeValue(forKey: s) {
                        NxPadShared.clear(player: oldP)
                        NxMotionShared.clear(player: oldP)
                    }
                    self.clientLastSeen.removeValue(forKey: s)
                    self.activeConnections.removeValue(forKey: s)
                }
                self.savePlayerMap()
                self.onClientListChanged?(self.clientPlayerMap)
            }

            // Only register a UDP client if it explicitly matches a configured controller name
            if let data = content, !data.isEmpty,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let devName = json["name"] as? String, !devName.isEmpty,
               let mappedP = self.onResolvePlayerForName?(devName) {
                if self.clientPlayerMap[clientHost] != mappedP {
                    self.setPlayer(for: clientHost, to: mappedP)
                }
                if isNewConnection {
                    self.sendPlayerAssignment(to: connection, player: mappedP)
                }
            }

            if let data = content, !data.isEmpty {

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String {
                    // If the phone reports its device name and that name is explicitly assigned to a player in NX Controles, honor it
                    if let devName = json["name"] as? String, !devName.isEmpty,
                       let mappedP = self.onResolvePlayerForName?(devName),
                       self.clientPlayerMap[clientHost] != mappedP {
                        self.setPlayer(for: clientHost, to: mappedP)
                    }
                    if type == "discover" {
                        let pin = json["pin"] as? String ?? ""
                        let info = self.getPairingInfo?() ?? (ip: "127.0.0.1", port: 8765, pin: "")

                        if pin == info.pin || info.pin.isEmpty {
                            let response: [String: Any] = [
                                "type": "discover_ack",
                                "ip": info.ip,
                                "port": Int(info.port),
                                "status": "ok"
                            ]
                            if let respData = try? JSONSerialization.data(withJSONObject: response) {
                                connection.send(content: respData, completion: .contentProcessed({ _ in }))
                            }
                            self.sendPlayerAssignment(to: connection, player: self.clientPlayerMap[clientHost] ?? 0)
                            self.onDiscovered?(clientHost)
                        }
                    } else if type == "set_player" {
                        if let reqP = json["player"] as? Int, reqP >= 0 && reqP < 8 {
                            self.setPlayer(for: clientHost, to: reqP)
                        }
                        self.onHeartbeatReceived?(clientHost)
                    } else if type == "heartbeat" || type == "connect" {
                        if let assignedP = self.clientPlayerMap[clientHost] {
                            self.sendPlayerAssignment(to: connection, player: assignedP)
                            self.onHeartbeatReceived?(clientHost)
                        }
                    } else if type == "disconnect" {
                        let player = self.clientPlayerMap.removeValue(forKey: clientHost) ?? 0
                        self.savePlayerMap()
                        self.clientLastSeen.removeValue(forKey: clientHost)
                        self.activeConnections.removeValue(forKey: clientHost)
                        NxPadShared.clear(player: player)
                        NxMotionShared.clear(player: player)
                        DSUServer.shared.updateState(JoyConState(player: player), slot: UInt8(player))
                        self.onClientListChanged?(self.clientPlayerMap)
                    }
                } else if let state = self.parsePacket(data, clientHost: clientHost) {
                    self.onPacketReceived?(state, clientHost)
                }
            }

            if error == nil {
                self.receiveNext(on: connection)
            }
        }
    }

    private func parsePacket(_ data: Data, clientHost: String) -> JoyConState? {
        struct Packet: Decodable {
            let mode: String?
            let buttons: [String]?
            let lx: Double?
            let ly: Double?
            let rx: Double?
            let ry: Double?
            let ax: Double?
            let ay: Double?
            let az: Double?
            let gx: Double?
            let gy: Double?
            let gz: Double?
            let shake: Bool?
            let player: Int?
            let name: String?
        }

        guard let packet = try? JSONDecoder().decode(Packet.self, from: data) else { return nil }
        // Ignore anonymous/phantom UDP packets that do not match a configured controller name
        guard let devName = packet.name, !devName.isEmpty,
              let mappedP = onResolvePlayerForName?(devName) else {
            return nil
        }
        if clientPlayerMap[clientHost] != mappedP {
            setPlayer(for: clientHost, to: mappedP)
        }
        var state = JoyConState()
        let assignedPlayer = mappedP
        state.player = assignedPlayer
        state.mode = packet.mode ?? "grip"
        state.pressedButtons = Set(packet.buttons ?? [])
        state.lx = max(-1.0, min(1.0, packet.lx ?? 0.0))
        state.ly = max(-1.0, min(1.0, packet.ly ?? 0.0))
        state.rx = max(-1.0, min(1.0, packet.rx ?? 0.0))
        state.ry = max(-1.0, min(1.0, packet.ry ?? 0.0))
        state.ax = packet.ax ?? 0.0
        state.ay = packet.ay ?? 0.0
        state.az = packet.az ?? 0.0
        state.gx = packet.gx ?? 0.0
        state.gy = packet.gy ?? 0.0
        state.gz = packet.gz ?? 0.0
        state.isShaking = packet.shake ?? packet.buttons?.contains("SHAKE") ?? false
        return state
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    deinit {
        stop()
    }
}

// MARK: - Unified Remote Store (Built into NX Controles)

@MainActor
public final class RemoteStore: ObservableObject {
    public static let sidebarID = "__nx_remote__"

    @Published public var state: JoyConState = JoyConState()
    @Published public var states: [Int: JoyConState] = [
        0: JoyConState(), 1: JoyConState(), 2: JoyConState(), 3: JoyConState(),
        4: JoyConState(), 5: JoyConState(), 6: JoyConState(), 7: JoyConState()
    ]
    @Published public var isConnected: Bool = false
    @Published public var clientAddress: String = ""
    @Published public var connectedClients: [String: Int] = [:]
    @Published public var localIP: String = "127.0.0.1" {
        didSet { updateQRCode() }
    }
    @Published public var bluetoothMAC: String = "9C:58:84:79:B6:BF" {
        didSet { updateQRCode() }
    }
    @Published public var port: UInt16 = 8765
    @Published public var pairingCode: String = String(format: "%04d", Int.random(in: 1000...9999)) {
        didSet { updateQRCode() }
    }
    @Published public var qrImage: NSImage?
    @Published public var forwardToGame: Bool = true // Automatically forward Wi-Fi controller buttons to active games
    @Published public var pps: Int = 0

    let injector = KeyInjector()
    private let server = UDPServer(port: 8765)
    private var packetCounter: Int = 0
    private var timer: Timer?
    private var knownClients: Set<String> = []

    var onRemotePadInput: ((_ player: Int, _ inputs: Set<PadInput>, _ ls: CGPoint, _ rs: CGPoint) -> Void)?
    var onQRClientConnected: ((String) -> Void)?
    public var onResolvePlayerForName: ((String) -> Int?)? {
        get { server.onResolvePlayerForName }
        set { server.onResolvePlayerForName = newValue }
    }

    public init() {
        self.localIP = Self.detectLocalIP()
        fetchBluetoothMAC()
        setupServerBridge()
        startPpsTimer()
        updateQRCode()
    }

    private func setupServerBridge() {
        server.getPairingInfo = { [weak self] in
            guard let self = self else { return ("127.0.0.1", 8765, "") }
            return (self.localIP, self.port, self.pairingCode)
        }

        server.onDiscovered = { [weak self] clientAddr in
            Task { @MainActor in
                self?.recordPacket(from: clientAddr)
            }
        }

        server.onHeartbeatReceived = { [weak self] clientAddr in
            Task { @MainActor in
                self?.recordPacket(from: clientAddr)
            }
        }

        server.onClientListChanged = { [weak self] map in
            Task { @MainActor in
                self?.connectedClients = map
            }
        }

        var lastUIUpdateTime: [Int: Double] = [:]
        var lastButtons: [Int: Set<String>] = [:]

        server.onPacketReceived = { [weak self] state, clientAddr in
            // Do not write NxPadShared or NxMotionShared from Wi-Fi UDP packets:
            // All controllers connect via Bluetooth HID, which already provides buttons, sticks, and 6-axis motion per player without phantom duplicates.
            DSUServer.shared.updateState(state, slot: UInt8(state.player))

            let now = CACurrentMediaTime()
            let p = state.player
            let prevBtns = lastButtons[p] ?? []
            let buttonsChanged = (prevBtns != state.pressedButtons)
            let timeSinceLastUI = now - (lastUIUpdateTime[p] ?? 0)

            // Throttle UI update: only dispatch to MainActor if button state changed or at ~30 FPS (every 33ms)
            guard buttonsChanged || timeSinceLastUI >= 0.033 else { return }
            lastUIUpdateTime[p] = now
            lastButtons[p] = state.pressedButtons

            Task { @MainActor in
                guard let self = self else { return }
                self.states[state.player] = state
                if state.player == 0 {
                    self.state = state
                }
                if self.connectedClients[clientAddr] != state.player {
                    self.connectedClients[clientAddr] = state.player
                }
                self.recordPacket(from: clientAddr)

                let mapped = Self.mapToPadInputs(state)
                self.onRemotePadInput?(
                    state.player,
                    mapped,
                    CGPoint(x: state.lx, y: state.ly),
                    CGPoint(x: state.rx, y: state.ry)
                )
            }
        }
    }

    private static func mapToPadInputs(_ s: JoyConState) -> Set<PadInput> {
        var now = Set<PadInput>()
        let b = s.pressedButtons
        if b.contains("A") { now.insert(.A) }
        if b.contains("B") { now.insert(.B) }
        if b.contains("X") { now.insert(.X) }
        if b.contains("Y") { now.insert(.Y) }
        if b.contains("L") || b.contains("SL") { now.insert(.LB) }
        if b.contains("R") || b.contains("SR") { now.insert(.RB) }
        if b.contains("ZL") { now.insert(.LT) }
        if b.contains("ZR") { now.insert(.RT) }
        if b.contains("MINUS") || b.contains("CAPTURE") { now.insert(.VIEW) }
        if b.contains("PLUS") || b.contains("HOME") { now.insert(.MENU) }
        if b.contains("LS") { now.insert(.LS) }
        if b.contains("RS") { now.insert(.RS) }
        if b.contains("UP") { now.insert(.DUP) }
        if b.contains("DOWN") { now.insert(.DDOWN) }
        if b.contains("LEFT") { now.insert(.DLEFT) }
        if b.contains("RIGHT") { now.insert(.DRIGHT) }
        var effLX = s.lx, effLY = s.ly
        var effRX = s.rx, effRY = s.ry
        if effLX == 0 && effLY == 0 {
            if effRX != 0 || effRY != 0 {
                effLX = effRX; effLY = effRY
            } else {
                if b.contains("UP") { effLY += 1.0 }
                if b.contains("DOWN") { effLY -= 1.0 }
                if b.contains("LEFT") { effLX -= 1.0 }
                if b.contains("RIGHT") { effLX += 1.0 }
            }
        } else if effRX == 0 && effRY == 0 {
            effRX = effLX; effRY = effLY
        }

        if effLY > 0.60 { now.insert(.LUP) }
        if effLY < -0.60 { now.insert(.LDOWN) }
        if effLX < -0.60 { now.insert(.LLEFT) }
        if effLX > 0.60 { now.insert(.LRIGHT) }
        if effRY > 0.60 { now.insert(.RUP) }
        if effRY < -0.60 { now.insert(.RDOWN) }
        if effRX < -0.60 { now.insert(.RLEFT) }
        if effRX > 0.60 { now.insert(.RRIGHT) }
        return now
    }

    private func fetchBluetoothMAC() {
        if let controller = IOBluetoothHostController.default(),
           let mac = controller.addressAsString(), !mac.isEmpty {
            let formatted = mac.replacingOccurrences(of: "-", with: ":").uppercased()
            self.bluetoothMAC = formatted
        }
    }

    public func sendRemapConfig(player: Int, buttonMap: [String: String], swapStickDpad: Bool) {
        let payload: [String: Any] = [
            "type": "remap",
            "player": player,
            "mapping": buttonMap,
            "swapStickDpad": swapStickDpad
        ]
        server.broadcastPacket(payload)
    }

    public func assignPlayer(for address: String, to player: Int) {
        let p = max(0, min(7, player))
        connectedClients[address] = p
        server.setPlayer(for: address, to: p)
    }

    public func refreshNetworkInfo() {
        self.localIP = Self.detectLocalIP()
        fetchBluetoothMAC()
        updateQRCode()
    }

    public func regenerateCode() {
        pairingCode = String(format: "%04d", Int.random(in: 1000...9999))
    }

    public func updateQRCode() {
        let payload = "nxremote://pair?bt=\(bluetoothMAC)&ip=\(localIP):\(port)&pin=\(pairingCode)"
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(payload.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        self.qrImage = img
    }

    private func startPpsTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.pps = self.packetCounter
                self.packetCounter = 0
                if Date().timeIntervalSince(self.state.lastPacketDate) > 3.5 && self.isConnected {
                    self.isConnected = false
                    self.clientAddress = ""
                    self.state.pressedButtons.removeAll()
                    self.state.lx = 0
                    self.state.ly = 0
                    self.state.rx = 0
                    self.state.ry = 0
                }
            }
        }
    }

    public func recordPacket(from address: String) {
        let isNewClient = !knownClients.contains(address)
        if isNewClient {
            knownClients.insert(address)
        }
        packetCounter += 1
        isConnected = true
        clientAddress = address
        state.lastPacketDate = Date()
        if isNewClient {
            onQRClientConnected?(address)
        }
    }

    public static func detectLocalIP() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            let name = String(cString: ptr.pointee.ifa_name)

            if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
               addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if name == "en0" || name == "en1" {
                        return ip
                    } else if address == "127.0.0.1" {
                        address = ip
                    }
                }
            }
        }
        return address
    }
}

// MARK: - Inline Expandable NX Remote Pairing Drawer (Used inside any game's controller view)

struct NXRemoteExpandableBanner: View {
    @ObservedObject var remote: RemoteStore
    @EnvironmentObject var store: Store
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.cyan)
                                .fixedSize()
                            Text("Escanea el QR con tu móvil para sincronizarlo con el Jugador \(store.player + 1) (J\(store.player + 1))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(remote.isConnected || !store.connectedPads.isEmpty ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(statusSummary)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.white.opacity(0.08), in: Capsule())

                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                isExpanded = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Ocultar QR")
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }

                    NXRemotePairingCardView(remote: remote, compact: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.20, alpha: 1)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.cyan.opacity(0.40), lineWidth: 1.5)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var statusSummary: String {
        if remote.isConnected {
            return "Móvil activo (\(remote.pps) Hz)"
        }
        if !store.connectedPads.isEmpty {
            return "\(store.connectedPads.count) mando(s) por Bluetooth"
        }
        return "Esperando escaneo QR o PIN…"
    }
}

// MARK: - Reusable Pairing Card (QR + 4-Digit PIN)

struct NXRemotePairingCardView: View {
    @ObservedObject var remote: RemoteStore
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 22) {
            // Left: QR Code for instant Bluetooth + Wi-Fi pairing
            HStack(spacing: 16) {
                if let qr = remote.qrImage {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 92 : 116, height: compact ? 92 : 116)
                        .padding(6)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("1. ESCANEA EL CÓDIGO QR")
                            .font(.system(size: 11.5, weight: .heavy))
                            .foregroundStyle(.cyan)
                        Text("RECOMENDADO")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.2), in: Capsule())
                            .foregroundStyle(.cyan)
                    }

                    Text("Abre la app NXJoyCon en tu teléfono, toca el menú superior (⚙️) → «Escanear Código QR». Enlaza el mando por Bluetooth y Wi-Fi automáticamente.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        Label("BT: \(remote.bluetoothMAC)", systemImage: "antenna.radiowaves.left.and.right")
                        Label("IP: \(remote.localIP):\(remote.port)", systemImage: "wifi")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: compact ? 84 : 104)
                .overlay(Color.white.opacity(0.12))

            // Right: 4-Digit PIN
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("2. O CONECTA CON PIN")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 4)
                    Button {
                        remote.refreshNetworkInfo()
                        remote.regenerateCode()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Nuevo PIN")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.cyan)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Generar un nuevo código PIN de 4 dígitos")
                }

                HStack(spacing: 8) {
                    ForEach(Array(remote.pairingCode.enumerated()), id: \.offset) { _, char in
                        Text(String(char))
                            .font(.system(size: compact ? 22 : 26, weight: .black, design: .monospaced))
                            .foregroundStyle(.cyan)
                            .frame(width: compact ? 36 : 42, height: compact ? 42 : 48)
                            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.cyan.opacity(0.45), lineWidth: 1.5)
                            )
                    }
                }

                Text("Escribe estos 4 dígitos en el menú de la app móvil.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .frame(width: compact ? 195 : 220)
        }
    }
}

// MARK: - Full NX Remote View (When selected in Sidebar)

struct NXRemoteDashboardView: View {
    @ObservedObject var remote: RemoteStore
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .cyan.opacity(0.3), radius: 6, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("NX Remote — Mandos Móviles")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(remote.isConnected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(remote.isConnected ? "Móvil transmitiendo (\(remote.pps) Hz)" : "Servidor activo esperando conexión")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background((remote.isConnected ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                            .foregroundStyle(remote.isConnected ? .green : .orange)

                            if !store.connectedPads.isEmpty {
                                Text("\(store.connectedPads.count) mando(s) Bluetooth detectados")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Color.cyan.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        remote.refreshNetworkInfo()
                        store.refreshControllers()
                    } label: {
                        Label("Actualizar Red y Bluetooth", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                }

                // Pairing Card (Dark Styled)
                VStack(alignment: .leading, spacing: 12) {
                    NXRemotePairingCardView(remote: remote, compact: false)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(nsColor: NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.16, alpha: 1)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.cyan.opacity(0.30), lineWidth: 1)
                )

                // Connected Phones & Bluetooth Gamepads List + Live Joy-Con Visualizer
                HStack(alignment: .top, spacing: 18) {
                    // Left: Live Joy-Con Telemetry Preview
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Vista previa en vivo del móvil", systemImage: "gamecontroller.fill")
                                .font(.headline)
                            Spacer()
                            Text("Modo: \(remote.state.mode.uppercased())")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }

                        liveJoyConPreview

                        HStack {
                            Text("Botones pulsados:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if remote.state.pressedButtons.isEmpty && store.pressedPadInputs.isEmpty {
                                Text("Ninguno")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(Array(remote.state.pressedButtons).sorted(), id: \.self) { btn in
                                    Text(btn)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.cyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(.cyan)
                                }
                                ForEach(Array(store.pressedPadInputs).map(\.xboxLabel).sorted(), id: \.self) { lbl in
                                    Text(lbl)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(.green)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))

                    // Right: Multi-Controller Status & Options
                    VStack(alignment: .leading, spacing: 14) {
                        // Section: Mobile Phones Connected (Auto-assigned & Reassignable from Mac)
                        Label("Móviles Conectados (\(remote.connectedClients.count))", systemImage: "iphone.radiowaves.left.and.right")
                            .font(.headline)

                        if remote.connectedClients.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No hay móviles transmitiendo en este momento.")
                                    .font(.callout.weight(.medium))
                                Text("Abre la app en cada móvil; el Mac le asignará automáticamente Jugador 1, 2, 3... y sus LEDs se iluminarán al instante.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(remote.connectedClients.keys.sorted()), id: \.self) { addr in
                                    let curP = remote.connectedClients[addr] ?? 0
                                    HStack(spacing: 10) {
                                        Image(systemName: "iphone.gen3")
                                            .foregroundStyle(.cyan)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(addr)
                                                .font(.callout.weight(.semibold).monospaced())
                                            Text("Asignación automática desde este Mac")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Picker("Jugador", selection: Binding(
                                            get: { curP },
                                            set: { newP in remote.assignPlayer(for: addr, to: newP) }
                                        )) {
                                            ForEach(0..<8, id: \.self) { p in
                                                Text("Jugador \(p + 1) (J\(p + 1))").tag(p)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(width: 140)
                                    }
                                    .padding(10)
                                    .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }

                        Divider()

                        Label("Mandos Bluetooth (\(store.connectedPads.count))", systemImage: "person.2.wave.2.fill")
                            .font(.headline)

                        if store.connectedPads.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Aún no hay mandos Bluetooth activos.")
                                    .font(.callout.weight(.medium))
                                Text("Escanea el código QR desde uno o varios teléfonos Android para que aparezcan aquí como Jugador 1, Jugador 2, etc.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(0..<store.connectedPads.count, id: \.self) { idx in
                                    HStack(spacing: 10) {
                                        Image(systemName: "gamecontroller.fill")
                                            .foregroundStyle(.green)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("Mando #\(idx + 1): \(store.connectedPads[idx])")
                                                .font(.callout.weight(.semibold))
                                            Text("Listo para asignar a cualquier jugador (J1–J8)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("J\(idx + 1)")
                                            .font(.caption.monospaced().bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.green.opacity(0.18), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                    .padding(10)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }

                        Divider()

                        Toggle("Emular pulsaciones de teclado por Wi-Fi (solo si no usas Bluetooth)", isOn: $remote.forwardToGame)
                            .toggleStyle(.switch)
                            .font(.callout)

                        Text("Nota: Al conectar por Bluetooth con el QR, nxnative detecta cada teléfono nativamente como un mando independiente con giroscopio y soporte multijugador.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(width: 340)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("NX Remote — Conectar Móvil")
    }

    private var liveJoyConPreview: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                shoulderPill("ZL", active: remote.state.pressedButtons.contains("ZL") || store.pressedPadInputs.contains(.LT))
                shoulderPill("L / SL", active: remote.state.pressedButtons.contains("L") || remote.state.pressedButtons.contains("SL") || store.pressedPadInputs.contains(.LB))
                Spacer()
                shoulderPill("R / SR", active: remote.state.pressedButtons.contains("R") || remote.state.pressedButtons.contains("SR") || store.pressedPadInputs.contains(.RB))
                shoulderPill("ZR", active: remote.state.pressedButtons.contains("ZR") || store.pressedPadInputs.contains(.RT))
            }

            HStack(spacing: 18) {
                // Left Joy-Con
                VStack(spacing: 12) {
                    stickPreview(
                        x: remote.isConnected ? remote.state.lx : Double(store.leftStick.x),
                        y: remote.isConnected ? remote.state.ly : Double(store.leftStick.y),
                        label: "L"
                    )
                    HStack(spacing: 12) {
                        miniCircle("◀", active: remote.state.pressedButtons.contains("LEFT") || store.pressedPadInputs.contains(.DLEFT))
                        VStack(spacing: 8) {
                            miniCircle("▲", active: remote.state.pressedButtons.contains("UP") || store.pressedPadInputs.contains(.DUP))
                            miniCircle("▼", active: remote.state.pressedButtons.contains("DOWN") || store.pressedPadInputs.contains(.DDOWN))
                        }
                        miniCircle("▶", active: remote.state.pressedButtons.contains("RIGHT") || store.pressedPadInputs.contains(.DRIGHT))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(colors: [Color.cyan.opacity(0.85), Color.blue.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                )

                // Right Joy-Con
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        miniCircle("Y", active: remote.state.pressedButtons.contains("Y") || store.pressedPadInputs.contains(.X))
                        VStack(spacing: 8) {
                            miniCircle("X", active: remote.state.pressedButtons.contains("X") || store.pressedPadInputs.contains(.Y))
                            miniCircle("B", active: remote.state.pressedButtons.contains("B") || store.pressedPadInputs.contains(.A))
                        }
                        miniCircle("A", active: remote.state.pressedButtons.contains("A") || store.pressedPadInputs.contains(.B))
                    }
                    stickPreview(
                        x: remote.isConnected ? remote.state.rx : Double(store.rightStick.x),
                        y: remote.isConnected ? remote.state.ry : Double(store.rightStick.y),
                        label: "R"
                    )
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(colors: [Color.red.opacity(0.85), Color.pink.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                )
            }
        }
    }

    private func shoulderPill(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(active ? Color.green : Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(active ? .black : .primary)
    }

    private func miniCircle(_ title: String, active: Bool) -> some View {
        Circle()
            .fill(active ? Color.green : Color.black.opacity(0.45))
            .frame(width: 24, height: 24)
            .overlay(
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(active ? .black : .white)
            )
    }

    private func stickPreview(x: Double, y: Double, label: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: 60, height: 60)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .offset(x: CGFloat(x * 16), y: CGFloat(-y * 16))
                .overlay(
                    Text(label)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.black)
                )
        }
    }
}

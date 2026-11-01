import Foundation
import Darwin

func dsuLog(_ msg: String) {
    // Disabled to prevent synchronous disk I/O in the fast path
}

/// Standard Cemuhook / DSU (DualShock UDP) protocol server.
/// Listens on 127.0.0.1:26760 to feed real-time motion and input telemetry to Astris / Ryujinx / Cemu.
public final class DSUServer {
    public static let shared = DSUServer()

    private var socketFd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.nxnative.dsuserver", qos: .userInteractive)

    private struct ClientSubscription {
        var addr: sockaddr_in
        var lastSeen: Date
    }

    private var activeClients: [String: ClientSubscription] = [:]
    private var currentStates: [UInt8: JoyConState] = [
        0: JoyConState()
    ]
    private var currentState: JoyConState {
        get { currentStates[0] ?? JoyConState() }
        set { currentStates[0] = newValue }
    }
    private var packetCounter: UInt32 = 0
    private var streamTimer: DispatchSourceTimer?
    private let serverId: UInt32 = 0x4E584453 // "NXDS"

    // Keyboard → DSU: direct thread-safe path bypassing @MainActor
    private var keyboardPressed: Set<UInt16> = []
    // keyMap[player][controlName] = [keyCodes]  (snapshot from Store, updated periodically)
    private var keyMapSnapshot: [[[UInt16]]] = []  // [player][ controlIndex ] = [keyCodes]
    private var controlNames: [String] = []

    /// Called from CGEvent tap callback on system thread — NOT main thread
    public func handleKeyEvent(code: UInt16, down: Bool) {
        dsuLog("[DSU-KEY] code=\(code) down=\(down)")
        queue.async {
            let changed: Bool
            if down {
                changed = self.keyboardPressed.insert(code).inserted
            } else {
                changed = self.keyboardPressed.remove(code) != nil
            }
            if changed {
                dsuLog("[DSU-KEY] changed! pressed=\(self.keyboardPressed)")
                self.rebuildKeyboardStates()
            }
        }
    }

    /// Set the keyboard mapping from Store (call from main thread whenever keymap changes)
    func setKeyMap(_ map: KeyMap) {
        let allControls = Control.allCases
        let names = allControls.map { $0.rawValue }
        var snapshot: [[[UInt16]]] = []
        for p in 0..<kPlayers {
            var playerData: [[UInt16]] = []
            for c in allControls {
                playerData.append(map.keys[p][c] ?? [])
            }
            snapshot.append(playerData)
        }
        let totalKeys = snapshot.flatMap { $0 }.flatMap { $0 }.count
        dsuLog("[DSU-KEY] setKeyMap: \(kPlayers) players, \(totalKeys) total key bindings")
        for p in 0..<min(kPlayers, 2) {
            let pkeys = snapshot[p].flatMap { $0 }
            dsuLog("[DSU-KEY]   Player \(p): \(pkeys.count) keys = \(pkeys)")
        }
        queue.async {
            self.controlNames = names
            self.keyMapSnapshot = snapshot
            self.rebuildKeyboardStates()
        }
    }

    private func rebuildKeyboardStates() {
        // dispatchPrecondition: on self.queue
        guard !keyMapSnapshot.isEmpty else { return }
        let allControls = Control.allCases
        var newStates: [UInt8: JoyConState] = [:]

        for p in 0..<min(keyMapSnapshot.count, 8) {
            let playerData = keyMapSnapshot[p]
            let hasAnyBinding = playerData.contains { !$0.isEmpty }
            // Only player 0 (always) or players with actual bindings
            guard p == 0 || hasAnyBinding else { continue }

            var buttons = Set<String>()
            var lx: Double = 0, ly: Double = 0, rx: Double = 0, ry: Double = 0
            var isShaking = false

            for (ci, control) in allControls.enumerated() {
                guard ci < playerData.count else { break }
                let keyCodes = playerData[ci]
                let isPressed = keyCodes.contains { keyboardPressed.contains($0) }
                guard isPressed else { continue }

                switch control {
                case .A: buttons.insert("A")
                case .B: buttons.insert("B")
                case .X: buttons.insert("X")
                case .Y: buttons.insert("Y")
                case .L: buttons.insert("L")
                case .R: buttons.insert("R")
                case .ZL: buttons.insert("ZL")
                case .ZR: buttons.insert("ZR")
                case .PLUS: buttons.insert("PLUS")
                case .MINUS: buttons.insert("MINUS")
                case .LS: buttons.insert("LS")
                case .RS: buttons.insert("RS")
                case .UP: buttons.insert("UP")
                case .DOWN: buttons.insert("DOWN")
                case .LEFT: buttons.insert("LEFT")
                case .RIGHT: buttons.insert("RIGHT")
                case .LUP: ly += 1.0
                case .LDOWN: ly -= 1.0
                case .LLEFT: lx -= 1.0
                case .LRIGHT: lx += 1.0
                case .RUP: ry += 1.0
                case .RDOWN: ry -= 1.0
                case .RLEFT: rx -= 1.0
                case .RRIGHT: rx += 1.0
                case .SHAKE: isShaking = true
                }
            }

            lx = max(-1.0, min(1.0, lx))
            ly = max(-1.0, min(1.0, ly))
            rx = max(-1.0, min(1.0, rx))
            ry = max(-1.0, min(1.0, ry))

            newStates[UInt8(p)] = JoyConState(
                player: p,
                pressedButtons: buttons,
                lx: lx, ly: ly, rx: rx, ry: ry,
                isShaking: isShaking
            )
            if p == 0 && (!buttons.isEmpty || lx != 0 || ly != 0) {
                dsuLog("[DSU] P0 buttons=\(buttons) LStick=(\(lx),\(ly)) clients=\(self.activeClients.count)")
            }
        }

        // Preserve external device states if active
        for (slot, st) in self.currentStates {
            if newStates[slot] == nil && (!st.pressedButtons.isEmpty || st.lx != 0 || st.ly != 0) {
                newStates[slot] = st
            }
        }
        if newStates[0] == nil {
            newStates[0] = JoyConState()
        }

        self.currentStates = newStates

        if !self.activeClients.isEmpty {
            self.sendControllerDataToAll()
        }
    }

    public init() {
        start()
    }

    public func start(port: UInt16 = 26760) {
        stop()

        socketFd = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFd >= 0 else {
            print("[DSU] Failed to create UDP socket: \(errno)")
            return
        }

        var reuse: Int32 = 1
        setsockopt(socketFd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = in_addr_t(0x7F000001).bigEndian // 127.0.0.1

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(socketFd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindRes != 0 {
            print("[DSU] Failed to bind port \(port): \(errno)")
            close(socketFd)
            socketFd = -1
            return
        }

        _ = fcntl(socketFd, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleIncomingPackets()
        }
        source.resume()
        self.readSource = source

        startStreamTimer()
        print("[DSU] Server listening on 127.0.0.1:\(port)")
    }

    public func stop() {
        streamTimer?.cancel()
        streamTimer = nil
        readSource?.cancel()
        readSource = nil
        if socketFd >= 0 {
            close(socketFd)
            socketFd = -1
        }
        activeClients.removeAll()
    }

    public func updateState(_ state: JoyConState, slot: UInt8 = 0) {
        queue.async {
            self.currentStates[slot] = state
            if !self.activeClients.isEmpty {
                self.sendControllerDataToAll()
            }
        }
    }

    // MARK: - Streaming Timer (60 Hz continuous feed for emulator motion filters)

    private func startStreamTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = Date()
            self.activeClients = self.activeClients.filter { now.timeIntervalSince($0.value.lastSeen) < 5.0 }
            if !self.activeClients.isEmpty {
                self.sendControllerDataToAll()
            }
        }
        timer.resume()
        self.streamTimer = timer
    }

    // MARK: - Incoming UDP Packets Dispatcher

    private func handleIncomingPackets() {
        var senderAddr = sockaddr_in()
        var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        var buffer = [UInt8](repeating: 0, count: 1024)

        while true {
            let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { sptr in
                sptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(socketFd, &buffer, buffer.count, 0, sa, &senderLen)
                }
            }

            guard bytesRead >= 16 else { break }

            let data = Data(buffer.prefix(bytesRead))
            let clientKey = "\(senderAddr.sin_addr.s_addr):\(senderAddr.sin_port)"
            activeClients[clientKey] = ClientSubscription(addr: senderAddr, lastSeen: Date())
            dsuLog("[DSU-IN] Packet \(bytesRead)B from \(clientKey)")
            processPacket(data: data, sender: senderAddr)
        }
    }

    private func processPacket(data: Data, sender: sockaddr_in) {
        // Read header magic
        guard data.count >= 20 else { return }
        // Bytes 0..3: magic (e.g. DDUC, DSUC, DSUS)
        // Bytes 16..19: message type (UInt32 LE)
        let msgType = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 16, as: UInt32.self)
        }
        dsuLog("[DSU] processPacket type=\(String(format: "0x%06X", msgType)) clients=\(activeClients.count)")

        switch msgType {
        case 0x100000:
            // Protocol Version Request
            var vPayload = Data()
            var v: UInt16 = 1001
            vPayload.append(Data(bytes: &v, count: 2))
            let resp = buildPacket(type: 0x100000, payload: vPayload)
            sendData(resp, to: sender)

        case 0x100001:
            // Controller Information Request
            var requestedSlots: [UInt8] = [0]
            if data.count >= 24 {
                let count = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 20, as: Int32.self) })
                let safeCount = max(0, min(count, 8))
                if safeCount > 0 && data.count >= 24 + safeCount {
                    requestedSlots = (0..<safeCount).map { data[24 + $0] }
                }
            }

            for slot in requestedSlots {
                var slotPayload = Data()
                slotPayload.append(slot) // Slot index
                let isSlotActive = (slot < 8 && currentStates[slot] != nil)
                if isSlotActive {
                    slotPayload.append(2) // 2 = Connected
                    slotPayload.append(2) // 2 = Full Gyro (Switch Joy-Con / Pro Controller)
                    slotPayload.append(2) // 2 = Bluetooth
                    slotPayload.append(contentsOf: [0x00, 0x90, 0xE6, 0x01, 0x02, slot]) // MAC
                    slotPayload.append(0xEF) // 0xEF = Charged battery
                    slotPayload.append(0)    // Reserved
                } else {
                    slotPayload.append(0) // 0 = Not connected
                    slotPayload.append(0)
                    slotPayload.append(0)
                    slotPayload.append(contentsOf: [0, 0, 0, 0, 0, 0])
                    slotPayload.append(0)
                    slotPayload.append(0)
                }
                let resp = buildPacket(type: 0x100001, payload: slotPayload)
                sendData(resp, to: sender)
            }

        case 0x100002:
            // Controller Data Request / Subscription
            sendControllerData(to: sender)

        default:
            break
        }
    }

    private func sendControllerDataToAll() {
        packetCounter = packetCounter &+ 1
        for (slot, st) in currentStates {
            let packet = buildControllerDataPacket(slot: slot, state: st, counter: packetCounter)
            for (_, client) in activeClients {
                sendData(packet, to: client.addr)
            }
        }
    }

    private func sendControllerData(to sender: sockaddr_in) {
        packetCounter = packetCounter &+ 1
        for (slot, st) in currentStates {
            let packet = buildControllerDataPacket(slot: slot, state: st, counter: packetCounter)
            sendData(packet, to: sender)
        }
    }

    private func sendData(_ data: Data, to recipient: sockaddr_in) {
        guard socketFd >= 0 else { return }
        var addr = recipient
        _ = data.withUnsafeBytes { ptr in
            withUnsafePointer(to: &addr) { aptr in
                aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(socketFd, ptr.baseAddress, ptr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - Packet Builder & CRC32

    private func buildPacket(type: UInt32, payload: Data) -> Data {
        var data = Data()
        // Magic: DSUS (Server to Client)
        data.append(contentsOf: [0x44, 0x53, 0x55, 0x53])
        // Version: 1001 LE
        var version: UInt16 = 1001
        data.append(Data(bytes: &version, count: 2))
        // Length: payload.count + 4
        var length: UInt16 = UInt16(payload.count + 4)
        data.append(Data(bytes: &length, count: 2))
        // CRC32 placeholder: 0
        var zeroCrc: UInt32 = 0
        data.append(Data(bytes: &zeroCrc, count: 4))
        // Server ID
        var sid = serverId
        data.append(Data(bytes: &sid, count: 4))
        // Message Type
        var msgType = type
        data.append(Data(bytes: &msgType, count: 4))
        // Payload
        data.append(payload)

        // Calculate CRC32 over the whole packet and insert at bytes 8..11
        var crc = Self.crc32(data)
        withUnsafeBytes(of: &crc) { ptr in
            data.replaceSubrange(8..<12, with: ptr)
        }
        return data
    }

    private func buildControllerDataPacket(slot: UInt8, state: JoyConState, counter: UInt32) -> Data {
        var p = Data()
        p.reserveCapacity(80)

        p.append(slot) // Offset 0: Slot (0)
        p.append(2)    // Offset 1: State (2 = connected)
        p.append(2)    // Offset 2: Device Model (2 = full gyro)
        p.append(2)    // Offset 3: Connection (2 = bluetooth)
        p.append(contentsOf: [0x00, 0x90, 0xE6, 0x01, 0x02, slot]) // Offsets 4..9: MAC
        p.append(0xEF) // Offset 10: Battery (0xEF = charged)
        p.append(1)    // Offset 11: Connected flag (1)

        // Offsets 12..15: Packet Counter (UInt32 LE)
        var c = counter
        p.append(Data(bytes: &c, count: 4))

        // Offsets 16..17: Digital Buttons Bitmask (Cemuhook DSU Protocol standard)
        // Byte 16 (Packet 1):
        //   bit 0 (0x01): D-Pad Right
        //   bit 1 (0x02): D-Pad Left
        //   bit 2 (0x04): D-Pad Down
        //   bit 3 (0x08): D-Pad Up
        //   bit 4 (0x10): Options / Plus / Start
        //   bit 5 (0x20): R3 (Right Stick Click)
        //   bit 6 (0x40): L3 (Left Stick Click)
        //   bit 7 (0x80): Share / Minus / Select
        var b1: UInt8 = 0
        let b = state.pressedButtons
        if b.contains("RIGHT") { b1 |= (1 << 0) }
        if b.contains("LEFT")  { b1 |= (1 << 1) }
        if b.contains("DOWN")  { b1 |= (1 << 2) }
        if b.contains("UP")    { b1 |= (1 << 3) }
        if b.contains("PLUS") || b.contains("HOME") { b1 |= (1 << 4) }
        if b.contains("RS")    { b1 |= (1 << 5) }
        if b.contains("LS")    { b1 |= (1 << 6) }
        if b.contains("MINUS") || b.contains("CAPTURE") { b1 |= (1 << 7) }
        p.append(b1) // Offset 16

        // Byte 17 (Packet 2):
        //   bit 0 (0x01): L2 / ZL (Trigger)
        //   bit 1 (0x02): R2 / ZR (Trigger)
        //   bit 2 (0x04): L1 / L (Shoulder)
        //   bit 3 (0x08): R1 / R (Shoulder)
        //   bit 4 (0x10): Cross / Gamepad A -> Switch A
        //   bit 5 (0x20): Circle / Gamepad B -> Switch B
        //   bit 6 (0x40): Triangle / Gamepad Y -> Switch Y
        //   bit 7 (0x80): Square / Gamepad X -> Switch X
        var b2: UInt8 = 0
        if b.contains("ZL") { b2 |= (1 << 0) }
        if b.contains("ZR") { b2 |= (1 << 1) }
        if b.contains("L") || b.contains("SL") { b2 |= (1 << 2) }
        if b.contains("R") || b.contains("SR") { b2 |= (1 << 3) }
        if b.contains("A") { b2 |= (1 << 4) }
        if b.contains("B") { b2 |= (1 << 5) }
        if b.contains("Y") { b2 |= (1 << 6) }
        if b.contains("X") { b2 |= (1 << 7) }
        p.append(b2) // Offset 17

        p.append(0) // Offset 18: PS Button (0)
        p.append(0) // Offset 19: Touch Button (0)

        // Offsets 20..23: Analog Sticks (0..255, 128 neutral)
        let lxByte = UInt8(max(0, min(255, Int((state.lx + 1.0) * 127.5))))
        let lyByte = UInt8(max(0, min(255, Int((state.ly + 1.0) * 127.5))))
        let rxByte = UInt8(max(0, min(255, Int((state.rx + 1.0) * 127.5))))
        let ryByte = UInt8(max(0, min(255, Int((state.ry + 1.0) * 127.5))))
        p.append(lxByte) // 20
        p.append(lyByte) // 21
        p.append(rxByte) // 22
        p.append(ryByte) // 23

        // Offsets 24..35: Analog Buttons (12 bytes)
        var analog = [UInt8](repeating: 0, count: 12)
        if b.contains("LEFT")  { analog[0] = 255 }
        if b.contains("DOWN")  { analog[1] = 255 }
        if b.contains("RIGHT") { analog[2] = 255 }
        if b.contains("UP")    { analog[3] = 255 }
        if b.contains("X")     { analog[4] = 255 } // Square (Gamepad X)
        if b.contains("A")     { analog[5] = 255 } // Cross (Gamepad A)
        if b.contains("B")     { analog[6] = 255 } // Circle (Gamepad B)
        if b.contains("Y")     { analog[7] = 255 } // Triangle (Gamepad Y)
        if b.contains("R") || b.contains("SR") { analog[8] = 255 }
        if b.contains("L") || b.contains("SL") { analog[9] = 255 }
        if b.contains("ZR")    { analog[10] = 255 }
        if b.contains("ZL")    { analog[11] = 255 }
        p.append(contentsOf: analog)

        // Offsets 36..47: Touchpad Data (12 bytes zeroes)
        p.append(contentsOf: [UInt8](repeating: 0, count: 12))

        // Offsets 48..55: Motion Timestamp in microseconds (UInt64 LE)
        var ts = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        p.append(Data(bytes: &ts, count: 8))

        // Offsets 56..67: Accelerometer (Float32 in G's)
        var ax = Float32(state.ax / 9.80665)
        var ay = Float32(state.ay / 9.80665)
        var az = Float32(state.az / 9.80665)

        // If mobile app is reporting a shake gesture (Mario Party minigames, cooking, dice, etc.)
        if state.isShaking {
            let shakeWave: Float32 = (counter % 4 < 2) ? 3.8 : -3.8
            ay += shakeWave
        }

        p.append(Data(bytes: &ax, count: 4)) // 56..59: Accel X
        p.append(Data(bytes: &ay, count: 4)) // 60..63: Accel Y
        p.append(Data(bytes: &az, count: 4)) // 64..67: Accel Z

        // Offsets 68..79: Gyroscope (Float32 in deg/s)
        var pitch = Float32(state.gx * (180.0 / .pi))
        var yaw   = Float32(state.gy * (180.0 / .pi))
        var roll  = Float32(state.gz * (180.0 / .pi))

        p.append(Data(bytes: &pitch, count: 4)) // 68..71: Gyro Pitch
        p.append(Data(bytes: &yaw, count: 4))   // 72..75: Gyro Yaw
        p.append(Data(bytes: &roll, count: 4))  // 76..79: Gyro Roll

        return buildPacket(type: 0x100002, payload: p)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

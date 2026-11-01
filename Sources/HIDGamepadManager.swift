import Foundation
import IOKit.hid
import CoreGraphics

final class RawReportContext {
    let device: IOHIDDevice
    let devIndex: Int
    var buffer: [UInt8] = [UInt8](repeating: 0, count: 64)
    weak var manager: HIDGamepadManager?

    init(device: IOHIDDevice, devIndex: Int, manager: HIDGamepadManager) {
        self.device = device
        self.devIndex = devIndex
        self.manager = manager
    }
}

final class HIDGamepadManager {
    struct DeviceState {
        let device: IOHIDDevice
        let name: String
        var buttons: Set<Int> = []
        var hat: Int = 0
        var lx: Double = 0
        var ly: Double = 0
        var rx: Double = 0
        var ry: Double = 0
        var lt: Double = 0
        var rt: Double = 0
    }

    private var manager: IOHIDManager?
    private(set) var devices: [DeviceState] = []
    private var reportContexts: [IOHIDDevice: RawReportContext] = [:]
    
    var onDeviceListChanged: (([String]) -> Void)?
    var onInput: ((_ deviceIndex: Int, _ inputs: Set<PadInput>, _ leftStick: CGPoint, _ rightStick: CGPoint, _ leftTrigger: Double, _ rightTrigger: Double) -> Void)?
    var onGetPlayerForDevice: ((Int) -> Int?)?

    init() {
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = mgr

        let criteria: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop), kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Joystick)],
            [kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop), kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_GamePad)],
            [kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop), kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_MultiAxisController)]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, criteria as CFArray)

        let matchingCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let this = Unmanaged<HIDGamepadManager>.fromOpaque(context).takeUnretainedValue()
            this.deviceAttached(device)
        }

        let removalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let this = Unmanaged<HIDGamepadManager>.fromOpaque(context).takeUnretainedValue()
            this.deviceDetached(device)
        }

        let valueCallback: IOHIDValueCallback = { context, result, sender, value in
            guard let context = context else { return }
            let this = Unmanaged<HIDGamepadManager>.fromOpaque(context).takeUnretainedValue()
            this.valueReceived(value)
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, matchingCallback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, removalCallback, ctx)
        IOHIDManagerRegisterInputValueCallback(mgr, valueCallback, ctx)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func stop() {
        if let mgr = manager {
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
    }

    private func deviceAttached(_ device: IOHIDDevice) {
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Mando HID"
        if !devices.contains(where: { $0.device == device }) {
            let devIdx = devices.count
            devices.append(DeviceState(device: device, name: name))

            let ctxObj = RawReportContext(device: device, devIndex: devIdx, manager: self)
            reportContexts[device] = ctxObj

            let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
                guard result == kIOReturnSuccess, reportLength >= 20, let context = context else { return }
                let ctx = Unmanaged<RawReportContext>.fromOpaque(context).takeUnretainedValue()
                ctx.manager?.rawReportReceived(device: ctx.device, reportID: reportID, report: report, length: reportLength)
            }

            let uCtx = Unmanaged.passUnretained(ctxObj).toOpaque()
            ctxObj.buffer.withUnsafeMutableBytes { ptr in
                if let base = ptr.bindMemory(to: UInt8.self).baseAddress {
                    IOHIDDeviceRegisterInputReportCallback(device, base, 64, reportCallback, uCtx)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onDeviceListChanged?(self.devices.map { $0.name })
            }
        }
    }

    private func deviceDetached(_ device: IOHIDDevice) {
        if let ctxObj = reportContexts.removeValue(forKey: device) {
            ctxObj.buffer.withUnsafeMutableBytes { ptr in
                if let base = ptr.bindMemory(to: UInt8.self).baseAddress {
                    IOHIDDeviceRegisterInputReportCallback(device, base, 64, nil, nil)
                }
            }
        }
        if let idx = devices.firstIndex(where: { $0.device == device }) {
            devices.remove(at: idx)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onDeviceListChanged?(self.devices.map { $0.name })
            }
        }
    }

    func rawReportReceived(device: IOHIDDevice, reportID: UInt32, report: UnsafePointer<UInt8>, length: CFIndex) {
        guard length >= 20 else { return }
        guard let devIndex = devices.firstIndex(where: { $0.device == device }) else { return }
        guard let playerIdx = onGetPlayerForDevice?(devIndex) else { return }

        // Report format from Android NXJoyCon over Bluetooth HID:
        // If macOS prepended the Report ID (1), the payload starts at offset 1.
        let offset: Int
        if length >= 21 && report[0] == 1 {
            offset = 1
        } else if length == 20 {
            offset = 0
        } else {
            offset = (report[0] == 1) ? 1 : 0
        }
        guard length >= offset + 20 else { return }

        // Bytes offset + 0..6: sticks, buttons, dpad
        // Bytes offset + 7..12: ax, ay, az (short little endian / 100.0 m/s^2)
        let b7 = UInt16(report[offset + 7]), b8 = UInt16(report[offset + 8])
        let b9 = UInt16(report[offset + 9]), b10 = UInt16(report[offset + 10])
        let b11 = UInt16(report[offset + 11]), b12 = UInt16(report[offset + 12])
        let rawAx = Int16(bitPattern: b7 | (b8 << 8))
        let rawAy = Int16(bitPattern: b9 | (b10 << 8))
        let rawAz = Int16(bitPattern: b11 | (b12 << 8))

        // Bytes offset + 13..18: gx, gy, gz (short little endian / 1000.0 rad/s)
        let b13 = UInt16(report[offset + 13]), b14 = UInt16(report[offset + 14])
        let b15 = UInt16(report[offset + 15]), b16 = UInt16(report[offset + 16])
        let b17 = UInt16(report[offset + 17]), b18 = UInt16(report[offset + 18])
        let rawGx = Int16(bitPattern: b13 | (b14 << 8))
        let rawGy = Int16(bitPattern: b15 | (b16 << 8))
        let rawGz = Int16(bitPattern: b17 | (b18 << 8))

        let isShaking = report[offset + 19] != 0

        var state = JoyConState()
        state.player = playerIdx
        state.ax = Double(rawAx) / 100.0
        state.ay = Double(rawAy) / 100.0
        state.az = Double(rawAz) / 100.0
        state.gx = Double(rawGx) / 1000.0
        state.gy = Double(rawGy) / 1000.0
        state.gz = Double(rawGz) / 1000.0
        state.isShaking = isShaking

        NxMotionShared.writeShared(state, player: playerIdx)
    }

    private func valueReceived(_ val: IOHIDValue) {
        let elem = IOHIDValueGetElement(val)
        let page = IOHIDElementGetUsagePage(elem)
        guard page == kHIDPage_Button || page == kHIDPage_GenericDesktop || page == kHIDPage_Simulation else { return }
        let usage = IOHIDElementGetUsage(elem)
        let intVal = IOHIDValueGetIntegerValue(val)

        // Find which device sent this
        guard let devIdx = devices.firstIndex(where: {
            IOHIDElementGetDevice(elem) == $0.device
        }) else { return }

        let oldState = devices[devIdx]
        var state = oldState

        if page == kHIDPage_Button {
            let btn = Int(usage)
            if intVal != 0 {
                state.buttons.insert(btn)
            } else {
                state.buttons.remove(btn)
            }
        } else if page == kHIDPage_GenericDesktop {
            let minVal = Double(IOHIDElementGetLogicalMin(elem))
            let maxVal = Double(IOHIDElementGetLogicalMax(elem))
            let norm: Double
            if maxVal > minVal {
                norm = ((Double(intVal) - minVal) / (maxVal - minVal)) * 2.0 - 1.0
            } else {
                norm = 0
            }

            switch usage {
            case UInt32(kHIDUsage_GD_X):
                state.lx = max(-1.0, min(1.0, norm))
            case UInt32(kHIDUsage_GD_Y):
                // Inverted: HID Y down is positive, we want Up to be positive
                state.ly = max(-1.0, min(1.0, -norm))
            case UInt32(kHIDUsage_GD_Z), UInt32(kHIDUsage_GD_Rx):
                state.rx = max(-1.0, min(1.0, norm))
            case UInt32(kHIDUsage_GD_Rz), UInt32(kHIDUsage_GD_Ry):
                state.ry = max(-1.0, min(1.0, -norm))
            case UInt32(kHIDUsage_GD_Hatswitch):
                let minHat = IOHIDElementGetLogicalMin(elem)
                // Normalize hat to 1..8, 0 = null
                if intVal < minHat || intVal > IOHIDElementGetLogicalMax(elem) {
                    state.hat = 0
                } else if minHat == 0 {
                    state.hat = intVal + 1
                } else {
                    state.hat = intVal
                }
            default:
                break
            }
        } else if page == kHIDPage_Simulation {
            let minVal = Double(IOHIDElementGetLogicalMin(elem))
            let maxVal = Double(IOHIDElementGetLogicalMax(elem))
            let norm = maxVal > minVal ? (Double(intVal) - minVal) / (maxVal - minVal) : 0
            if usage == UInt32(kHIDUsage_Sim_Brake) {
                state.lt = max(0.0, min(1.0, norm))
            } else if usage == UInt32(kHIDUsage_Sim_Accelerator) {
                state.rt = max(0.0, min(1.0, norm))
            }
        }

        let changed = state.buttons != oldState.buttons ||
                      state.hat != oldState.hat ||
                      abs(state.lx - oldState.lx) > 0.004 ||
                      abs(state.ly - oldState.ly) > 0.004 ||
                      abs(state.rx - oldState.rx) > 0.004 ||
                      abs(state.ry - oldState.ry) > 0.004 ||
                      abs(state.lt - oldState.lt) > 0.004 ||
                      abs(state.rt - oldState.rt) > 0.004
        guard changed else { return }

        devices[devIdx] = state

        // Map state to PadInput
        var now = Set<PadInput>()
        if state.buttons.contains(1) { now.insert(.A) }
        if state.buttons.contains(2) { now.insert(.B) }
        if state.buttons.contains(3) { now.insert(.X) }
        if state.buttons.contains(4) { now.insert(.Y) }
        if state.buttons.contains(5) || state.buttons.contains(15) { now.insert(.LB) }
        if state.buttons.contains(6) || state.buttons.contains(16) { now.insert(.RB) }
        if state.buttons.contains(7) || state.lt > 0.45 { now.insert(.LT) }
        if state.buttons.contains(8) || state.rt > 0.45 { now.insert(.RT) }
        if state.buttons.contains(9) || state.buttons.contains(14) { now.insert(.VIEW) }
        if state.buttons.contains(10) || state.buttons.contains(13) { now.insert(.MENU) }
        if state.buttons.contains(11) { now.insert(.LS) }
        if state.buttons.contains(12) { now.insert(.RS) }

        // Hat switch
        switch state.hat {
        case 1: now.insert(.DUP)
        case 2: now.insert(.DUP); now.insert(.DRIGHT)
        case 3: now.insert(.DRIGHT)
        case 4: now.insert(.DDOWN); now.insert(.DRIGHT)
        case 5: now.insert(.DDOWN)
        case 6: now.insert(.DDOWN); now.insert(.DLEFT)
        case 7: now.insert(.DLEFT)
        case 8: now.insert(.DUP); now.insert(.DLEFT)
        default: break
        }

        // Stick deflections as buttons
        if state.ly > 0.60 { now.insert(.LUP) }
        if state.ly < -0.60 { now.insert(.LDOWN) }
        if state.lx < -0.60 { now.insert(.LLEFT) }
        if state.lx > 0.60 { now.insert(.LRIGHT) }
        if state.ry > 0.60 { now.insert(.RUP) }
        if state.ry < -0.60 { now.insert(.RDOWN) }
        if state.rx < -0.60 { now.insert(.RLEFT) }
        if state.rx > 0.60 { now.insert(.RRIGHT) }

        let ls = CGPoint(x: state.lx, y: state.ly)
        let rs = CGPoint(x: state.rx, y: state.ry)
        let lt = state.lt
        let rt = state.rt

        DispatchQueue.main.async { [weak self] in
            self?.onInput?(devIdx, now, ls, rs, lt, rt)
        }
    }
}

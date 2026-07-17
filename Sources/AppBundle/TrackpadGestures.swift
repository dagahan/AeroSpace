import AppKit
import Foundation

private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var pos: MTPoint
    var vel: MTPoint
}

private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerId: Int32
    var handId: Int32
    var normalizedVector: MTVector
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

private typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32,
) -> Int32

private typealias MTDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterContactFrameCallbackFunc = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
private typealias MTDeviceStartFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32

nonisolated(unsafe) private var lastGestureFire: Double = 0
nonisolated(unsafe) private var accumulatedVelY: Float = 0

private let contactCallback: MTContactCallback = { _, touchesRaw, numTouches, timestamp, _ in
    guard let touchesRaw, numTouches == 3 else {
        accumulatedVelY = 0
        return 0
    }
    let touches = unsafe touchesRaw.assumingMemoryBound(to: MTTouch.self)
    var velY: Float = 0
    for i in 0 ..< Int(numTouches) {
        velY += unsafe touches[i].normalizedVector.vel.y
    }
    velY /= Float(numTouches)
    accumulatedVelY = abs(velY) > 0.1 && (velY > 0) == (accumulatedVelY > 0)
        ? accumulatedVelY + velY
        : velY
    let threshold: Float = 6
    if abs(accumulatedVelY) > threshold, timestamp - lastGestureFire > 0.8 {
        lastGestureFire = timestamp
        let up = accumulatedVelY > 0
        accumulatedVelY = 0
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                up ? MissionControl.show() : MissionControl.hide()
            }
        }
    }
    return 0
}

enum TrackpadGestures {
    static func start() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createListSym = dlsym(handle, "MTDeviceCreateList"),
              let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart")
        else { return }
        let createList = unsafe unsafeBitCast(createListSym, to: MTDeviceCreateListFunc.self)
        let register = unsafe unsafeBitCast(registerSym, to: MTRegisterContactFrameCallbackFunc.self)
        let startDevice = unsafe unsafeBitCast(startSym, to: MTDeviceStartFunc.self)
        guard let devices = createList()?.takeRetainedValue() else { return }
        for i in 0 ..< CFArrayGetCount(devices) {
            guard let device = unsafe CFArrayGetValueAtIndex(devices, i) else { continue }
            let mutableDevice = unsafe UnsafeMutableRawPointer(mutating: device)
            unsafe register(mutableDevice, contactCallback)
            _ = unsafe startDevice(mutableDevice, 0)
        }
    }
}

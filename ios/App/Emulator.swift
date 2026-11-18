import Foundation
import QuartzCore
import SwiftUI
import UIKit

/// The running game: pd_ios.c ticked once a display refresh on the main thread (CADisplayLink), its two pictures handed to
/// the Metal views, its sound to AudioOut, the buttons from the touch controls and any game controller or keyboard.
@MainActor
final class Emulator: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var title = ""
    @Published private(set) var gameBoy = false
    @Published var showError = false
    @Published var errorText = ""
    @Published private(set) var controllerConnected = false

    /// The on-screen buttons: AUTO = shown unless a game controller is connected; SHOWN / HIDDEN = the player's pick from the
    /// buttons' toggle, kept until a controller connects or disconnects (then AUTO again).
    enum TouchControls: String { case auto, shown, hidden }
    @Published var touchControls: TouchControls = .auto {
        didSet { UserDefaults.standard.set(touchControls.rawValue, forKey: "touchControls") }
    }
    var showsTouchControls: Bool {
        switch touchControls {
        case .auto: return !controllerConnected
        case .shown: return true
        case .hidden: return false
        }
    }
    func toggleTouchControls() {
        touchControls = showsTouchControls ? .hidden : .shown
        if !showsTouchControls { // nothing stays held under buttons that went away
            touchButtons = 0
            tapHold = [Int](repeating: 0, count: Emulator.buttonCount)
        }
    }

    let top = PixelRenderer(width: Int(PD_IOS_TOP_W), height: Int(PD_IOS_TOP_H), format: .rgba8Unorm)
    let bottom = PixelRenderer(width: Int(PD_IOS_BOTTOM_W), height: Int(PD_IOS_BOTTOM_H), format: .bgra8Unorm)

    /// The on-screen controls' buttons (PD_IOS_* bits), set by TouchControls. A tap can begin and end between two ticks,
    /// and the game reads its buttons once a frame, so a new press stays held for at least `Emulator.tapFrames` ticks
    /// (`tapHold`) whatever the finger does: a quick tap registers, holding works as before.
    var touchButtons: UInt32 = 0 {
        didSet {
            let pressed = touchButtons & ~oldValue
            guard pressed != 0 else { return }
            for bit in 0..<Emulator.buttonCount where pressed & (1 << UInt32(bit)) != 0 {
                tapHold[bit] = Emulator.tapFrames
            }
        }
    }
    private var tapHold = [Int](repeating: 0, count: Emulator.buttonCount)
    private static let buttonCount = 14
    /// About 1/15 s: past the 3 frames Game Boy games can need to notice a press outside their menus.
    private static let tapFrames = 4

    /// What the touch buttons hold this tick: the fingers down, plus taps still inside their minimum hold.
    private func touchHeldThisTick() -> UInt32 {
        var held = touchButtons
        for bit in 0..<Emulator.buttonCount where tapHold[bit] > 0 {
            held |= 1 << UInt32(bit)
            tapHold[bit] -= 1
        }
        return held
    }
    private let controllers = Controllers()
    private let audio = AudioOut()
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var owed: Double = 0
    private var paused = false
    private var batteryTimer: Timer?

    private static let frameTime = 1.0 / 60.0

    init() {
        controllers.onChange = { [weak self] connected in
            Task { @MainActor in
                guard let self, self.controllerConnected != connected else { return }
                self.controllerConnected = connected
                self.touchControls = .auto
            }
        }
        controllers.start()
        controllerConnected = controllers.connected
        touchControls = TouchControls(rawValue: UserDefaults.standard.string(forKey: "touchControls") ?? "") ?? .auto
    }

    func start(_ game: Game) {
        var error = [CChar](repeating: 0, count: 256)
        let ok = pd_ios_start(game.url.path, game.saveURL.path, &error, error.count)
        guard ok else {
            errorText = String(cString: error)
            showError = true
            return
        }
        title = String(cString: pd_ios_title())
        gameBoy = pd_ios_game_boy()
        touchButtons = 0
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBattery()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateBattery() }
        }
        audio.start()
        startLink()
    }

    func stop() {
        stopLink()
        audio.stop()
        pd_ios_stop()
        batteryTimer?.invalidate()
        batteryTimer = nil
        running = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func pause() {
        paused = true
        link?.isPaused = true
        if running { audio.pause() }
    }

    func resume() {
        paused = false
        guard running else { return }
        lastTime = 0
        audio.start()
        link?.isPaused = false
    }

    func flushSave() {
        pd_ios_flush_save()
    }

    /// A finger on the companion, in its 320x240 pixels (nil = lifted).
    func touchCompanion(_ point: CGPoint?) {
        if let p = point {
            pd_ios_touch(Int32(p.x), Int32(p.y), true)
        } else {
            pd_ios_touch(0, 0, false)
        }
    }

    private func startLink() {
        stopLink()
        let proxy = LinkProxy { [weak self] link in self?.step(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        link.isPaused = paused
        self.link = link
        lastTime = 0
        owed = 0
        pd_ios_set_refresh(60)
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    /// One refresh: a tick of the game when a 60th of a second is owed (a ProMotion screen may call twice as often).
    private func step(_ link: CADisplayLink) {
        guard running else { return }
        let now = link.timestamp
        if lastTime == 0 { lastTime = now - Emulator.frameTime }
        let dt = min(now - lastTime, 0.25)
        lastTime = now
        owed += dt
        guard owed >= Emulator.frameTime * 0.75 else { return }
        owed = min(owed - Emulator.frameTime, Emulator.frameTime)

        pd_ios_set_buttons(touchHeldThisTick() | controllers.buttons)
        let result = pd_ios_tick(UInt32((dt * 1000).rounded()))
        if result & Int32(PD_IOS_TOP_CHANGED) != 0 { top.upload(pd_ios_top()) }
        if result & Int32(PD_IOS_BOTTOM_CHANGED) != 0 { bottom.upload(pd_ios_bottom()) }
        if result & Int32(PD_IOS_LEAVE) != 0 { stop() }
    }

    private func updateBattery() {
        let device = UIDevice.current
        let level = device.batteryLevel
        let pct = level < 0 ? -1 : Int32((level * 100).rounded())
        let charging = device.batteryState == .charging || device.batteryState == .full
        pd_ios_set_battery(pct, charging)
    }
}

/// CADisplayLink holds its target strongly: this keeps the emulator out of that.
/// It's added to the main run loop, so its calls come on the main thread.
private final class LinkProxy: NSObject {
    let body: @MainActor (CADisplayLink) -> Void
    init(_ body: @escaping @MainActor (CADisplayLink) -> Void) { self.body = body }
    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated { body(link) }
    }
}

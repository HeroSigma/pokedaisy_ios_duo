import GameController

/// Game controllers and a hardware keyboard, read once a tick. Buttons go by where they sit, as on a Nintendo pad: the
/// right face button is A, the bottom one B, the top one X (the buttons to the companion / BACK), the left one Y (the
/// QUICK MENU); L2 steps the companion's tabs back and R2 turns fast-forward on and off, as the 3DS build has them.
@MainActor
final class Controllers {
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    var connected: Bool {
        GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    func start() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.onChange?(self.connected)
                }
            })
        }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    var buttons: UInt32 {
        var held: UInt32 = 0
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            func on(_ button: GCControllerButtonInput?, _ bit: Int) {
                if button?.isPressed == true { held |= UInt32(bit) }
            }
            on(pad.buttonB, PD_IOS_A)
            on(pad.buttonA, PD_IOS_B)
            on(pad.buttonY, PD_IOS_X)
            on(pad.buttonX, PD_IOS_Y)
            on(pad.leftShoulder, PD_IOS_L)
            on(pad.rightShoulder, PD_IOS_R)
            on(pad.leftTrigger, PD_IOS_ZL)
            on(pad.rightTrigger, PD_IOS_ZR)
            on(pad.buttonMenu, PD_IOS_START)
            on(pad.buttonOptions, PD_IOS_SELECT)
            on(pad.dpad.up, PD_IOS_UP)
            on(pad.dpad.down, PD_IOS_DOWN)
            on(pad.dpad.left, PD_IOS_LEFT)
            on(pad.dpad.right, PD_IOS_RIGHT)
            let x = pad.leftThumbstick.xAxis.value, y = pad.leftThumbstick.yAxis.value
            if x > 0.5 { held |= UInt32(PD_IOS_RIGHT) }
            if x < -0.5 { held |= UInt32(PD_IOS_LEFT) }
            if y > 0.5 { held |= UInt32(PD_IOS_UP) }
            if y < -0.5 { held |= UInt32(PD_IOS_DOWN) }
        }
        if let keyboard = GCKeyboard.coalesced?.keyboardInput {
            let keys: [(GCKeyCode, Int)] = [
                (.upArrow, PD_IOS_UP), (.downArrow, PD_IOS_DOWN), (.leftArrow, PD_IOS_LEFT), (.rightArrow, PD_IOS_RIGHT),
                (.keyX, PD_IOS_A), (.keyZ, PD_IOS_B), (.keyA, PD_IOS_L), (.keyS, PD_IOS_R),
                (.returnOrEnter, PD_IOS_START), (.deleteOrBackspace, PD_IOS_SELECT), (.rightShift, PD_IOS_SELECT),
                (.keyC, PD_IOS_X), (.keyQ, PD_IOS_Y), (.keyW, PD_IOS_ZL), (.tab, PD_IOS_ZR),
            ]
            for (code, bit) in keys where keyboard.button(forKeyCode: code)?.isPressed == true {
                held |= UInt32(bit)
            }
        }
        return held
    }
}

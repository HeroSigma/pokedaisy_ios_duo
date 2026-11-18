import GameController
import SwiftUI

/// What a controller's buttons do. Each action can have several inputs; an input belongs to one action at a time.
/// Inputs are named by the controller's own element names (GCInputButtonA, "Direction Pad Up", ...), so any controller
/// iOS knows works, and a binding made on one pad carries to another of the same kind.
struct ControllerAction: Identifiable, Hashable {
    let bit: Int
    let label: String
    let detail: String
    var id: Int { bit }

    static let all: [ControllerAction] = [
        ControllerAction(bit: PD_IOS_UP, label: "Up", detail: ""),
        ControllerAction(bit: PD_IOS_DOWN, label: "Down", detail: ""),
        ControllerAction(bit: PD_IOS_LEFT, label: "Left", detail: ""),
        ControllerAction(bit: PD_IOS_RIGHT, label: "Right", detail: ""),
        ControllerAction(bit: PD_IOS_A, label: "A", detail: ""),
        ControllerAction(bit: PD_IOS_B, label: "B", detail: ""),
        ControllerAction(bit: PD_IOS_L, label: "L", detail: ""),
        ControllerAction(bit: PD_IOS_R, label: "R", detail: ""),
        ControllerAction(bit: PD_IOS_START, label: "START", detail: ""),
        ControllerAction(bit: PD_IOS_SELECT, label: "SELECT", detail: ""),
        ControllerAction(bit: PD_IOS_ZR, label: "Fast forward", detail: "A press turns it on, the next off"),
        ControllerAction(bit: PD_IOS_Y, label: "Quick menu", detail: ""),
        ControllerAction(bit: PD_IOS_X, label: "Companion", detail: "Gives the buttons to the companion and back"),
        ControllerAction(bit: PD_IOS_ZL, label: "Companion tab back", detail: ""),
    ]
}

@MainActor
final class Controllers: ObservableObject {
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    /// Input name -> action bit.
    @Published private(set) var bindings: [String: Int]
    /// Waiting for a press to bind to this action (the game gets no controller buttons meanwhile).
    @Published var capturing: ControllerAction?
    private var heldAtCapture: Set<String> = []
    /// Analog inputs (triggers, sticks) on / off with a gap between the two thresholds, so a trigger let go slowly
    /// doesn't flicker: a flicker read as a second press of FF, turning it straight back off.
    private var analogOn: Set<String> = []

    private static let key = "controllerBindings"
    private static let stick = GCInputLeftThumbstick

    static let defaults: [String: Int] = [
        GCInputButtonB: PD_IOS_A, GCInputButtonA: PD_IOS_B, GCInputButtonY: PD_IOS_X, GCInputButtonX: PD_IOS_Y,
        GCInputLeftShoulder: PD_IOS_L, GCInputRightShoulder: PD_IOS_R,
        GCInputLeftTrigger: PD_IOS_ZL, GCInputRightTrigger: PD_IOS_ZR,
        GCInputButtonMenu: PD_IOS_START, GCInputButtonOptions: PD_IOS_SELECT,
        "\(GCInputDirectionPad) Up": PD_IOS_UP, "\(GCInputDirectionPad) Down": PD_IOS_DOWN,
        "\(GCInputDirectionPad) Left": PD_IOS_LEFT, "\(GCInputDirectionPad) Right": PD_IOS_RIGHT,
        "\(stick) Up": PD_IOS_UP, "\(stick) Down": PD_IOS_DOWN, "\(stick) Left": PD_IOS_LEFT, "\(stick) Right": PD_IOS_RIGHT,
    ]

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: Controllers.key) as? [String: Int], !saved.isEmpty {
            bindings = saved
        } else {
            bindings = Controllers.defaults
        }
    }

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

    // ---- bindings ----

    func inputs(for action: ControllerAction) -> [String] {
        bindings.filter { $0.value == action.bit }.map(\.key).sorted()
    }

    func startCapture(_ action: ControllerAction) {
        heldAtCapture = pressedInputs() // a button already down when it started isn't the answer
        capturing = action
    }

    func cancelCapture() {
        capturing = nil
    }

    func clear(_ action: ControllerAction) {
        bindings = bindings.filter { $0.value != action.bit }
        save()
    }

    func resetToDefaults() {
        bindings = Controllers.defaults
        capturing = nil
        save()
    }

    private func bind(_ input: String, to action: ControllerAction) {
        var b = bindings
        b[input] = action.bit // taken off whatever had it
        bindings = b
        save()
    }

    private func save() {
        UserDefaults.standard.set(bindings, forKey: Controllers.key)
    }

    /// Short, readable names for the list ("Right Trigger", "D-pad Up").
    static func display(_ input: String) -> String {
        input.replacingOccurrences(of: GCInputDirectionPad, with: "D-pad")
            .replacingOccurrences(of: "Direction Pad", with: "D-pad")
    }

    // ---- reading ----

    /// Every input held now, by name, on every controller.
    private func pressedInputs() -> Set<String> {
        var held = Set<String>()
        for controller in GCController.controllers() {
            let profile = controller.physicalInputProfile
            for (name, button) in profile.buttons {
                if name == GCInputButtonHome { continue } // the system's
                if button.isAnalog {
                    if analog(name, button.value) { held.insert(name) }
                } else if button.isPressed {
                    held.insert(name)
                }
            }
            for (name, pad) in profile.dpads {
                let x = pad.xAxis.value, y = pad.yAxis.value
                if analog("\(name) Up", y) { held.insert("\(name) Up") }
                if analog("\(name) Down", -y) { held.insert("\(name) Down") }
                if analog("\(name) Left", -x) { held.insert("\(name) Left") }
                if analog("\(name) Right", x) { held.insert("\(name) Right") }
            }
        }
        return held
    }

    private func analog(_ name: String, _ value: Float) -> Bool {
        if analogOn.contains(name) {
            if value < 0.3 { analogOn.remove(name) }
        } else if value > 0.55 {
            analogOn.insert(name)
        }
        return analogOn.contains(name)
    }

    var buttons: UInt32 {
        let pressed = pressedInputs()
        if let action = capturing {
            // Binding: the first input pressed since it began is the answer; the game gets nothing meanwhile.
            heldAtCapture.formIntersection(pressed)
            if let input = pressed.subtracting(heldAtCapture).sorted().first {
                bind(input, to: action)
                capturing = nil
                heldAtCapture = pressed
            }
            return 0
        }
        if !heldAtCapture.isEmpty {
            heldAtCapture.formIntersection(pressed) // the press that made a binding stays away from the game until let go
        }
        var held: UInt32 = 0
        for input in pressed.subtracting(heldAtCapture) {
            if let bit = bindings[input] { held |= UInt32(bit) }
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

/// CONTROLLER BUTTONS: tap an action, then press the button for it on the controller.
struct ControllerBindingsView: View {
    @ObservedObject var controllers: Controllers
    @Environment(\.dismiss) private var dismiss
    /// The capture reads the pad on a timer when no game is running to read it.
    private let poll = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    var pollsItself: Bool

    var body: some View {
        NavigationStack {
            List {
                if !controllers.connected {
                    Text("Connect a controller to change its buttons.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(ControllerAction.all) { action in
                        Button {
                            if controllers.capturing == action { controllers.cancelCapture() }
                            else { controllers.startCapture(action) }
                        } label: {
                            row(action)
                        }
                        .swipeActions {
                            Button("Clear", role: .destructive) { controllers.clear(action) }
                        }
                    }
                } footer: {
                    Text("Tap an action, then press the button you want for it. A button moves off whatever it did before. Swipe left to clear one. The keyboard's keys stay as they are.")
                }
                Section {
                    Button("Reset to defaults", role: .destructive) { controllers.resetToDefaults() }
                }
            }
            .navigationTitle("Controller buttons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        controllers.cancelCapture()
                        dismiss()
                    }
                }
            }
        }
        .onReceive(poll) { _ in
            if pollsItself && controllers.capturing != nil { _ = controllers.buttons }
        }
        .onDisappear { controllers.cancelCapture() }
    }

    private func row(_ action: ControllerAction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.label).foregroundStyle(.primary)
                if !action.detail.isEmpty {
                    Text(action.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if controllers.capturing == action {
                Text("Press a button…").foregroundStyle(Color.accentColor).bold()
            } else {
                let names = controllers.inputs(for: action).map(Controllers.display)
                Text(names.isEmpty ? "None" : names.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .contentShape(Rectangle())
    }
}

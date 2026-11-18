import SwiftUI
import UIKit

/// The on-screen buttons. Each control sets its own bits in Emulator.touchButtons while a finger is on it; several can
/// be held at once (SwiftUI tracks each finger's gesture on its own view).
struct ControlButton: View {
    @EnvironmentObject var emulator: Emulator
    let label: String
    let bit: Int
    var size: CGSize = CGSize(width: 64, height: 64)
    var round = true
    var accent = Color(white: 0.22)
    /// FF's button: lit while fast forward is on (it's a toggle).
    var showsFF = false
    @State private var pressed = false

    var body: some View {
        let lit = pressed || (showsFF && emulator.ffOn)
        let shape = RoundedRectangle(cornerRadius: round ? min(size.width, size.height) / 2 : 8, style: .continuous)
        Text(label)
            .font(.system(size: max(10, min(size.width, size.height) * (round ? 0.36 : 0.32)), weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(lit ? 1 : 0.85))
            .frame(width: size.width, height: size.height)
            .background(shape.fill(lit ? accent.opacity(1) : accent.opacity(0.75)))
            .overlay(shape.stroke(.white.opacity(lit ? 0.6 : 0.18), lineWidth: 1.5))
            .scaleEffect(pressed ? 0.94 : 1)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            emulator.touchButtons |= UInt32(bit)
                            Haptics.tap()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        emulator.touchButtons &= ~UInt32(bit)
                    }
            )
            .accessibilityLabel(label)
    }
}

/// Eight ways: a finger between two arms holds both.
struct DPad: View {
    @EnvironmentObject var emulator: Emulator
    let size: CGFloat
    @State private var dirs: UInt32 = 0
    private static let all = UInt32(PD_IOS_UP | PD_IOS_DOWN | PD_IOS_LEFT | PD_IOS_RIGHT)

    var body: some View {
        let arm = size / 3
        ZStack {
            Group {
                RoundedRectangle(cornerRadius: 6).frame(width: arm, height: size)
                RoundedRectangle(cornerRadius: 6).frame(width: size, height: arm)
            }
            .foregroundStyle(Color(white: 0.22).opacity(0.8))
            arrow("arrowtriangle.up.fill", PD_IOS_UP).offset(y: -arm)
            arrow("arrowtriangle.down.fill", PD_IOS_DOWN).offset(y: arm)
            arrow("arrowtriangle.left.fill", PD_IOS_LEFT).offset(x: -arm)
            arrow("arrowtriangle.right.fill", PD_IOS_RIGHT).offset(x: arm)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in set(dirsAt(value.location)) }
                .onEnded { _ in set(0) }
        )
        .accessibilityLabel("Direction pad")
    }

    private func arrow(_ symbol: String, _ bit: Int) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.11))
            .foregroundStyle(.white.opacity(dirs & UInt32(bit) != 0 ? 1 : 0.55))
    }

    private func dirsAt(_ p: CGPoint) -> UInt32 {
        let dx = p.x - size / 2, dy = p.y - size / 2
        if hypot(dx, dy) < size * 0.1 { return 0 }
        var bits: UInt32 = 0
        // tan(22.5°): within that of an axis is that direction alone, between two axes both.
        if abs(dx) > abs(dy) * 0.414 { bits |= UInt32(dx > 0 ? PD_IOS_RIGHT : PD_IOS_LEFT) }
        if abs(dy) > abs(dx) * 0.414 { bits |= UInt32(dy > 0 ? PD_IOS_DOWN : PD_IOS_UP) }
        return bits
    }

    private func set(_ bits: UInt32) {
        guard bits != dirs else { return }
        if bits & ~dirs != 0 { Haptics.tap() }
        dirs = bits
        emulator.touchButtons = (emulator.touchButtons & ~DPad.all) | bits
    }
}

/// A thumbstick for the D-pad: it centres itself where the thumb lands (anywhere in its area), the knob follows the thumb,
/// and past the rim the centre is dragged along so turning back is quick. Straight directions get the wider share
/// (60° each); between them a 30° band holds both, so walking a line is easy.
struct Joystick: View {
    @EnvironmentObject var emulator: Emulator
    let size: CGFloat
    @State private var origin: CGPoint?
    @State private var knob: CGSize = .zero
    @State private var dirs: UInt32 = 0
    private static let all = UInt32(PD_IOS_UP | PD_IOS_DOWN | PD_IOS_LEFT | PD_IOS_RIGHT)

    var body: some View {
        let base = size * 0.72, radius = base * 0.42, knobSize = base * 0.46
        let centre = origin ?? CGPoint(x: size / 2, y: size / 2)
        ZStack {
            Circle()
                .fill(Color(white: 0.22).opacity(origin == nil ? 0.55 : 0.8))
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1.5))
                .frame(width: base, height: base)
                .position(centre)
            ForEach(0..<4, id: \.self) { i in
                arrow(i, centre: centre, reach: base * 0.4, size: base * 0.09)
            }
            Circle()
                .fill(Color(white: origin == nil ? 0.38 : 0.55))
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .frame(width: knobSize, height: knobSize)
                .position(x: centre.x + knob.width, y: centre.y + knob.height)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var o = origin ?? value.startLocation
                    var dx = value.location.x - o.x, dy = value.location.y - o.y
                    let d = hypot(dx, dy)
                    if d > radius { // past the rim: the centre follows the thumb
                        o.x += dx * (d - radius) / d
                        o.y += dy * (d - radius) / d
                        dx = value.location.x - o.x
                        dy = value.location.y - o.y
                    }
                    origin = o
                    knob = CGSize(width: dx, height: dy)
                    set(dirsFor(dx: dx, dy: dy, radius: radius))
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        origin = nil
                        knob = .zero
                    }
                    set(0)
                }
        )
        .accessibilityLabel("Movement stick")
    }

    private static let arrowBits: [Int] = [PD_IOS_UP, PD_IOS_RIGHT, PD_IOS_DOWN, PD_IOS_LEFT]
    private static let arrowX: [CGFloat] = [0, 1, 0, -1]
    private static let arrowY: [CGFloat] = [-1, 0, 1, 0]

    private func arrow(_ i: Int, centre: CGPoint, reach: CGFloat, size: CGFloat) -> some View {
        let on = dirs & UInt32(Joystick.arrowBits[i]) != 0
        let x: CGFloat = centre.x + Joystick.arrowX[i] * reach
        let y: CGFloat = centre.y + Joystick.arrowY[i] * reach
        return Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: size))
            .foregroundStyle(.white.opacity(on ? 1 : 0.4))
            .rotationEffect(.degrees(Double(i) * 90))
            .position(x: x, y: y)
    }

    private func dirsFor(dx: CGFloat, dy: CGFloat, radius: CGFloat) -> UInt32 {
        if hypot(dx, dy) < radius * 0.3 { return 0 }
        var bits: UInt32 = 0
        // tan(30°): within 30° of an axis is that direction alone, the 30° between two axes both.
        if abs(dx) > abs(dy) * 0.577 { bits |= UInt32(dx > 0 ? PD_IOS_RIGHT : PD_IOS_LEFT) }
        if abs(dy) > abs(dx) * 0.577 { bits |= UInt32(dy > 0 ? PD_IOS_DOWN : PD_IOS_UP) }
        return bits
    }

    private func set(_ bits: UInt32) {
        guard bits != dirs else { return }
        if bits & ~dirs != 0 { Haptics.tap() }
        dirs = bits
        emulator.touchButtons = (emulator.touchButtons & ~Joystick.all) | bits
    }
}

/// A and B on a slant, as on the GBA.
struct FaceButtons: View {
    let size: CGFloat
    var body: some View {
        let b = size * 0.46
        ZStack {
            ControlButton(label: "A", bit: PD_IOS_A, size: CGSize(width: b, height: b), accent: Color(red: 0.55, green: 0.18, blue: 0.3))
                .offset(x: size * 0.24, y: -size * 0.14)
            ControlButton(label: "B", bit: PD_IOS_B, size: CGSize(width: b, height: b), accent: Color(red: 0.55, green: 0.18, blue: 0.3))
                .offset(x: -size * 0.24, y: size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

/// SELECT / START and the app's own two: MENU (the QUICK MENU, the 3DS's Y) and FF (a toggle, the 3DS's ZR).
struct SmallButtons: View {
    let width: CGFloat
    var body: some View {
        let w = min(64, (width - 24) / 2), h = w * 0.42
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ControlButton(label: "SELECT", bit: PD_IOS_SELECT, size: CGSize(width: w, height: h), round: false)
                ControlButton(label: "START", bit: PD_IOS_START, size: CGSize(width: w, height: h), round: false)
            }
            HStack(spacing: 12) {
                ControlButton(label: "MENU", bit: PD_IOS_Y, size: CGSize(width: w, height: h), round: false,
                              accent: Color(red: 0.2, green: 0.35, blue: 0.3))
                ControlButton(label: "FF", bit: PD_IOS_ZR, size: CGSize(width: w, height: h), round: false,
                              accent: Color(red: 0.2, green: 0.3, blue: 0.45), showsFF: true)
            }
        }
    }
}

struct Shoulder: View {
    let label: String
    let bit: Int
    let width: CGFloat
    var body: some View {
        ControlButton(label: label, bit: bit, size: CGSize(width: width, height: max(30, width * 0.42)), round: false)
    }
}

enum Haptics {
    @MainActor private static let generator = UIImpactFeedbackGenerator(style: .light)
    @MainActor static func tap() {
        generator.impactOccurred(intensity: 0.6)
    }
}

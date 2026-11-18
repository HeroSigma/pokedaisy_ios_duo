import SwiftUI

/// A game: its pane (the 3DS top screen's 5:3) and the companion (4:3) both on screen, like PokeDaisy on a two-screen
/// handheld, with the touch controls (hidden while a game controller is connected).
///
/// Which arrangement is used is worked out from the window, so it follows the iPhone Duo as it folds and turns, and an
/// ordinary iPhone too:
///  - STACKED, controls under: the game over the companion, the buttons below (a tall window: folded, upright).
///  - STACKED, controls beside: the same column with the D-pad left and the buttons right (a squarer window: the Duo
///    open, either way round).
///  - SIDE BY SIDE: the game left, the companion right, the buttons at the ends (a wide window: a phone on its side).
/// The one giving the game the most room wins. With the touch buttons hidden (a controller connected, or the player's pick),
/// a thin bar along the bottom keeps the button that brings them back.
struct GameScreen: View {
    @EnvironmentObject var emulator: Emulator

    private static let gameAspect = CGFloat(PD_IOS_TOP_W) / CGFloat(PD_IOS_TOP_H)       // 5:3
    private static let companionAspect = CGFloat(PD_IOS_BOTTOM_W) / CGFloat(PD_IOS_BOTTOM_H) // 4:3

    enum Arrangement { case stackedUnder, stackedBeside, sideBySide }

    static let bar: CGFloat = 36

    struct Layout {
        var arrangement: Arrangement
        var paneWidth: CGFloat        // stacked: both panes' width; side by side: the panes' height
        var strip: CGFloat            // controls under: their height
        var column: CGFloat           // controls beside / at the ends: each column's width
    }

    static func layout(for size: CGSize, touch: Bool) -> Layout {
        let W = size.width, H = size.height
        let strip = touch ? min(max(H * 0.24, 170), 240) : 0
        let column = touch ? min(max(W * 0.15, 130), 190) : 0
        let stackH = 1 / gameAspect + 1 / companionAspect // a stacked column's height per point of width
        let under = max(0, min(W, (H - strip) / stackH))
        let beside = max(0, min(W - 2 * column, H / stackH))
        let sideH = max(0, min(H, (W - 2 * column) / (gameAspect + companionAspect)))
        let sideGame = sideH * gameAspect
        if !touch {
            let barUnder = max(0, min(W, (H - bar) / stackH))
            let barSideH = max(0, min(H - bar, W / (gameAspect + companionAspect)))
            return barUnder >= barSideH * gameAspect
                ? Layout(arrangement: .stackedUnder, paneWidth: barUnder, strip: 0, column: 0)
                : Layout(arrangement: .sideBySide, paneWidth: barSideH, strip: 0, column: 0)
        }
        let best = max(under, beside, sideGame)
        if best == under { return Layout(arrangement: .stackedUnder, paneWidth: under, strip: strip, column: column) }
        if best == beside { return Layout(arrangement: .stackedBeside, paneWidth: beside, strip: strip, column: column) }
        return Layout(arrangement: .sideBySide, paneWidth: sideH, strip: strip, column: column)
    }

    var body: some View {
        GeometryReader { geo in
            let touch = emulator.showsTouchControls
            let l = GameScreen.layout(for: geo.size, touch: touch)
            VStack(spacing: 0) {
                Group {
                    switch l.arrangement {
                    case .stackedUnder:
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            panes(stackedWidth: l.paneWidth)
                            Spacer(minLength: 0)
                            if touch { strip(width: geo.size.width, height: l.strip) }
                        }
                    case .stackedBeside:
                        HStack(spacing: 0) {
                            leftColumn(width: l.column, height: geo.size.height)
                            Spacer(minLength: 0)
                            panes(stackedWidth: l.paneWidth)
                            Spacer(minLength: 0)
                            rightColumn(width: l.column, height: geo.size.height)
                        }
                    case .sideBySide:
                        HStack(spacing: 0) {
                            if touch { leftColumn(width: l.column, height: geo.size.height) }
                            Spacer(minLength: 0)
                            HStack(spacing: 0) {
                                gamePane.frame(width: l.paneWidth * GameScreen.gameAspect, height: l.paneWidth)
                                companionPane.frame(width: l.paneWidth * GameScreen.companionAspect, height: l.paneWidth)
                            }
                            Spacer(minLength: 0)
                            if touch { rightColumn(width: l.column, height: geo.size.height) }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                if !touch {
                    HStack {
                        Spacer()
                        ControlsToggle(shown: false)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: GameScreen.bar)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: the panes

    private func panes(stackedWidth w: CGFloat) -> some View {
        VStack(spacing: 0) {
            gamePane.frame(width: w, height: w / GameScreen.gameAspect)
            companionPane.frame(width: w, height: w / GameScreen.companionAspect)
        }
    }

    private var gamePane: some View {
        PixelView(renderer: emulator.top, background: emulator.gameBoy ? .white : .black)
            .accessibilityLabel("Game screen")
    }

    /// The companion takes taps as the 3DS's touch screen does: its own 320x240 pixels.
    private var companionPane: some View {
        GeometryReader { geo in
            PixelView(renderer: emulator.bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x / max(geo.size.width, 1) * CGFloat(PD_IOS_BOTTOM_W)
                            let y = value.location.y / max(geo.size.height, 1) * CGFloat(PD_IOS_BOTTOM_H)
                            emulator.touchCompanion(CGPoint(x: x, y: y))
                        }
                        .onEnded { _ in emulator.touchCompanion(nil) }
                )
        }
        .accessibilityLabel("Companion")
    }

    // MARK: the controls

    private func strip(width: CGFloat, height: CGFloat) -> some View {
        let pad = min(height * 0.82, width * 0.36)
        return VStack(spacing: 6) {
            HStack {
                Shoulder(label: "L", bit: PD_IOS_L, width: min(90, width * 0.2))
                Spacer()
                ControlsToggle(shown: true)
                Spacer()
                Shoulder(label: "R", bit: PD_IOS_R, width: min(90, width * 0.2))
            }
            .padding(.horizontal, 12)
            HStack(spacing: 0) {
                DPad(size: pad * 0.78)
                    .frame(width: pad)
                Spacer(minLength: 4)
                SmallButtons(width: max(110, width - 2 * pad - 16))
                Spacer(minLength: 4)
                FaceButtons(size: pad * 0.86)
                    .frame(width: pad)
            }
        }
        .frame(width: width, height: height)
    }

    private func leftColumn(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 16) {
            Shoulder(label: "L", bit: PD_IOS_L, width: width * 0.62)
            ControlsToggle(shown: true)
            Spacer()
            DPad(size: width * 0.88)
            Spacer()
            HStack(spacing: 8) {
                ControlButton(label: "SELECT", bit: PD_IOS_SELECT, size: CGSize(width: width * 0.42, height: 26), round: false)
                ControlButton(label: "MENU", bit: PD_IOS_Y, size: CGSize(width: width * 0.42, height: 26), round: false,
                              accent: Color(red: 0.2, green: 0.35, blue: 0.3))
            }
        }
        .padding(.vertical, 16)
        .frame(width: width, height: height)
    }

    private func rightColumn(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 16) {
            Shoulder(label: "R", bit: PD_IOS_R, width: width * 0.62)
            Spacer()
            FaceButtons(size: width * 0.92)
            Spacer()
            HStack(spacing: 8) {
                ControlButton(label: "FF", bit: PD_IOS_ZR, size: CGSize(width: width * 0.42, height: 26), round: false,
                              accent: Color(red: 0.2, green: 0.3, blue: 0.45))
                ControlButton(label: "START", bit: PD_IOS_START, size: CGSize(width: width * 0.42, height: 26), round: false)
            }
        }
        .padding(.vertical, 16)
        .frame(width: width, height: height)
    }
}

/// Shows or hides the on-screen buttons (Emulator.touchControls). With a controller connected they start hidden; this
/// brings them up when they're needed, and back down.
struct ControlsToggle: View {
    @EnvironmentObject var emulator: Emulator
    let shown: Bool

    var body: some View {
        Button {
            emulator.toggleTouchControls()
        } label: {
            Label(shown ? "Hide buttons" : "Show buttons", systemImage: shown ? "gamecontroller.fill" : "gamecontroller")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(white: 0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shown ? "Hide the on-screen buttons" : "Show the on-screen buttons")
    }
}

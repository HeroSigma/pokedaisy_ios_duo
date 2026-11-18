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
/// The one giving the game the most room wins. Held sideways (wider than tall) it's PokeDaisy's one-screen look instead: the
/// game alone with EXPAND (the overworld past the GBA's edges) and the HUD, the companion over it from its button or the
/// controller's X. With the touch buttons hidden (a controller connected, or the player's pick),
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
            let wide = geo.size.width > geo.size.height
            Group {
                if wide { landscape(size: geo.size) } else { twoPanes(size: geo.size) }
            }
            .onAppear { emulator.setLandscape(wide) }
            .onChange(of: wide) { _, now in emulator.setLandscape(now) }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $emulator.showsBindings) {
            ControllerBindingsView(controllers: emulator.controllers, pollsItself: false)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: sideways: the game alone

    private func landscape(size: CGSize) -> some View {
        let touch = emulator.showsTouchControls
        let column = touch ? min(max(size.width * 0.15, 130), 190) : 0
        let roomW = size.width - 2 * column, roomH = size.height - (touch ? 0 : GameScreen.bar)
        let gameW = max(0, min(roomW, roomH * GameScreen.gameAspect))
        return ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if touch { leftColumn(width: column, height: size.height, companionButton: true) }
                    Spacer(minLength: 0)
                    gamePane.frame(width: gameW, height: gameW / GameScreen.gameAspect)
                    Spacer(minLength: 0)
                    if touch { rightColumn(width: column, height: size.height) }
                }
                .frame(maxHeight: .infinity)
                if !touch {
                    HStack(spacing: 10) {
                        Spacer()
                        BindingsButton()
                        CompanionButton()
                        ControlsToggle(shown: false)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: GameScreen.bar)
                }
            }
            if emulator.showsCompanionOverlay { companionWindow(size: size) }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The companion over the dimmed game (which keeps running), as the one-screen Android build's window: 4:3, most of the
    /// height, an X at its corner; a tap on the dim closes it too.
    private func companionWindow(size: CGSize) -> some View {
        let h = min(size.height * 0.88, size.width * 0.9 / GameScreen.companionAspect)
        let w = h * GameScreen.companionAspect
        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { emulator.closeCompanion() }
            companionPane
                .frame(width: w, height: h)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.85), lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    Button {
                        emulator.closeCompanion()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(white: 0.2)))
                            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 14, y: -14)
                    .accessibilityLabel("Close the companion")
                }
        }
        .transition(.opacity)
    }

    // MARK: upright: game and companion

    private func twoPanes(size: CGSize) -> some View {
        let touch = emulator.showsTouchControls
        let l = GameScreen.layout(for: size, touch: touch)
        return VStack(spacing: 0) {
            Group {
                switch l.arrangement {
                case .stackedUnder:
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        panes(stackedWidth: l.paneWidth)
                        Spacer(minLength: 0)
                        if touch { strip(width: size.width, height: l.strip) }
                    }
                case .stackedBeside:
                    HStack(spacing: 0) {
                        leftColumn(width: l.column, height: size.height)
                        Spacer(minLength: 0)
                        panes(stackedWidth: l.paneWidth)
                        Spacer(minLength: 0)
                        rightColumn(width: l.column, height: size.height)
                    }
                case .sideBySide:
                    HStack(spacing: 0) {
                        if touch { leftColumn(width: l.column, height: size.height) }
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            gamePane.frame(width: l.paneWidth * GameScreen.gameAspect, height: l.paneWidth)
                            companionPane.frame(width: l.paneWidth * GameScreen.companionAspect, height: l.paneWidth)
                        }
                        Spacer(minLength: 0)
                        if touch { rightColumn(width: l.column, height: size.height) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if !touch {
                HStack(spacing: 10) {
                    Spacer()
                    BindingsButton()
                    ControlsToggle(shown: false)
                }
                .padding(.horizontal, 12)
                .frame(height: GameScreen.bar)
            }
            }
        .frame(width: size.width, height: size.height)
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
                Joystick(size: pad * 0.9)
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

    private func leftColumn(width: CGFloat, height: CGFloat, companionButton: Bool = false) -> some View {
        VStack(spacing: 16) {
            Shoulder(label: "L", bit: PD_IOS_L, width: width * 0.62)
            ControlsToggle(shown: true)
            if companionButton { CompanionButton() }
            Spacer()
            Joystick(size: width * 0.98)
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
                              accent: Color(red: 0.2, green: 0.3, blue: 0.45), showsFF: true)
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

/// Opens CONTROLLER BUTTONS (custom binds) over the game.
struct BindingsButton: View {
    @EnvironmentObject var emulator: Emulator

    var body: some View {
        Button {
            emulator.showsBindings = true
        } label: {
            Label("Buttons", systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(white: 0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change the controller's buttons")
    }
}

/// Sideways: brings the companion up over the game (the controller's X does too, and gives it the buttons).
struct CompanionButton: View {
    @EnvironmentObject var emulator: Emulator

    var body: some View {
        Button {
            emulator.openCompanion()
        } label: {
            Label("Companion", systemImage: "rectangle.on.rectangle")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(white: 0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the companion")
    }
}

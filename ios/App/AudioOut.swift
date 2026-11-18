import AVFoundation

/// The game's sound: an AVAudioSourceNode that pulls pd_ios.c's ring on the audio thread. pd_ios.c keeps the ring about
/// 50 ms full by nudging the emulated sound's rate, so this never waits and never resamples.
final class AudioOut {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let scratch: UnsafeMutablePointer<Int16>
    private var observers: [NSObjectProtocol] = []
    private var wanted = false // started and not paused / stopped: what an interruption's end goes back to
    private static let maxFrames = 4096

    init() {
        scratch = UnsafeMutablePointer<Int16>.allocate(capacity: AudioOut.maxFrames * 2)
        scratch.initialize(repeating: 0, count: AudioOut.maxFrames * 2)
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(PD_IOS_AUDIO_RATE), channels: 2)!
        let scratch = self.scratch
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            var done = 0
            let total = Int(frameCount)
            while done < total {
                let n = min(total - done, AudioOut.maxFrames)
                pd_ios_audio_read(scratch, Int32(n))
                for channel in 0..<min(buffers.count, 2) {
                    guard let out = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for i in 0..<n {
                        out[done + i] = Float(scratch[i * 2 + channel]) / 32768
                    }
                }
                done += n
            }
            return noErr
        }
        self.node = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        // Another app's sound (a call, an alarm, Siri) can stop the engine; music started alongside shouldn't, but if
        // anything does, the game's sound comes back when it's over, mixed in with whatever is playing.
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification,
                     .AVAudioEngineConfigurationChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, self.wanted else { return }
                if note.name == AVAudioSession.interruptionNotification,
                   let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   AVAudioSession.InterruptionType(rawValue: raw) == .began { return }
                self.start()
            })
        }
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        scratch.deallocate()
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        // A game's sound: quiet with the ring / silent switch, mixed with what else is playing (your own music keeps
        // playing alongside the game, and the game alongside it).
        wanted = true
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.01)
        try? session.setActive(true)
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    func pause() {
        wanted = false
        engine.pause()
    }

    func stop() {
        wanted = false
        engine.stop()
    }
}

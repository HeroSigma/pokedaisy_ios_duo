import AVFoundation

/// The game's sound: an AVAudioSourceNode that pulls pd_ios.c's ring on the audio thread. pd_ios.c keeps the ring about
/// 50 ms full by nudging the emulated sound's rate, so this never waits and never resamples.
final class AudioOut {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let scratch: UnsafeMutablePointer<Int16>
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
    }

    deinit {
        scratch.deallocate()
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        // A game's sound: quiet with the ring / silent switch, mixed with what else is playing.
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setPreferredIOBufferDuration(0.01)
        try? session.setActive(true)
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    func pause() {
        engine.pause()
    }

    func stop() {
        engine.stop()
    }
}

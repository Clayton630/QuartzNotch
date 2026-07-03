// AudioWaveformEngine.swift
import Foundation
import Accelerate
import AppKit
import CoreAudio
import SwiftUI

// Runs entirely on the caller's processingQueue — no actor isolation
private final class FFTProcessor: @unchecked Sendable {
    let fftSize = 4096
    private var fftSetup: FFTSetup?
    private var inputDataBuffer: [Float]
    private var magnitudesBuffer: [Float]
    private var magnitudesOutputBuffer: [Float]
    private var windowedBuffer: [Float]
    private var realPartsBuffer: [Float]
    private var imagPartsBuffer: [Float]
    private var hanningWindow: [Float]
    private var powerOutputBuffer: [Float]
    var sampleRate: Float = 48_000

    private var lastProcessTime: TimeInterval = 0
    let updateInterval: TimeInterval = 1.0 / 30.0

    private struct Band {
        let start: Float
        let peak: Float
        let end: Float
        let minDB: Float
        let maxDB: Float
        let curve: Float
    }

    private let bands: [Band] = [
        Band(start: 15,   peak: 35,   end: 90,    minDB: -36, maxDB: -4,  curve: 1.25),
        Band(start: 35,   peak: 100,  end: 160,   minDB: -38, maxDB: -2,  curve: 1.40),
        Band(start: 105,  peak: 300,  end: 520,   minDB: -42, maxDB: -8,  curve: 1.30),
        Band(start: 300,  peak: 620,  end: 1500,  minDB: -51, maxDB: -14, curve: 1.00),
        Band(start: 620,  peak: 1700, end: 4500,  minDB: -55, maxDB: -18, curve: 0.92),
        Band(start: 1200, peak: 4000, end: 12000, minDB: -50, maxDB: -22, curve: 1.25)
    ]

    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
        inputDataBuffer = Array(repeating: 0, count: fftSize)
        magnitudesBuffer = Array(repeating: 0, count: fftSize / 2)
        magnitudesOutputBuffer = Array(repeating: 0, count: fftSize / 2)
        windowedBuffer = Array(repeating: 0, count: fftSize)
        realPartsBuffer = Array(repeating: 0, count: fftSize / 2)
        imagPartsBuffer = Array(repeating: 0, count: fftSize / 2)
        hanningWindow = Array(repeating: 0, count: fftSize)
        powerOutputBuffer = Array(repeating: 0, count: bands.count)
        vDSP_hann_window(&hanningWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    // Returns nil if called too soon (rate-limited to 60 fps)
    func process(samples: [Float]) -> [Float]? {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastProcessTime >= updateInterval else { return nil }
        lastProcessTime = now

        appendSamples(samples)

        vDSP_vmul(inputDataBuffer, 1, hanningWindow, 1, &windowedBuffer, 1, vDSP_Length(fftSize))

        for index in 0..<(fftSize / 2) {
            realPartsBuffer[index] = windowedBuffer[index * 2]
            imagPartsBuffer[index] = windowedBuffer[index * 2 + 1]
        }

        realPartsBuffer.withUnsafeMutableBufferPointer { realPtr in
            imagPartsBuffer.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress,
                      let imagBase = imagPtr.baseAddress,
                      let setup = fftSetup else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudesBuffer, 1, vDSP_Length(fftSize / 2))
            }
        }

        magnitudesBuffer[0] = 0

        var magCount = Int32(fftSize / 2)
        vvsqrtf(&magnitudesOutputBuffer, magnitudesBuffer, &magCount)

        var scale = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudesOutputBuffer, 1, &scale, &magnitudesOutputBuffer, 1, vDSP_Length(fftSize / 2))

        for index in bands.indices {
            powerOutputBuffer[index] = getPower(for: bands[index], magnitudes: magnitudesOutputBuffer)
        }
        return powerOutputBuffer
    }

    private func appendSamples(_ samples: [Float]) {
        let count = min(samples.count, fftSize)
        guard count > 0 else { return }

        let sourceStart = samples.count - count
        if count >= fftSize {
            for index in 0..<fftSize {
                inputDataBuffer[index] = samples[sourceStart + index]
            }
            return
        }

        let preservedCount = fftSize - count
        inputDataBuffer.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            memmove(base, base.advanced(by: count), preservedCount * MemoryLayout<Float>.size)
            for index in 0..<count {
                base[preservedCount + index] = samples[sourceStart + index]
            }
        }
    }

    private func getPower(for band: Band, magnitudes: [Float]) -> Float {
        let startBin = Int((band.start / sampleRate) * Float(fftSize))
        let endBin   = Int((band.end   / sampleRate) * Float(fftSize))

        let safeLower = max(1, startBin)
        let safeUpper = min(fftSize / 2 - 1, endBin)
        guard safeLower <= safeUpper else { return 0 }

        var maxMag: Float = 0
        var i = safeLower
        while i <= safeUpper {
            let f = Float(i) * sampleRate / Float(fftSize)
            let weight: Float
            if f <= band.peak {
                weight = max(0, (f - band.start) / max(1, band.peak - band.start))
            } else {
                weight = max(0, (band.end - f) / max(1, band.end - band.peak))
            }
            let mag = magnitudes[i] * weight
            if mag > maxMag { maxMag = mag }
            i += 1
        }

        let db = 20 * log10(max(maxMag, 1e-6))
        var normalized = (db - band.minDB) / (band.maxDB - band.minDB)
        normalized = max(0.0, min(1.0, normalized))
        return pow(normalized, band.curve)
    }
}

@MainActor
final class WaveSpectrumLiveModel: ObservableObject {
    @Published var displayBars: [Float] = Array(repeating: 0.0, count: 6)

    private let processingQueue = DispatchQueue(label: "quartz.notch.fft", qos: .utility)
    private let startupQueue = DispatchQueue(label: "quartz.notch.audio-start", qos: .utility)
    // FFTProcessor is accessed exclusively from processingQueue
    private let processor = FFTProcessor()
    private let silentBars: [Float] = Array(repeating: 0, count: 6)

    private var audioToken: UUID?
    private var audioStartID: UUID?
    private var fallbackTimer: Timer?

    func startLive() {
        guard audioToken == nil else { return }
        let token = SystemAudioRecorder.shared.addHandler { [weak self] samples in
            guard let self else { return }
            // Dispatch FFT work to background queue — never touch MainActor here
            self.processingQueue.async { [weak self] in
                guard let self else { return }
                guard let target = self.processor.process(samples: samples) else { return }
                Task { @MainActor [weak self] in self?.applySmoothing(target) }
            }
        }
        audioToken = token

        let startID = UUID()
        audioStartID = startID
        startupQueue.async { [weak self] in
            do {
                try SystemAudioRecorder.shared.startRecording()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.audioStartID == startID, self.audioToken == token {
                        self.audioStartID = nil
                    } else {
                        SystemAudioRecorder.shared.stopRecordingIfUnused()
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.audioStartID == startID, self.audioToken == token else { return }
                    SystemAudioRecorder.shared.removeHandler(token)
                    self.audioToken = nil
                    self.audioStartID = nil
                    self.startFallback()
                }
            }
        }
    }

    func stopLive() {
        audioStartID = nil
        stopFallback()
        if let token = audioToken {
            SystemAudioRecorder.shared.removeHandler(token)
            audioToken = nil
        }
        SystemAudioRecorder.shared.stopRecordingIfUnused()
    }

    private func applySmoothing(_ target: [Float]) {
        let attackRate: Float = 0.85
        let decayRate: Float  = 0.62
        for i in 0..<6 {
            let attack: Float = (i == 3 || i == 4) ? 0.91 : attackRate
            if target[i] > displayBars[i] {
                displayBars[i] += (target[i] - displayBars[i]) * attack
            } else {
                displayBars[i] += (target[i] - displayBars[i]) * decayRate
            }
        }
    }

    func notchBars() -> [Float] { displayBars }

    private func startFallback() {
        guard fallbackTimer == nil else { return }
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.applySmoothing(self.silentBars)
            }
        }
    }

    private func stopFallback() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }
}

final class SystemAudioRecorder: @unchecked Sendable {
    static let shared = SystemAudioRecorder()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "quartz.notch.audio-tap", qos: .userInteractive)
    private var handlers: [UUID: ([Float]) -> Void] = [:]
    private var tapDescription: AnyObject?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isRecording = false
    private var mixBuffer: [Float] = []
    private var lastDeliveryTime: TimeInterval = 0
    private let deliveryInterval: TimeInterval = 1.0 / 30.0

    private init() {}

    func addHandler(_ handler: @escaping ([Float]) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        handlers[token] = handler
        lock.unlock()
        return token
    }

    func removeHandler(_ token: UUID) {
        lock.lock()
        handlers.removeValue(forKey: token)
        let shouldStop = handlers.isEmpty
        lock.unlock()
        if shouldStop { stopRecording() }
    }

    func startRecording() throws {
        lock.lock()
        if isRecording { lock.unlock(); return }
        isRecording = true
        lock.unlock()
        do {
            try createTapGraph()
        } catch {
            lock.lock()
            isRecording = false
            lock.unlock()
            teardownTapGraph()
            throw error
        }
    }

    func stopRecording() {
        lock.lock()
        guard isRecording else { lock.unlock(); return }
        isRecording = false
        lock.unlock()
        teardownTapGraph()
    }

    func stopRecordingIfUnused() {
        lock.lock()
        let shouldStop = handlers.isEmpty && isRecording
        if shouldStop {
            isRecording = false
        }
        lock.unlock()
        if shouldStop {
            teardownTapGraph()
        }
    }

    private func createTapGraph() throws {
        if #available(macOS 14.2, *) {
            let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            tap.name = "QuartzNotch System Audio"
            tap.isPrivate = true
            tap.muteBehavior = .unmuted
            tapDescription = tap

            var localTapID = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateProcessTap(tap, &localTapID), "AudioHardwareCreateProcessTap")
            tapID = localTapID

            let aggregateUID = "QuartzNotch.SystemAudio.\(UUID().uuidString)"
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "QuartzNotch System Audio",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tap.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            var localAggID = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &localAggID), "AudioHardwareCreateAggregateDevice")
            aggregateDeviceID = localAggID

            var localIOProcID: AudioDeviceIOProcID?
            try check(AudioDeviceCreateIOProcIDWithBlock(&localIOProcID, aggregateDeviceID, queue) { [weak self] _, inputData, _, _, _ in
                self?.handle(inputData: inputData)
            }, "AudioDeviceCreateIOProcIDWithBlock")
            ioProcID = localIOProcID

            try check(AudioDeviceStart(aggregateDeviceID, ioProcID), "AudioDeviceStart")
        } else {
            throw NSError(
                domain: "QuartzNotch.AudioWaveformEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "System audio tap requires macOS 14.2+"]
            )
        }
    }

    private func teardownTapGraph() {
        if #available(macOS 14.2, *) {
            if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
            }
            if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
                AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            }
            ioProcID = nil
            if aggregateDeviceID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
                aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            }
            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
                tapID = AudioObjectID(kAudioObjectUnknown)
            }
        }
        tapDescription = nil
    }

    private func handle(inputData: UnsafePointer<AudioBufferList>) {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        let shouldDeliver = !handlers.isEmpty && now - lastDeliveryTime >= deliveryInterval
        if shouldDeliver {
            lastDeliveryTime = now
        }
        lock.unlock()
        guard shouldDeliver else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        var channelBuffers: [UnsafeBufferPointer<Float>] = []
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }
            let pointer = data.assumingMemoryBound(to: Float.self)
            channelBuffers.append(UnsafeBufferPointer(start: pointer, count: min(sampleCount, 4096)))
        }
        guard let frameCount = channelBuffers.map(\.count).min(), frameCount > 0 else { return }
        if mixBuffer.count != frameCount {
            mixBuffer = Array(repeating: 0, count: frameCount)
        } else {
            vDSP_vclr(&mixBuffer, 1, vDSP_Length(frameCount))
        }
        for channelBuffer in channelBuffers {
            guard let baseAddress = channelBuffer.baseAddress else { continue }
            vDSP_vadd(mixBuffer, 1, baseAddress, 1, &mixBuffer, 1, vDSP_Length(frameCount))
        }
        var channelCount = Float(channelBuffers.count)
        vDSP_vsdiv(mixBuffer, 1, &channelCount, &mixBuffer, 1, vDSP_Length(frameCount))
        let samples = mixBuffer
        lock.lock()
        let currentHandlers = Array(handlers.values)
        lock.unlock()
        currentHandlers.forEach { $0(samples) }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw NSError(
                domain: "QuartzNotch.SystemAudioRecorder",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "\(operation) failed with OSStatus \(status)"]
            )
        }
    }
}

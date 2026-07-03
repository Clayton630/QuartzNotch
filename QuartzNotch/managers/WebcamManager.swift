import AVFoundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

class WebcamManager: NSObject, ObservableObject {
    static let shared = WebcamManager()
    
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var photoCaptureDelegates: [PhotoCaptureDelegate] = []
    @Published var isSessionRunning: Bool = false
    
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    
    @Published var cameraAvailable: Bool = false

    private let sessionQueue = DispatchQueue(label: "QuartzNotch.WebcamManager.SessionQueue", qos: .userInitiated)
    
    private var isCleaningUp: Bool = false
    
  // MARK: - Constants
    
    enum WebcamError: Error, LocalizedError {
        case deviceUnavailable
        case accessDenied
        case configurationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .deviceUnavailable:
                return "No camera devices available"
            case .accessDenied:
                return "Camera access denied"
            case .configurationFailed(let message):
                return "Camera configuration failed: \(message)"
            }
        }
    }
    
  // MARK: - Properties
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasDisconnected), name: .AVCaptureDeviceWasDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceWasConnected), name: .AVCaptureDeviceWasConnected, object: nil)
        refreshVideoAuthorizationStatus()
        checkCameraAvailability()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
        }
        captureSession = nil
            
        previewLayer = nil
    }

  // MARK: - Camera Management

  /// Reads current camera authorization status without prompting the system dialog.
    func refreshVideoAuthorizationStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
  /// Checks current authorization status and requests access if needed
    func checkAndRequestVideoAuthorization() {
        refreshVideoAuthorizationStatus()
        let status = authorizationStatus
        
        switch status {
        case .authorized:
            checkCameraAvailability() // Check availability if authorized
        case .notDetermined:
            requestVideoAccess()
        case .denied, .restricted:
            NSLog("Camera access denied or restricted")
        @unknown default:
            NSLog("Unknown authorization status")
        }
    }
    
  /// Requests access to the camera
    private func requestVideoAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
                if granted {
                    self?.checkCameraAvailability() // Check availability if access granted
                }
            }
        }
    }
    
  /// Checks if any camera devices are available and sets up capture session if needed
    func checkCameraAvailability() {
        let availableDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        let hasAvailableDevices = !availableDevices.isEmpty
        
        DispatchQueue.main.async {
            self.cameraAvailable = hasAvailableDevices
        }
    }
    
  /// Sets up the capture session with a completion handler
    private func setupCaptureSession(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { 
                completion(false)
                return 
            }
            
            self.cleanupExistingSession()
            
            let session = AVCaptureSession()
            
            do {
                let discoverySession = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.external, .builtInWideAngleCamera],
                    mediaType: .video,
                    position: .unspecified
                )
                
                guard let videoDevice = discoverySession.devices.first else {
                    NSLog("No video devices available")
                    DispatchQueue.main.async {
                        self.isSessionRunning = false
                        self.cameraAvailable = false
                    }
                    completion(false)
                    return
                }
                
                NSLog("Using camera: \(videoDevice.localizedName)")
                
                try videoDevice.lockForConfiguration()
                defer { videoDevice.unlockForConfiguration() }
                
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                guard session.canAddInput(videoInput) else {
                    throw NSError(domain: "QuartzNotch.WebcamManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
                }
                
                session.beginConfiguration()
                session.sessionPreset = .high
                session.addInput(videoInput)
                
                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.setSampleBufferDelegate(nil, queue: nil)
                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                }

                let photoOutput = AVCapturePhotoOutput()
                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                    self.photoOutput = photoOutput
                } else {
                    self.photoOutput = nil
                }

                session.commitConfiguration()
                
                self.captureSession = session
                
                DispatchQueue.main.async {
                    self.cameraAvailable = true
                    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                    previewLayer.videoGravity = .resizeAspectFill
                    self.previewLayer = previewLayer
                    
                    completion(true)
                }
                
                NSLog("Capture session setup completed successfully")
            } catch {
                NSLog("Failed to setup capture session: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                    self.cameraAvailable = false
                    self.previewLayer = nil
                }
                completion(false)
            }
        }
    }
    
  /// Cleans up an existing capture session, removing all inputs and outputs
    private func cleanupExistingSession() {
        if let existingSession = self.captureSession {
            if existingSession.isRunning {
                existingSession.stopRunning()
            }
            
            existingSession.beginConfiguration()
            
            for input in existingSession.inputs {
                existingSession.removeInput(input)
            }
            for output in existingSession.outputs {
                existingSession.removeOutput(output)
            }
            
            existingSession.commitConfiguration()
            self.captureSession = nil
            self.photoOutput = nil
            self.photoCaptureDelegates.removeAll()
            
            DispatchQueue.main.async {
                self.previewLayer = nil
            }
        }
    }

    @objc private func deviceWasDisconnected(notification: Notification) {
        NSLog("Camera device was disconnected")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.stopSession()
            DispatchQueue.main.async {
                self.cameraAvailable = false
            }
        }
    }

    @objc private func deviceWasConnected(notification: Notification) {
        NSLog("Camera device was connected")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.checkCameraAvailability()
        }
    }

    private func updateSessionState() {
        let isRunning = self.captureSession?.isRunning ?? false
        DispatchQueue.main.async {
            self.isSessionRunning = isRunning
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession == nil {
                self.setupCaptureSession { success in
                    if success {
                        self.startRunningCaptureSession()
                    }
                }
            } else {
                self.startRunningCaptureSession()
            }
        }
    }
    
    private func startRunningCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession, !session.isRunning else {
                return
            }
            
            session.startRunning()
            
            self.updateSessionState()
            
            NSLog("Capture session started successfully")
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
            
            self.cleanupExistingSession()
            
            NSLog("Capture session stopped and cleaned up")
        }
    }


    func capturePhotoToDesktop(completion: ((Result<URL, Error>) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let photoOutput = self.photoOutput else {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "QuartzNotch.WebcamManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Photo capture output unavailable"])))
                }
                return
            }

            let settings = AVCapturePhotoSettings()

            var delegate: PhotoCaptureDelegate?
            delegate = PhotoCaptureDelegate { [weak self] result in
                DispatchQueue.main.async {
                    completion?(result)
                }
                guard let delegate else { return }
                self?.sessionQueue.async {
                    self?.photoCaptureDelegates.removeAll { $0 === delegate }
                }
            }

            if let delegate {
                self.photoCaptureDelegates.append(delegate)
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

    private func mirroredJPEGData(from data: Data) throws -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.translateBy(x: CGFloat(width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let mirrored = context.makeImage(),
              let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, mirrored, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<URL, Error>) -> Void

    init(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(NSError(domain: "QuartzNotch.WebcamManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unable to generate photo data"])))
            return
        }

        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let fileURL = desktopURL.appendingPathComponent("QuartzNotch Capture \(formatter.string(from: Date())).jpg")

        do {
            let outputData = try mirroredJPEGData(from: data) ?? data
            try outputData.write(to: fileURL, options: .atomic)
            completion(.success(fileURL))
        } catch {
            completion(.failure(error))
        }
    }

}

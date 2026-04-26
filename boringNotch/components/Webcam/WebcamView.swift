
import AVFoundation
import Defaults
import SwiftUI

struct CameraPreviewView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager: WebcamManager
    @Default(.cameraPreviewClickAction) private var cameraPreviewClickAction

    @State private var isRequestingAuthorization: Bool = false
    @State private var photoCaptureErrorMessage: String?
    @State private var captureFlashVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewLayer = webcamManager.previewLayer {
                    CameraPreviewLayerView(previewLayer: previewLayer)
                        .scaleEffect(x: -1, y: 1)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 22
                            )
                        )
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.width
                        )
                        .opacity(webcamManager.isSessionRunning ? 1 : 0)
                }



                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.98),
                                .white.opacity(0.88),
                                .white.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(captureFlashVisible ? 1.0 : 0.965)
                    .opacity(captureFlashVisible ? 1 : 0)
                    .blur(radius: captureFlashVisible ? 0 : 6)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.22), value: captureFlashVisible)

                if !webcamManager.isSessionRunning {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: (!Defaults[.cornerRadiusScaling]
                                ? MusicPlayerImageSizes.cornerRadiusInset.closed
                                : 12)
                        )
                        .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.width
                        )

                        VStack(spacing: 8) {
                            Image(
                                systemName: webcamManager.authorizationStatus == .denied
                                ? "exclamationmark.triangle"
                                : "web.camera"
                            )
                            .foregroundStyle(.gray)
                            .font(.system(size: geometry.size.width / 3.5))

                            Text(
                                webcamManager.authorizationStatus == .denied
                                ? "Access Denied"
                                : "Mirror"
                            )
                            .font(.caption2)
                            .foregroundColor(.gray)
                        }
                    }
                }
            }
            .onTapGesture {
                handleCameraTap()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .alert("Capture failed", isPresented: Binding(get: { photoCaptureErrorMessage != nil }, set: { if !$0 { photoCaptureErrorMessage = nil } })) {
            Button("OK") { photoCaptureErrorMessage = nil }
        } message: {
            Text(photoCaptureErrorMessage ?? "")
        }
    }



    private func playCaptureFlash() {
        withAnimation(.easeOut(duration: 0.08)) {
            captureFlashVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.24)) {
                captureFlashVisible = false
            }
        }
    }

    private func handleCameraTap() {
        if isRequestingAuthorization {
            return
        }

        webcamManager.refreshVideoAuthorizationStatus()

        switch webcamManager.authorizationStatus {
        case .authorized:
            guard webcamManager.isSessionRunning else { return }
            switch cameraPreviewClickAction {
            case .none:
                return
            case .closePreview:
                vm.toggleCameraPreview()
            case .capturePhoto:
                webcamManager.capturePhotoToDesktop { result in
                    switch result {
                    case .success:
                        playCaptureFlash()
                    case let .failure(error):
                        photoCaptureErrorMessage = error.localizedDescription
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                let alert = NSAlert()
                let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
                appIcon.size = NSSize(width: 64, height: 64)
                alert.icon = appIcon
                alert.messageText = "Camera Access Required"
                alert.informativeText =
                "Please allow camera access in System Settings to use the mirror feature."
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let settingsURL = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
                    ) {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
            }
        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isRequestingAuthorization = false
            }
        @unknown default:
            break
        }
    }
}

struct CameraPreviewLayerView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = nsView.bounds
        CATransaction.commit()
    }
}

#Preview {
    CameraPreviewView(webcamManager: .shared)
        .environmentObject(BoringViewModel())
}

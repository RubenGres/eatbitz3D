import SwiftUI
import Foundation
import SceneKit
import AVFoundation
import CoreMotion

struct BitzoneView: View {
    @State private var fov: Double = 80

    var body: some View {
        ZStack(alignment: .bottom) {
            BitzonePlayerView(fov: $fov)
                .edgesIgnoringSafeArea(.all)

            // Simple testing slider overlay for FOV
            VStack(spacing: 8) {
                HStack {
                    Text("FOV: \(Int(fov))°")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                .padding(.horizontal)

                HStack {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.white)
                    Slider(value: $fov, in: 35...100, step: 1)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.white)
                }
                .padding()
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
}

struct BitzonePlayerView: UIViewControllerRepresentable {
    @Binding var fov: Double

    func makeUIViewController(context: Context) -> BitzoneViewController {
        let controller = BitzoneViewController()
        controller.setFOV(Float(fov))
        return controller
    }

    func updateUIViewController(_ uiViewController: BitzoneViewController, context: Context) {
        uiViewController.setFOV(Float(fov))
    }
}

class BitzoneViewController: UIViewController {
    private var sceneView: SCNView!
    private var cameraNode: SCNNode!
    private var videoNode: SCNNode!
    private var player: AVPlayer!  // Changed from AVQueuePlayer to reduce memory
    private var motionManager: CMMotionManager!
    private var healthCheckTimer: Timer?
    private var playerObserver: Any?

    // Force landscape orientation
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }

    override var shouldAutorotate: Bool {
        return false  // Lock rotation
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        print("🚀 BitzoneViewController viewDidLoad called")

        // CRITICAL: Disable idle timer to prevent sleep
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Set background to black
        view.backgroundColor = .black

        // Setup scene first (lightweight)
        setupScene()
        setupCamera()
        
        // Delay video setup by 3 seconds to let system stabilize after reboot
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.setupVideoSphere()
            self?.setupMotionTracking()
            self?.startHealthCheck()
        }

        // Add lifecycle observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkVideoHealth()
        }
    }

    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received")
        // Force garbage collection
        autoreleasepool {
            // Don't recreate player on memory warning - that uses MORE memory
            // Just ensure current playback continues
            if player?.rate == 0 {
                player?.play()
            }
        }
    }

    private func checkVideoHealth() {
        guard let player = player else {
            setupVideoSphere()
            return
        }

        if player.rate == 0 {
            player.play()
        }
        
        if player.currentItem?.status == .failed {
            recreateVideoPlayer()
        }
    }

    private func recreateVideoPlayer() {
        // Clean up old player first
        playerObserver.map { NotificationCenter.default.removeObserver($0) }
        player?.pause()
        player = nil
        videoNode?.removeFromParentNode()
        videoNode = nil
        
        // Small delay before recreating to let memory settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.setupVideoSphere()
        }
    }

    private func setupScene() {
        sceneView = SCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.backgroundColor = .black
        sceneView.allowsCameraControl = false
        sceneView.antialiasingMode = .none  // Reduce memory
        
        let scene = SCNScene()
        sceneView.scene = scene
        view.addSubview(sceneView)
    }

    private func setupCamera() {
        let camera = SCNCamera()

        cameraNode = SCNNode()
        cameraNode.camera = camera
        setFOV(Float(80))

        sceneView.scene?.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode
    }

    public func setFOV(_ newValue: Float) {
        let clamped = max(30, min(110, newValue))
        if Thread.isMainThread {
            cameraNode?.camera?.fieldOfView = CGFloat(clamped)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.cameraNode?.camera?.fieldOfView = CGFloat(clamped)
            }
        }
    }

    private func setupVideoSphere() {
        // Use lower segment count to reduce memory
        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 96  // Reduced from 300 to save memory

        videoNode = SCNNode(geometry: sphere)
        videoNode.position = SCNVector3(0, 0, 0)
        videoNode.scale = SCNVector3(-1, 1, 1)

        let fm = FileManager.default
        let candidateURL: URL
        if fm.fileExists(atPath: VideoStore.localVideoURL.path) {
            candidateURL = VideoStore.localVideoURL
        } else if let bundled = VideoStore.bundledVideoURL() {
            candidateURL = bundled
        } else {
            print("❌ Video not found (neither documents nor bundle)")
            return
        }

        // Create player with memory-efficient settings
        let asset = AVAsset(url: candidateURL)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Reduce buffer size to save memory
        playerItem.preferredForwardBufferDuration = 2.0
        
        player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false  // Reduce memory buffering
        player.preventsDisplaySleepDuringVideoPlayback = true

        // Loop video using notification instead of AVPlayerLooper (uses less memory)
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }

        let material = SCNMaterial()
        material.diffuse.contents = player
        material.isDoubleSided = true
        sphere.materials = [material]

        sceneView.scene?.rootNode.addChildNode(videoNode)

        // Start playback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.player?.play()
        }
    }

    private func setupMotionTracking() {
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0  // 30fps instead of 60 to reduce CPU

        guard motionManager.isDeviceMotionAvailable else { return }

        // Use xArbitraryCorrectedZVertical for gravity reference with yaw tracking
        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] (motion, _) in
            guard let motion = motion, let self = self else { return }

            let pitch = Float(motion.attitude.pitch)
            let roll = Float(motion.attitude.roll)
            let yaw = Float(motion.attitude.yaw)

            // For landscape phone held upright:
            // - yaw: user turns body left/right -> look left/right (main rotation)
            // - pitch: tilt phone up/down -> look up/down
            // - roll: minor adjustment
            self.cameraNode.eulerAngles = SCNVector3(
                pitch,           // Up/down look (tilt phone)
                yaw,             // Left/right look (turn body)
                0                // No camera roll
            )
        }
    }

    @objc private func appWillEnterForeground() {
        UIApplication.shared.isIdleTimerDisabled = true
        if player?.rate == 0 {
            player?.play()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    deinit {
        healthCheckTimer?.invalidate()
        playerObserver.map { NotificationCenter.default.removeObserver($0) }
        motionManager?.stopDeviceMotionUpdates()
        NotificationCenter.default.removeObserver(self)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}


import SwiftUI
import Foundation
import SceneKit
import AVFoundation
import CoreMotion

struct BitzoneView: View {
    @State private var fov: Double = 45
    @ObservedObject var videoUpdater: VideoUpdater

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

            // Download progress overlay
            if videoUpdater.isDownloading {
                ZStack {
                    Color.black.opacity(0.85)
                        .edgesIgnoringSafeArea(.all)

                    VStack(spacing: 20) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white)

                        Text(videoUpdater.statusMessage)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 10)

                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: max(0, geo.size.width * CGFloat(videoUpdater.progress)),
                                        height: 10
                                    )
                                    .animation(.easeOut(duration: 0.3), value: videoUpdater.progress)
                            }
                        }
                        .frame(height: 10)
                        .frame(maxWidth: 300)

                        Text("\(Int(videoUpdater.progress * 100))%")
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: videoUpdater.isDownloading)
        .onReceive(videoUpdater.$remoteFOV) { newFOV in
            fov = newFOV
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
    private var player: AVPlayer!
    private var motionManager: CMMotionManager!
    private let motionQueue = OperationQueue()
    private var healthCheckTimer: Timer?
    private var playerObserver: Any?
    private var videoUpdateObserver: Any?
    
    // Energy management
    private var lastMotionTime: Date = Date()
    private var isIdle: Bool = false
    private var _isSleeping: Bool = false
    private let stateLock = NSLock()
    private var isSleeping: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isSleeping }
        set { stateLock.lock(); defer { stateLock.unlock() }; _isSleeping = newValue }
    }
    // Track start of motion for "pick up" detection
    private var motionStartDate: Date?
    private let idleThreshold: TimeInterval = 30.0  // 30 seconds to idle (10 FPS)
    private let sleepThreshold: TimeInterval = 60.0 // 1 minute to FULL SLEEP (Brightness 0)
    private let normalFPS: Int = 30
    private let idleFPS: Int = 10
    private let motionSensitivity: Double = 0.15 // Increased from 0.05 to prevent noise resets

    // Gyroscope tracking state
    private var initialYaw: Float?
    private let maxPitchAngle: Float = 60.0 * (.pi / 180.0)  // ±60° vertical clamp

    // Force landscape orientation
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }

    override var shouldAutorotate: Bool {
        return false
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

        // Listen for video update notifications to hot-reload the video
        videoUpdateObserver = NotificationCenter.default.addObserver(
            forName: .videoDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[BitzoneViewController] 🔄 Video updated notification received – reloading video")
            self?.recreateVideoPlayer()
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
            self?.checkEnergyStatus()
        }
    }

    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received")
        autoreleasepool {
            // Only try to recover playback if we are NOT sleeping
            if !isSleeping && player?.rate == 0 {
                player?.play()
            }
        }
    }

    private func checkVideoHealth() {
        // Energy Check: Don't wake up the video if we are sleeping!
        if isSleeping { return }

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
        sceneView.antialiasingMode = .none
        
        // Energy optimization: cap frame rate
        sceneView.preferredFramesPerSecond = normalFPS
        
        let scene = SCNScene()
        sceneView.scene = scene
        view.addSubview(sceneView)
    }

    private func setupCamera() {
        let camera = SCNCamera()

        cameraNode = SCNNode()
        cameraNode.camera = camera
        setFOV(Float(45))

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
        let sphere = SCNSphere(radius: 10)
        // Reduced complexity for energy savings (was 96)
        sphere.segmentCount = 64

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

        let asset = AVAsset(url: candidateURL)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 2.0
        
        player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = true

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.player?.play()
        }
    }

    private func setupMotionTracking() {
        // Re-enabled motion tracking with safety guards for testing
        motionManager = CMMotionManager()
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

        guard motionManager.isDeviceMotionAvailable else { return }

        // Reset initial yaw so forward direction is calibrated on start
        initialYaw = nil
        motionStartDate = nil

        motionQueue.maxConcurrentOperationCount = 1
        motionQueue.name = "com.bitzone.motionUpdates"

        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: motionQueue) { [weak self] (motion, _) in
            guard let motion = motion, let self = self else { return }

            let rawYaw   = Float(motion.attitude.yaw)
            let gravity  = motion.gravity
            let accel    = motion.userAcceleration

            // Safety check for NaN or Infinity in any input
            guard gravity.z.isFinite, rawYaw.isFinite else { return }

            // --- Capture Initial Yaw ---
            if self.initialYaw == nil {
                self.initialYaw = rawYaw
            }

            // --- Energy & Wake Up Logic ---
            let totalAccel = abs(accel.x) + abs(accel.y) + abs(accel.z)
            let currentlySleeping = self.isSleeping // Thread-safe read

            if currentlySleeping {
                // Wake Up Logic: Require 0.5s of continuous movement to avoid accidental wakes
                if totalAccel > self.motionSensitivity {
                    if let start = self.motionStartDate {
                        if Date().timeIntervalSince(start) >= 0.5 {
                            // Valid sustained movement -> Wake up!
                            DispatchQueue.main.async { self.handleUserActivity() }
                            self.motionStartDate = nil // Reset
                        }
                    } else {
                        // Start tracking movement
                        self.motionStartDate = Date()
                    }
                } else {
                    // Movement stopped before threshold -> Reset
                    self.motionStartDate = nil
                }
                
                // If sleeping, do NOT update camera (save energy)
                return
            } else {
                // Not sleeping: Reset wake-up timer
                self.motionStartDate = nil
                
                // Reset idle timer on significant movement
                if totalAccel > self.motionSensitivity {
                    DispatchQueue.main.async { self.handleUserActivity() }
                }
            }

            // Mapping: asin(gravity.z) directly gives the latitude sign.
            // Safety: clamp gravity.z to [-1, 1] to avoid NaN from asin() during sudden impacts
            let verticalAngle = Float(asin(max(-1.0, min(1.0, gravity.z))))
            let clampedVertical = max(-self.maxPitchAngle, min(self.maxPitchAngle, verticalAngle))
            let currentYaw = rawYaw - (self.initialYaw ?? 0)

            // Update camera on main thread
            DispatchQueue.main.async {
                self.cameraNode.eulerAngles = SCNVector3(clampedVertical, currentYaw, 0)
            }
        }
        print("🛠 DEBUG: Motion tracking RE-ENABLED with safety guards.")
    }

    @objc private func appWillEnterForeground() {
        UIApplication.shared.isIdleTimerDisabled = true
        handleUserActivity()
        
        // Re-calibrate yaw on foreground return
        initialYaw = nil
        if player?.rate == 0 {
            player?.play()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    // MARK: - Energy Management

    private func handleUserActivity() {
        let now = Date()
        
        if isSleeping {
            print("[Energy] 🌅 Waking up from Deep Sleep")
            isSleeping = false
            isIdle = false
            UIScreen.main.brightness = 0.6
            sceneView.isHidden = false
            sceneView.isPlaying = true
            sceneView.preferredFramesPerSecond = normalFPS
            player?.play()
            lastMotionTime = now
            return
        }

        // Only log if it's been more than 5 seconds since last reset to avoid spam
        if now.timeIntervalSince(lastMotionTime) > 5.0 {
            print("[Energy] ⚡️ Activity detected (timer reset)")
        }
        lastMotionTime = now
        
        if isIdle {
            print("[Energy] 🔋 Restoring normal performance (30 FPS)")
            isIdle = false
            sceneView.preferredFramesPerSecond = normalFPS
        }
    }

    private func checkEnergyStatus() {
        let elapsed = Date().timeIntervalSince(lastMotionTime)
        
        if !isSleeping && elapsed > sleepThreshold {
            print("[Energy] 💤 Entering Deep Sleep (Display OFF)")
            isSleeping = true
            isIdle = false
            
            // 1. Kill brightness to save screen/battery
            UIScreen.main.brightness = 0.0
            
            // 2. Hide content and stop all processing
            sceneView.isHidden = true
            player?.pause()
            sceneView.isPlaying = false
            
            sceneView.preferredFramesPerSecond = 1
            return
        }
        
        if !isIdle && !isSleeping && elapsed > idleThreshold {
            print("[Energy] 🌙 Entering Low Energy Mode (10 FPS)")
            isIdle = true
            sceneView.preferredFramesPerSecond = idleFPS
        }
    }

    deinit {
        healthCheckTimer?.invalidate()
        playerObserver.map { NotificationCenter.default.removeObserver($0) }
        videoUpdateObserver.map { NotificationCenter.default.removeObserver($0) }
        motionManager?.stopDeviceMotionUpdates()
        NotificationCenter.default.removeObserver(self)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

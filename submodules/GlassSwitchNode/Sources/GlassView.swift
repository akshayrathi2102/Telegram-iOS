import UIKit
import MetalKit

/// A reusable Metal-based view that renders a liquid glass effect with distortion, blur, and edge effects.
///
/// Usage:
/// ```swift
/// // Simple usage
/// let glassView = GlassView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
/// view.addSubview(glassView)
///
/// // With configuration
/// let config = GlassView.Configuration(
///     cornerRadius: 30,
///     blurRadius: 0.5,
///     distortionStrength: 0.15
/// )
/// let glassView = GlassView(frame: frame, configuration: config)
///
/// // Modify at runtime
/// glassView.cornerRadius = 50
/// glassView.isActive = false  // Pause to save performance
/// ```
public class GlassView: UIView, MTKViewDelegate {
    
    // MARK: - Configuration
    
    /// Configuration options for GlassView
    public struct Configuration {
        /// Corner radius of the glass shape (0 = sharp rectangle)
        public var cornerRadius: Float
        
        /// Padding factor for background capture (0.25 = 25% padding on each side)
        public var paddingFactor: Float
        
        /// Distortion/magnification strength (0 = none, 0.15 = subtle, 0.5 = strong)
        public var distortionStrength: Float
        
        /// Blur radius for the glass effect
        public var blurRadius: Float
        
        /// Whether the glass effect should start active
        public var isActive: Bool
        
        /// Shadow direction - where the shadow is cast from
        /// x: positive = right, negative = left
        /// y: positive = down, negative = up
        /// e.g., (0.5, -0.7) = upper-right (shadow appears on upper-right edge)
        public var shadowDirection: SIMD2<Float>
        
        /// Multiplier for center minification (default 5.0 - higher = stronger shrink in center)
        public var minifyMultiplier: Float

        /// Multiplier for edge magnification (default 1.0 - higher = stronger magnify at edges)
        public var magnifyMultiplier: Float

        /// Threshold where minification transitions to magnification (0.0-1.0, default 0.5)
        /// Lower value = more area for magnification, higher value = more area for minification
        public var distortionThreshold: Float

        /// Default configuration
        public static let `default` = Configuration(
            cornerRadius: 20,
            paddingFactor: 0.25,
            distortionStrength: 0.50,
            blurRadius: 0.5,
            isActive: true,
            shadowDirection: SIMD2<Float>(0.7, -0.7),
            minifyMultiplier: 5.0,
            magnifyMultiplier: 1.0,
            distortionThreshold: 0.5
        )
        
        /// Subtle glass effect
        public static let subtle = Configuration(
            cornerRadius: 20,
            paddingFactor: 0.25,
            distortionStrength: 0.08,
            blurRadius: 0.3,
            isActive: true,
            shadowDirection: SIMD2<Float>(0.7, -0.7),
            minifyMultiplier: 5.0,
            magnifyMultiplier: 1.0,
            distortionThreshold: 0.5
        )
        
        /// Strong glass effect
        public static let strong = Configuration(
            cornerRadius: 20,
            paddingFactor: 0.25,
            distortionStrength: 0.25,
            blurRadius: 0.8,
            isActive: true,
            shadowDirection: SIMD2<Float>(0.7, -0.7),
            minifyMultiplier: 5.0,
            magnifyMultiplier: 1.0,
            distortionThreshold: 0.5
        )

        /// Configuration for slider thumb
        public static let sliderThumb = Configuration(
            cornerRadius: 12,
            paddingFactor: 0.25,
            distortionStrength: 0.15,
            blurRadius: 0.15,
            isActive: true,
            shadowDirection: SIMD2<Float>(0.7, -0.7),
            minifyMultiplier: 2.0,
            magnifyMultiplier: 3.0,
            distortionThreshold: 0.5
        )

        /// Configuration for switch thumb
        public static let switchThumb = Configuration(
            cornerRadius: 12,
            paddingFactor: 0.25,
            distortionStrength: 0.15,
            blurRadius: 0.15,
            isActive: false,
            shadowDirection: SIMD2<Float>(0.7, -0.7),
            minifyMultiplier: 5.0,
            magnifyMultiplier: 1.0,
            distortionThreshold: 0.5
        )

        /// Configuration for tab bar thumb (same as switch)
        public static let tabBarThumb = Configuration(
            cornerRadius: 12,
            paddingFactor: 0.25,
            distortionStrength: 0.15,
            blurRadius: 0.15,
            isActive: false,
            shadowDirection: SIMD2<Float>(0.7, -0.7),
            minifyMultiplier: 2.5,
            magnifyMultiplier: 0.2,
            distortionThreshold: 0.7
        )

        public init(
            cornerRadius: Float = 20,
            paddingFactor: Float = 0.25,
            distortionStrength: Float = 0.15,
            blurRadius: Float = 0.2,
            isActive: Bool = true,
            shadowDirection: SIMD2<Float> = SIMD2<Float>(0.7, -0.7),
            minifyMultiplier: Float = 5.0,
            magnifyMultiplier: Float = 1.0,
            distortionThreshold: Float = 0.5
        ) {
            self.cornerRadius = cornerRadius
            self.paddingFactor = paddingFactor
            self.distortionStrength = distortionStrength
            self.blurRadius = blurRadius
            self.isActive = isActive
            self.shadowDirection = shadowDirection
            self.minifyMultiplier = minifyMultiplier
            self.magnifyMultiplier = magnifyMultiplier
            self.distortionThreshold = distortionThreshold
        }
    }
    
    // MARK: - Public Properties
    
    /// The current configuration (read-only, use `configure(_:)` to update)
    public private(set) var configuration: Configuration = .default
    
    /// Controls whether the glass effect is actively rendering (set to false to save performance)
    public var isActive: Bool = true {
        didSet {
            mtkView?.isPaused = !isActive
            if isActive {
                captureBackground()
            }
        }
    }

    /// Corner radius of the glass shape (0 = sharp rectangle)
    public var cornerRadius: Float = 20 {
        didSet {
            if isActive { mtkView?.setNeedsDisplay() }
        }
    }
    
    /// Padding factor for background capture (0.25 = 25% padding on each side)
    public var paddingFactor: Float = 0.25 {
        didSet {
            if isActive {
                captureBackground()
                mtkView?.setNeedsDisplay()
            }
        }
    }
    
    /// Distortion/magnification strength (0 = none, higher = more magnification)
    public var distortionStrength: Float = 0.15 {
        didSet {
            if isActive { mtkView?.setNeedsDisplay() }
        }
    }
    
    /// Blur radius for the glass effect
    public var blurRadius: Float = 0.2 {
        didSet {
            if isActive { mtkView?.setNeedsDisplay() }
        }
    }
    
    /// Shadow direction - where the shadow is cast from
    /// x: positive = right, negative = left
    /// y: positive = down, negative = up
    /// e.g., (0.7, -0.7) = upper-right (shadow appears on upper-right edge)
    public var shadowDirection: SIMD2<Float> = SIMD2<Float>(0.7, -0.7) {
        didSet {
            if isActive { mtkView?.setNeedsDisplay() }
        }
    }
    
    /// Multiplier for center minification (default 5.0 - higher = stronger shrink in center)
    public var minifyMultiplier: Float = 5.0 {
        didSet {
            if isActive { mtkView?.setNeedsDisplay() }
        }
    }

    /// Multiplier for edge magnification (default 1.0 - higher = stronger magnify at edges)
    public var magnifyMultiplier: Float = 1.0 {
        didSet {
            if isActive { mtkView?.setNeedsDisplay() }
        }
    }

    /// Threshold where minification transitions to magnification (0.0-1.0, default 0.5)
    public var distortionThreshold: Float = 0.5 {
        didSet {
            if isActive { mtkView?.setNeedsDisplay() }
        }
    }

    // MARK: - Private Properties
    
    private var mtkView: MTKView?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var textureLoader: MTKTextureLoader?
    private var backgroundTexture: MTLTexture?
    
    /// Fallback view when Metal is not available
    private var fallbackView: UIView?
    private var metalSetupSucceeded = false
    
    // MARK: - Init
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    /// Initialize with a configuration
    public convenience init(frame: CGRect, configuration: Configuration) {
        self.init(frame: frame)
        configure(configuration)
    }
    
    private func commonInit() {
        clipsToBounds = false
        layer.masksToBounds = false
        setupMetal()
    }
    
    // MARK: - Public Methods
    
    /// Apply a configuration to the glass view
    public func configure(_ config: Configuration) {
        self.configuration = config
        self.cornerRadius = config.cornerRadius
        self.paddingFactor = config.paddingFactor
        self.distortionStrength = config.distortionStrength
        self.blurRadius = config.blurRadius
        self.isActive = config.isActive
        self.shadowDirection = config.shadowDirection
        self.minifyMultiplier = config.minifyMultiplier
        self.magnifyMultiplier = config.magnifyMultiplier
        self.distortionThreshold = config.distortionThreshold
    }
    
    /// Force a refresh of the glass effect
    public func refresh() {
        captureBackground()
        mtkView?.setNeedsDisplay()
    }
    
    // MARK: - Wobble Animation (Momentum-based)
    
    /// Axis constraint for wobble animation
    public enum WobbleAxis {
        case both       // Consider velocity on both axes (default)
        case horizontal // Only consider horizontal velocity (for horizontal sliders)
        case vertical   // Only consider vertical velocity (for vertical sliders)
    }
    
    /// Which axis to consider for wobble animation (default: .both)
    public var wobbleAxis: WobbleAxis = .both
    
    private var wobbleDisplayLink: CADisplayLink?
    private var isWobbling: Bool = false
    
    // Momentum-based wobble state
    private var currentMomentum: CGFloat = 0       // Current wobble intensity (0-1)
    private var targetMomentum: CGFloat = 0        // Target based on velocity
    private var momentumVelocity: CGFloat = 0      // Spring velocity for oscillation
    
    // Spring physics constants (tweaked for more bounce)
    private let springStiffness: CGFloat = 120     // Lower = more fluid, sloshy movement
    private let springDamping: CGFloat = 4         // Low = bouncy oscillations
    private let maxWobble: CGFloat = 0.10          // Maximum deformation (10%)
    
    /// Start wobble animation (call when drag/interaction begins)
    public func startWobble() {
        guard !isWobbling else { return }
        isWobbling = true
        currentMomentum = 0
        targetMomentum = 0
        momentumVelocity = 0
        
        // Start the display link for smooth animation
        startWobbleDisplayLink()
        
        // Initial bounce on pickup with randomness
        let randomKick = CGFloat.random(in: 0.4...0.7)
        targetMomentum = randomKick
        momentumVelocity = CGFloat.random(in: 2...5)  // Random initial velocity for organic feel
    }
    
    /// Update wobble based on movement velocity (call during drag with velocity)
    public func updateWobble(velocity: CGPoint) {
        guard isWobbling else { return }
        
        // Apply axis filter to velocity
        var filteredVelocity = velocity
        switch wobbleAxis {
        case .horizontal:
            filteredVelocity.y = 0
        case .vertical:
            filteredVelocity.x = 0
        case .both:
            break
        }
        
        // Calculate speed and normalize to 0-1 range
        let speed = sqrt(filteredVelocity.x * filteredVelocity.x + filteredVelocity.y * filteredVelocity.y)
        
        // Set target momentum based on velocity (higher speed = more wobble)
        targetMomentum = min(speed / 600, 1.2)  // Easier to hit max, allow overshoot
        
        // Add micro-randomness for organic feel
        if speed > 100 {
            momentumVelocity += CGFloat.random(in: -0.5...0.5)
        }
    }
    
    /// Stop wobble and spring back to normal (call when drag ends)
    public func stopWobble() {
        guard isWobbling else { return }
        isWobbling = false
        edgeStretchAmount = 0
        targetEdgeStretch = 0
        
        // Set target to 0 (rest position)
        targetMomentum = 0
        
        // BIG kick when releasing - this creates the visible bounce!
        let releaseKick = currentMomentum * 15 + CGFloat.random(in: 5...10)
        momentumVelocity += releaseKick
        
        // Keep display link running until fully settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.isWobbling else { return }
            self.stopWobbleDisplayLink()
            self.transform = .identity
        }
    }
    
    // MARK: - Display Link for Smooth Animation
    
    private func startWobbleDisplayLink() {
        stopWobbleDisplayLink()
        wobbleDisplayLink = CADisplayLink(target: self, selector: #selector(wobbleFrame))
        wobbleDisplayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopWobbleDisplayLink() {
        wobbleDisplayLink?.invalidate()
        wobbleDisplayLink = nil
    }
    
    @objc private func wobbleFrame(_ displayLink: CADisplayLink) {
        let dt = CGFloat(displayLink.targetTimestamp - displayLink.timestamp)
        guard dt > 0 && dt < 0.1 else { return }  // Sanity check
        
        // Smoothly interpolate edge stretch
        let edgeSmoothing: CGFloat = 0.2
        edgeStretchAmount = edgeStretchAmount + (targetEdgeStretch - edgeStretchAmount) * edgeSmoothing
        
        // Spring physics: F = -kx - cv
        // Accelerate toward target with spring force
        let displacement = currentMomentum - targetMomentum
        let springForce = -springStiffness * displacement
        let dampingForce = -springDamping * momentumVelocity
        let acceleration = springForce + dampingForce
        
        // Integrate velocity and position
        momentumVelocity += acceleration * dt
        currentMomentum += momentumVelocity * dt
        
        // Allow negative momentum for bounce-back oscillation (compress then stretch)
        // Clamp to reasonable range to prevent extreme values
        currentMomentum = max(-0.8, min(currentMomentum, 1.5))
        
        // Combine momentum wobble and edge stretch
        // Momentum can be negative (compress) or positive (stretch)
        let wobbleAmount = currentMomentum * maxWobble
        let totalStretch = edgeStretchAmount > 0.01 ? edgeStretchAmount : wobbleAmount
        
        let scaleX: CGFloat
        let scaleY: CGFloat
        
        switch wobbleAxis {
        case .horizontal:
            // Positive = stretch horizontally, Negative = compress horizontally
            scaleX = 1.0 + totalStretch
            scaleY = 1.0 - totalStretch * 0.85
        case .vertical:
            scaleX = 1.0 - totalStretch * 0.85
            scaleY = 1.0 + totalStretch
        case .both:
            scaleX = 1.0 + totalStretch
            scaleY = 1.0 - totalStretch * 0.85
        }
        
        self.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        
        // Stop animation when settled (not wobbling and nearly at rest)
        if !isWobbling && abs(currentMomentum) < 0.005 && abs(momentumVelocity) < 0.05 && edgeStretchAmount < 0.001 {
            stopWobbleDisplayLink()
            self.transform = .identity
        }
    }
    
    // MARK: - Edge Stretch (rubber band effect at limits)
    
    private var edgeStretchAmount: CGFloat = 0
    private var targetEdgeStretch: CGFloat = 0
    private var isAtEdge: Bool = false
    
    /// Apply edge stretch when at limits and user keeps pulling
    /// Direction doesn't matter - always stretches the same way based on wobbleAxis
    /// - Parameter intensity: How hard the user is pulling (normalized, will be clamped)
    public func applyEdgeStretch(intensity: CGFloat) {
        guard isWobbling else { return }
        
        isAtEdge = true
        
        // Rubber band resistance: diminishing returns as you pull harder
        let clampedIntensity = min(abs(intensity), 1.0)
        targetEdgeStretch = 0.08 * (1 - exp(-3 * clampedIntensity))  // Max ~8% stretch
        
        // Set momentum high to maintain wobble appearance
        targetMomentum = max(targetMomentum, targetEdgeStretch / maxWobble)
    }
    
    /// Release edge stretch - momentum system handles the bounce back
    public func releaseEdgeStretch() {
        guard isAtEdge else { return }
        
        isAtEdge = false
        targetEdgeStretch = 0
        
        // Give a bounce impulse when releasing from edge
        if edgeStretchAmount > 0.05 {
            momentumVelocity += edgeStretchAmount * 8  // Bigger stretch = bigger bounce
        }
        edgeStretchAmount = 0
    }
    
    // MARK: - Setup
    
    private func setupMetal() {
        // Get Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            setupFallbackView()
            return
        }
        self.device = device
        
        // Create MTKView
        let metalView = MTKView(frame: bounds, device: device)
        metalView.delegate = self
        metalView.framebufferOnly = false
        metalView.isPaused = false  // Enable continuous rendering
        metalView.enableSetNeedsDisplay = false  // Use continuous rendering instead
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.layer.isOpaque = false
        metalView.isOpaque = false
        metalView.backgroundColor = .clear
        // Ensure proper scaling with screen
        metalView.contentScaleFactor = UIScreen.main.scale
        metalView.autoResizeDrawable = true
        // Use autoresizing to fill parent
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView = metalView
        addSubview(metalView)
        
        // Create command queue
        commandQueue = device.makeCommandQueue()
        
        // Load shader library from resource bundle - try multiple locations
        var library: MTLLibrary?
        let mainBundle = Bundle(for: GlassView.self)
        
        // Try 1: Look for bundle in the module's bundle
        if let path = mainBundle.path(forResource: "GlassSwitchNodeBundle", ofType: "bundle") {
            if let bundle = Bundle(path: path) {
                library = try? device.makeDefaultLibrary(bundle: bundle)
            }
        }
        
        // Try 2: Look in main app bundle
        if library == nil {
            if let path = Bundle.main.path(forResource: "GlassSwitchNodeBundle", ofType: "bundle") {
                if let bundle = Bundle(path: path) {
                    library = try? device.makeDefaultLibrary(bundle: bundle)
                }
            }
        }
        
        // Try 3: Search in all bundles
        if library == nil {
            for bundle in Bundle.allBundles {
                if let path = bundle.path(forResource: "GlassSwitchNodeBundle", ofType: "bundle"),
                   let resourceBundle = Bundle(path: path) {
                    library = try? device.makeDefaultLibrary(bundle: resourceBundle)
                    if library != nil {
                        break
                    }
                }
            }
        }
        
        // Try 4: Fallback to default library for development/testing
        if library == nil {
            library = device.makeDefaultLibrary()
        }
        
        guard let lib = library else {
            setupFallbackView()
            return
        }
        
        guard let vertexFunction = lib.makeFunction(name: "simpleVertex"),
              let fragmentFunction = lib.makeFunction(name: "simpleFragment") else {
            setupFallbackView()
            return
        }
        
        // Create render pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            setupFallbackView()
            return
        }
        pipelineState = pipeline
        
        // Create vertex buffer (full-screen quad)
        let vertices: [Float] = [
            -1, -1,  // bottom-left
             1, -1,  // bottom-right
            -1,  1,  // top-left
             1, -1,  // bottom-right
             1,  1,  // top-right
            -1,  1   // top-left
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size)
        
        // Create texture loader
        textureLoader = MTKTextureLoader(device: device)
        
        metalSetupSucceeded = true
    }
    
    private func setupFallbackView() {
        metalSetupSucceeded = false
        mtkView?.removeFromSuperview()
        mtkView = nil
        
        // Create a simple glass-like fallback view
        let fallback = UIView(frame: bounds)
        fallback.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        fallback.layer.cornerRadius = CGFloat(cornerRadius)
        fallback.clipsToBounds = false
        fallback.layer.masksToBounds = false
        
        // Add subtle border for glass edge effect
        fallback.layer.borderWidth = 0.5
        fallback.layer.borderColor = UIColor(white: 0.9, alpha: 1.0).cgColor
        
        // Add shadow for depth
        fallback.layer.shadowColor = UIColor.black.cgColor
        fallback.layer.shadowOffset = CGSize(width: 0, height: 2)
        fallback.layer.shadowRadius = 4
        fallback.layer.shadowOpacity = 0.2
        
        self.fallbackView = fallback
        addSubview(fallback)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        mtkView?.frame = bounds
        fallbackView?.frame = bounds
        fallbackView?.layer.cornerRadius = CGFloat(cornerRadius)
        if metalSetupSucceeded {
            captureBackground()
        }
    }
    
    // MARK: - Background Capture
    
    /// Find window through various methods since ASDisplayNode views may not have direct window access
    private func findWindow() -> UIWindow? {
        // Method 1: Direct window property
        if let window = self.window {
            return window
        }
        
        // Method 2: Traverse superview chain
        var currentView: UIView? = self.superview
        while let view = currentView {
            if let window = view.window {
                return window
            }
            currentView = view.superview
        }
        
        // Method 3: Key window (iOS 13+)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        
        // Method 4: Any visible window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        
        return nil
    }
    
    private func captureBackground() {
        guard let window = findWindow() else {
            return
        }
        
        // Hide self during capture (use opacity instead of isHidden to avoid layout passes)
        let wasOpacity = layer.opacity
        layer.opacity = 0
        
        // Calculate padded size (1.5x for 25% padding on each side)
        let paddedScale = CGFloat(1.0 + 2.0 * paddingFactor)
        let paddedWidth = bounds.width * paddedScale
        let paddedHeight = bounds.height * paddedScale
        
        // Convert view center to window coordinates
        // Use layer presentation to get accurate screen position
        var viewCenterInWindow: CGPoint
        if let presentationLayer = layer.presentation() {
            // Get the frame in screen coordinates through the presentation layer
            let screenPosition = presentationLayer.convert(presentationLayer.position, to: window.layer)
            viewCenterInWindow = screenPosition
        } else if self.window != nil {
            // Direct conversion if we have a window connection
            viewCenterInWindow = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        } else {
            // Fallback: traverse superview chain to calculate position
            var position = CGPoint(x: bounds.midX, y: bounds.midY)
            var currentView: UIView? = self
            while let view = currentView, view.window == nil {
                position.x += view.frame.origin.x
                position.y += view.frame.origin.y
                currentView = view.superview
            }
            if let view = currentView {
                viewCenterInWindow = view.convert(position, to: window)
            } else {
                // Last resort: use center of window
                viewCenterInWindow = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            }
        }
        
        // Calculate capture rect centered on view (in window coordinates)
        let captureRect = CGRect(
            x: viewCenterInWindow.x - paddedWidth / 2,
            y: viewCenterInWindow.y - paddedHeight / 2,
            width: paddedWidth,
            height: paddedHeight
        )
        
        // Validate capture rect
        guard captureRect.width > 0, captureRect.height > 0 else {
            layer.opacity = wasOpacity
            return
        }
        
        // Get the screen scale for proper pixel density
        let scale = window.screen.scale
        
        // OPTIMIZATION: Render ONLY the region we need (not entire window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        
        // Render just the capture region by translating the context
        let renderer = UIGraphicsImageRenderer(size: captureRect.size, format: format)
        let regionImage = renderer.image { ctx in
            // Translate context so captureRect.origin becomes (0,0)
            ctx.cgContext.translateBy(x: -captureRect.origin.x, y: -captureRect.origin.y)
            window.layer.render(in: ctx.cgContext)
        }
        
        // Restore visibility immediately
        layer.opacity = wasOpacity
        
        // Synchronous texture creation (async causes 1-2 frame lag)
        guard let device = device else {
            return
        }
        
        // Create texture directly from UIImage using Core Graphics
        // This avoids the MTKTextureLoader "Image decoding failed" issue
        let imageWidth = Int(regionImage.size.width * regionImage.scale)
        let imageHeight = Int(regionImage.size.height * regionImage.scale)
        
        guard imageWidth > 0, imageHeight > 0 else {
            return
        }
        
        // Create texture descriptor
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: imageWidth,
            height: imageHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return
        }
        
        // Create a bitmap context to render the image
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * imageWidth
        var pixelData = [UInt8](repeating: 0, count: imageHeight * bytesPerRow)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return
        }
        
        // Draw the image into the context
        context.translateBy(x: 0, y: CGFloat(imageHeight))
        context.scaleBy(x: regionImage.scale, y: -regionImage.scale)
        UIGraphicsPushContext(context)
        regionImage.draw(at: .zero)
        UIGraphicsPopContext()
        
        // Copy pixel data to texture
        let region = MTLRegionMake2D(0, 0, imageWidth, imageHeight)
        texture.replace(region: region, mipmapLevel: 0, withBytes: pixelData, bytesPerRow: bytesPerRow)
        
        backgroundTexture = texture
    }
    
    // MARK: - MTKViewDelegate
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        guard metalSetupSucceeded else { return }
        
        // Recapture background every frame for real-time updates
        captureBackground()
        
        // CRITICAL: Don't render if we don't have a background texture
        // This prevents rendering black when the view isn't in a window
        guard let backgroundTexture = backgroundTexture else {
            // Clear to semi-transparent white instead of leaving garbage
            guard let drawable = view.currentDrawable,
                  let commandQueue = commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPass = view.currentRenderPassDescriptor else { return }
            
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 0.9)
            
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                encoder.endEncoding()
            }
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        
        guard let drawable = view.currentDrawable,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let vertexBuffer = vertexBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPass = view.currentRenderPassDescriptor else { return }
        
        renderPass.colorAttachments[0].loadAction = .clear
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Pass background texture
        encoder.setFragmentTexture(backgroundTexture, index: 0)
        
        // Pass parameters to fragment shader
        // Use drawable size for proper retina scaling
        let drawableSize = view.drawableSize
        let scale = UIScreen.main.scale
        let viewWidth = Float(drawableSize.width / scale)
        let viewHeight = Float(drawableSize.height / scale)
        
        var params = Params(
            resolution: SIMD2<Float>(viewWidth, viewHeight),
            cornerRadius: cornerRadius,
            paddingFactor: paddingFactor,
            distortionStrength: distortionStrength,
            blurRadius: blurRadius,
            shadowDirection: shadowDirection,
            minifyMultiplier: minifyMultiplier,
            magnifyMultiplier: magnifyMultiplier,
            distortionThreshold: distortionThreshold
        )
        encoder.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Params Struct
    
    private struct Params {
        var resolution: SIMD2<Float>
        var cornerRadius: Float
        var paddingFactor: Float
        var distortionStrength: Float
        var blurRadius: Float
        var shadowDirection: SIMD2<Float>
        var minifyMultiplier: Float
        var magnifyMultiplier: Float
        var distortionThreshold: Float
    }
}


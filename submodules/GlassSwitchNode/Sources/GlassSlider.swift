import UIKit

public class GlassSlider: UIView {
    
    // MARK: - Public Properties
    
    public var value: Float = 0.5 {
        didSet {
            value = min(max(value, minimumValue), maximumValue)
            updateThumbPosition()
            valueChanged?(value)
        }
    }
    
    public var minimumValue: Float = 0.0
    public var maximumValue: Float = 1.0
    
    public var valueChanged: ((Float) -> Void)?
    
    // MARK: - Private Properties
    
    // Container for both tracks
    private let trackContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()
    
    // Track (background - gray)
    private let trackView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.gray
        view.isUserInteractionEnabled = false
        return view
    }()
    
    // Filled track (left of thumb - blue)
    private let filledTrackView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0, green: 0.53, blue: 1, alpha: 1)
        view.isUserInteractionEnabled = false
        return view
    }()
    
    // Container for both thumbs (gestures go here)
    private let thumbContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.isUserInteractionEnabled = true
        return view
    }()
    
    // Normal opaque pill-shaped thumb (default state)
    private let normalThumb: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.isUserInteractionEnabled = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.shadowRadius = 2
        view.layer.shadowOpacity = 0.2
        return view
    }()
    
    // Glass thumb (expanded state) - hidden and inactive by default
    private lazy var glassThumb: GlassView = {
        let view = GlassView()
        view.configure(.sliderThumb)
        view.wobbleAxis = .horizontal  // Slider is horizontal, only wobble on X axis
        view.isUserInteractionEnabled = false
        view.clipsToBounds = false
        view.layer.masksToBounds = false
        view.alpha = 0  // Hidden by default
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.2
        return view
    }()
    
    // Thumb dimensions: 37x24 normal, 46x30 expanded
    private let thumbWidth: CGFloat = 37
    private let thumbHeight: CGFloat = 24
    private let expansionScaleX: CGFloat = 1.35
    private let expansionScaleY: CGFloat = 1.55
    private lazy var expandedWidth: CGFloat = thumbWidth * expansionScaleX
    private lazy var expandedHeight: CGFloat = thumbHeight * expansionScaleY
    private let trackHeight: CGFloat = 6
    private var isExpanded = false
    private var isDragging = false
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Rubber band edge bounce
    private var rubberBandOffset: CGFloat = 0  // Extra offset when pulling past edge
    private let maxRubberBand: CGFloat = 0.03  // Max 3% of track width
    
    // MARK: - Init
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Setup
    
    private func setup() {
        clipsToBounds = false
        layer.masksToBounds = false
        
        // Track container holds both tracks
        trackContainer.addSubview(trackView)
        trackContainer.addSubview(filledTrackView)
        trackContainer.layer.cornerRadius = trackHeight / 2
        filledTrackView.layer.cornerRadius = trackHeight / 2
        trackContainer.clipsToBounds = true
        addSubview(trackContainer)
        
        // Thumb container holds both thumbs
        // Set autoresizing so thumbs fill container even when transformed
        normalThumb.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glassThumb.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        thumbContainer.addSubview(normalThumb)
        thumbContainer.addSubview(glassThumb)
        addSubview(thumbContainer)
        
        // Long press for drag/hold (slight delay to distinguish from tap)
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleTouch(_:)))
        longPressGesture.minimumPressDuration = 0.15  // Short delay to detect tap vs hold
        longPressGesture.allowableMovement = .greatestFiniteMagnitude  // Allow dragging
        thumbContainer.addGestureRecognizer(longPressGesture)
        
        // Tap for quick expand → collapse animation
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.require(toFail: longPressGesture)  // Only fire if not a long press
        thumbContainer.addGestureRecognizer(tapGesture)
        
        feedbackGenerator.prepare()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Track container - horizontal span with padding for thumb
        trackContainer.frame = CGRect(
            x: thumbWidth / 2,
            y: (bounds.height - trackHeight) / 2,
            width: bounds.width - thumbWidth,
            height: trackHeight
        )
        
        // Track fills container
        trackView.frame = trackContainer.bounds
        
        // Update thumb and filled track positions
        updateThumbPosition()
        
        // Update corner radii
        normalThumb.layer.cornerRadius = thumbHeight / 2
        glassThumb.cornerRadius = Float(thumbHeight / 2)
    }
    
    // MARK: - Helpers
    
    private func thumbCenterXOffset(for value: Float) -> CGFloat {
        let trackWidth = bounds.width - thumbWidth
        guard trackWidth > 0, maximumValue > minimumValue else { return thumbWidth / 2 }
        
        let normalizedValue = (value - minimumValue) / (maximumValue - minimumValue)
        
        var position: Float
        
        if normalizedValue <= 0.10 {
            let t = normalizedValue / 0.10
            position = 0.05 + t * 0.05
        } else if normalizedValue >= 0.90 {
            let t = (normalizedValue - 0.90) / 0.10
            position = 0.90 + t * 0.05
        } else {
            position = normalizedValue
        }
        
        return thumbWidth / 2 + CGFloat(position) * trackWidth
    }
    
    private func updateThumbPosition() {
        guard bounds.width > thumbWidth else { return }
        
        let trackWidth = bounds.width - thumbWidth
        var centerXOffset = thumbCenterXOffset(for: value)
        
        // Add rubber band offset (allows thumb to move slightly past edge)
        centerXOffset += rubberBandOffset * trackWidth
        
        // Filled track follows slider VALUE directly (same as value)
        let normalizedValue = CGFloat((value - minimumValue) / (maximumValue - minimumValue))
        let filledWidth = max(0, normalizedValue * trackWidth)
        
        // Update filled track
        filledTrackView.frame = CGRect(x: 0, y: 0, width: filledWidth, height: trackHeight)
        
        // Update thumb container position
        thumbContainer.frame = CGRect(
            x: centerXOffset - thumbWidth / 2,
            y: (bounds.height - thumbHeight) / 2,
            width: thumbWidth,
            height: thumbHeight
        )
        
        // Both thumbs fill container
        normalThumb.frame = thumbContainer.bounds
        glassThumb.frame = thumbContainer.bounds
    }
    
    /// Apply rubber band resistance when pulling past edge
    private func applyRubberBand(overpull: CGFloat, atMinEdge: Bool) {
        let resistance: CGFloat = 0.15
        let rubberAmount = (1 - exp(-abs(overpull) * resistance)) * maxRubberBand
        rubberBandOffset = atMinEdge ? -rubberAmount : rubberAmount
        updateThumbPosition()
    }
    
    /// Animate rubber band snap back
    private func releaseRubberBand() {
        guard abs(rubberBandOffset) > 0.0001 else { return }
        
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.4,
            initialSpringVelocity: 1.5,
            options: .allowUserInteraction
        ) {
            self.rubberBandOffset = 0
            self.updateThumbPosition()
        }
    }
    
    private func valueForPosition(_ x: CGFloat) -> Float {
        let trackWidth = bounds.width - thumbWidth
        guard trackWidth > 0 else { return minimumValue }
        
        let clampedX = min(max(x - thumbWidth / 2, 0), trackWidth)
        let rawPosition = Float(clampedX / trackWidth)
        
        let position = min(max(rawPosition, 0.05), 0.95)
        
        var normalizedValue: Float
        
        if position <= 0.10 {
            let t = (position - 0.05) / 0.05
            normalizedValue = t * 0.10
        } else if position >= 0.90 {
            let t = (position - 0.90) / 0.05
            normalizedValue = 0.90 + t * 0.10
        } else {
            normalizedValue = position
        }
        
        return minimumValue + normalizedValue * (maximumValue - minimumValue)
    }
    
    private func expandThumb(completion: (() -> Void)? = nil) {
        guard !isExpanded else { return }
        isExpanded = true
                
        glassThumb.isActive = true
        
        let scaleX = expandedWidth / thumbWidth
        let scaleY = expandedHeight / thumbHeight
        
        UIView.animate(
            withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5,
            initialSpringVelocity: 0.8, options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.thumbContainer.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            self.normalThumb.alpha = 0
            self.glassThumb.alpha = 1
        } completion: { _ in
            completion?()
        }
    }
    
    private func collapseThumb() {
        guard isExpanded else { return }
        isExpanded = false
                
        let distortionStrength = glassThumb.distortionStrength
        self.glassThumb.distortionStrength = 0

        UIView.animate(
            withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5,
            initialSpringVelocity: 0.6, options: .allowUserInteraction
        ) {
            self.thumbContainer.transform = .identity
            self.normalThumb.alpha = 1
            self.glassThumb.alpha = 0
           
        } completion: { _ in
            self.glassThumb.isActive = false
            self.glassThumb.distortionStrength = distortionStrength
        }
    }
    
    // MARK: - Gesture Handling
    
    private var lastTouchLocation: CGPoint?
    private var lastTouchTime: CFTimeInterval?
    
    @objc private func handleTouch(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)
        let currentTime = CACurrentMediaTime()
        
        switch gesture.state {
        case .began:
            isDragging = true
            lastTouchLocation = location
            lastTouchTime = currentTime
            expandThumb()
            glassThumb.startWobble()
            feedbackGenerator.impactOccurred()
            
        case .changed:
            value = valueForPosition(location.x)
            
            var velocity = CGPoint.zero
            if let lastLocation = lastTouchLocation, let lastTime = lastTouchTime {
                let dt = currentTime - lastTime
                if dt > 0 {
                    velocity = CGPoint(
                        x: (location.x - lastLocation.x) / CGFloat(dt),
                        y: (location.y - lastLocation.y) / CGFloat(dt)
                    )
                }
            }
            
            let trackWidth = bounds.width - thumbWidth
            let minX = thumbWidth / 2 + trackWidth * 0.05
            let maxX = thumbWidth / 2 + trackWidth * 0.95
            
            if value == minimumValue && location.x < minX {
                let overpull = minX - location.x
                applyRubberBand(overpull: overpull, atMinEdge: true)
                glassThumb.applyEdgeStretch(intensity: overpull / 50)
            } else if value == maximumValue && location.x > maxX {
                let overpull = location.x - maxX
                applyRubberBand(overpull: overpull, atMinEdge: false)
                glassThumb.applyEdgeStretch(intensity: overpull / 50)
            } else {
                if abs(rubberBandOffset) > 0.0001 {
                    rubberBandOffset = 0
                    updateThumbPosition()
                }
                glassThumb.releaseEdgeStretch()
                glassThumb.updateWobble(velocity: velocity)
            }
            
            lastTouchLocation = location
            lastTouchTime = currentTime
            
        case .ended, .cancelled:
            isDragging = false
            lastTouchLocation = nil
            lastTouchTime = nil
            releaseRubberBand()
            glassThumb.stopWobble()
            collapseThumb()
            
        default:
            break
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        feedbackGenerator.impactOccurred()
        expandThumb {
            self.collapseThumb()
        }
    }
    
    // MARK: - Intrinsic Size
    
    public override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }
}


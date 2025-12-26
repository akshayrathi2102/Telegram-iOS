import UIKit

/// iOS 26-style toggle switch with glass expansion on interaction
/// - Non-interacted: gray track, white opaque thumb
/// - Interacted: thumb rises up and becomes glass, then returns to white
public class GlassSwitch: UIView, UIGestureRecognizerDelegate {
    
    // MARK: - Public Properties
    
    public var isOn: Bool = false {
        didSet {
            guard oldValue != isOn else { return }
            updateTrackColor(animated: true)
        }
    }
    
    public var valueChanged: ((Bool) -> Void)?
    
    /// Called when thumb expansion starts
    public var onExpansionStart: (() -> Void)?
    
    /// Called when thumb expansion ends (collapsed back)
    public var onExpansionEnd: (() -> Void)?
    
    /// Tint color for "on" state
    public var onTintColor: UIColor = UIColor.systemGreen {
        didSet {
            updateTrackColor(animated: false)
        }
    }
    
    /// Track color for "off" state
    public var offTrackColor: UIColor = UIColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 0.3)
    
    // MARK: - Private Properties
    
    // Track (gray when off, green when on)
    private let trackView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        return view
    }()

    // Container for both thumbs
    private let thumbContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.isUserInteractionEnabled = false
        return view
    }()
    
    // Normal white opaque thumb (default state)
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
    
    // Glass thumb (expanded state) - hidden by default
    private lazy var glassThumb: GlassView = {
        let view = GlassView()
        view.configure(.switchThumb)
        view.wobbleAxis = .horizontal
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
    
    // Dimensions: 63x28 track, 37x24 thumb
    private let trackWidth: CGFloat = 63
    private let trackHeight: CGFloat = 28
    private let thumbWidth: CGFloat = 37
    private let thumbHeight: CGFloat = 24
    private let thumbPadding: CGFloat = 2
    private let expansionScaleX: CGFloat = 1.5
    private let expansionScaleY: CGFloat = 1.6

    // Rubber band effect at edges
    private let maxRubberBand: CGFloat = 8.0  // Max pixels thumb can be pulled past edge

    // Animation state
    private var isExpanded = false

    // Current thumb leading offset
    private var currentThumbLeadingOffset: CGFloat = 2
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private let toggleFeedback = UIImpactFeedbackGenerator(style: .medium)
    
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
        
        // Track
        addSubview(trackView)
        trackView.backgroundColor = offTrackColor
        
        // Thumb container holds both thumbs
        // Set autoresizing so thumbs fill container even when transformed
        normalThumb.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glassThumb.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        thumbContainer.addSubview(normalThumb)
        thumbContainer.addSubview(glassThumb)
        addSubview(thumbContainer)
        
        // Long press gesture for tap and hold
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0
        longPressGesture.allowableMovement = .greatestFiniteMagnitude
        longPressGesture.delegate = self
        addGestureRecognizer(longPressGesture)
        
        // Pan gesture for dragging
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        
        feedbackGenerator.prepare()
        toggleFeedback.prepare()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Track fills self
        trackView.frame = bounds
        trackView.layer.cornerRadius = trackHeight / 2
        
        // Update thumb container position
        currentThumbLeadingOffset = thumbLeadingOffset(for: isOn)
        thumbContainer.frame = CGRect(
            x: currentThumbLeadingOffset,
            y: (bounds.height - thumbHeight) / 2,
            width: thumbWidth,
            height: thumbHeight
        )
        
        // Normal thumb fills container
        normalThumb.frame = thumbContainer.bounds
        normalThumb.layer.cornerRadius = thumbHeight / 2
        
        // Glass thumb fills container
        glassThumb.frame = thumbContainer.bounds
        glassThumb.cornerRadius = Float(thumbHeight / 2)
    }
    
    // MARK: - Helpers
    
    private func thumbLeadingOffset(for on: Bool) -> CGFloat {
        if on {
            return trackWidth - thumbWidth - thumbPadding
        } else {
            return thumbPadding
        }
    }
    
    /// Calculate rubber band amount with diminishing returns
    private func rubberBandAmount(overpull: CGFloat) -> CGFloat {
        // Rubber band formula: diminishing returns as you pull harder
        // Uses exponential decay for natural feel
        let resistance: CGFloat = 0.15  // Lower = more resistance
        return maxRubberBand * (1 - exp(-overpull * resistance / maxRubberBand))
    }

    private func updateTrackColor(animated: Bool) {
        let targetColor = isOn ? onTintColor : offTrackColor
        
        if animated {
            UIView.animate(
                withDuration: 0.15,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.trackView.backgroundColor = targetColor
            }
        } else {
            trackView.backgroundColor = targetColor
        }
    }
    
    private func updateThumbPosition(offset: CGFloat, animated: Bool) {
        currentThumbLeadingOffset = offset
        
        if animated {
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0.5,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.thumbContainer.frame = CGRect(
                    x: offset,
                    y: (self.bounds.height - self.thumbHeight) / 2,
                    width: self.thumbWidth,
                    height: self.thumbHeight
                )
            }
        } else {
            thumbContainer.frame = CGRect(
                x: offset,
                y: (bounds.height - thumbHeight) / 2,
                width: thumbWidth,
                height: thumbHeight
            )
        }
    }
    
    // MARK: - Expand/Collapse Animations
    
    private func expandThumb() {
        // Always expand, even if partially collapsed
        isExpanded = true
        
        // Notify parent to bring to front
        onExpansionStart?()
        
        glassThumb.isActive = true
        glassThumb.startWobble()
        
        // Cancel any ongoing collapse animation
        normalThumb.layer.removeAllAnimations()
        glassThumb.layer.removeAllAnimations()

        UIView.animate(
            withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8, options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.thumbContainer.transform = CGAffineTransform(
                scaleX: self.expansionScaleX, y: self.expansionScaleY)
            self.normalThumb.alpha = 0
            self.glassThumb.alpha = 1
        }
    }
    
    private func collapseThumb() {
        guard isExpanded else { return }
        isExpanded = false
        
        glassThumb.stopWobble()
        
        UIView.animate(
            withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.4, options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.thumbContainer.transform = .identity
            self.normalThumb.alpha = 1
            self.glassThumb.alpha = 0
        } completion: { _ in
            self.glassThumb.isActive = false
            // Notify parent to restore z-order
            self.onExpansionEnd?()
        }
    }
    
    private func moveThumbToPosition(animated: Bool) {
        let targetOffset = thumbLeadingOffset(for: isOn)
        updateThumbPosition(offset: targetOffset, animated: animated)
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
    
    // MARK: - Gesture Handling
    
    private var hasDragged = false
    private var dragStartOffset: CGFloat = 0

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            hasDragged = false
            expandThumb()
            feedbackGenerator.impactOccurred()
            
        case .ended, .cancelled:
            if !hasDragged {
                // Tap or long press release: toggle and collapse
                isOn.toggle()
                valueChanged?(isOn)
                toggleFeedback.impactOccurred()
                moveThumbToPosition(animated: true)
            }
            collapseThumb()
            
        default:
            break
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .began:
            hasDragged = true
            dragStartOffset = currentThumbLeadingOffset
            
        case .changed:
            let minOffset = thumbPadding
            let maxOffset = trackWidth - thumbWidth - thumbPadding
            let newOffset = dragStartOffset + translation.x
            
            // Apply rubber band at edges
            var finalOffset: CGFloat
            var overpull: CGFloat = 0

            if newOffset < minOffset {
                overpull = minOffset - newOffset
                finalOffset = minOffset - rubberBandAmount(overpull: overpull)
            } else if newOffset > maxOffset {
                overpull = newOffset - maxOffset
                finalOffset = maxOffset + rubberBandAmount(overpull: overpull)
            } else {
                finalOffset = newOffset
            }
            
            updateThumbPosition(offset: finalOffset, animated: false)
            
            // Blend track color based on progress
            let clampedOffset = max(minOffset, min(maxOffset, newOffset))
            let progress = (clampedOffset - minOffset) / (maxOffset - minOffset)
            trackView.backgroundColor = UIColor.blend(
                from: offTrackColor, to: onTintColor, progress: progress)
            
            // Toggle state when touching edges
            if newOffset >= maxOffset && !isOn {
                isOn = true
                valueChanged?(isOn)
                toggleFeedback.impactOccurred()
            } else if newOffset <= minOffset && isOn {
                isOn = false
                valueChanged?(isOn)
                toggleFeedback.impactOccurred()
            }

            // Wobble and edge stretch
            glassThumb.updateWobble(velocity: CGPoint(x: velocity.x, y: 0))

            if overpull > 0 {
                glassThumb.applyEdgeStretch(intensity: overpull / 30)
            } else {
                glassThumb.releaseEdgeStretch()
            }
            
        case .ended, .cancelled:
            moveThumbToPosition(animated: true)
            glassThumb.releaseEdgeStretch()
            
        default:
            break
        }
    }
    
    // MARK: - Intrinsic Size
    
    public override var intrinsicContentSize: CGSize {
        return CGSize(width: trackWidth, height: trackHeight)
    }
}

// MARK: - UIColor Extension

private extension UIColor {
    static func blend(from: UIColor, to: UIColor, progress: CGFloat) -> UIColor {
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0
        
        from.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        to.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)
        
        let r = fromR + (toR - fromR) * progress
        let g = fromG + (toG - fromG) * progress
        let b = fromB + (toB - fromB) * progress
        let a = fromA + (toA - fromA) * progress
        
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}


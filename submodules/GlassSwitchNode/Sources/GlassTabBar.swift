import UIKit

/// iOS 26-style tab bar with glass effect on selected item
public class GlassTabBar: UIView, UIGestureRecognizerDelegate {
    
    // MARK: - Public Properties
    
    public var selectedIndex: Int = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            animateSelection(from: oldValue, to: selectedIndex)
        }
    }
    
    private var oldIndex: Int = 0
    
    public var indexChanged: ((Int) -> Void)?
    
    // MARK: - Animation Properties
    
    private let expansionScaleX: CGFloat = 1.3
    private let expansionScaleY: CGFloat = 1.45
    
    // MARK: - Private Properties
    
    private var tabItems: [TabItem] = []
    private var tabButtons: [UIButton] = []
    
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fill
        stack.alignment = .fill
        stack.spacing = 0
        return stack
    }()
    
    /// Container for both thumbs - this is what gets transformed
    private let thumbContainer: UIView = {
        let view = UIView()
        view.clipsToBounds = false
        view.layer.masksToBounds = false
        return view
    }()
    
    /// Normal thumb - transparent with tint, visible in default state
    private let normalThumb: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        view.clipsToBounds = true
        return view
    }()
    
    /// Glass thumb - visible when selected/animating
    private lazy var glassThumb: GlassView = {
        let view = GlassView()
        view.configure(.tabBarThumb)
        view.blurRadius = 0.05
        view.alpha = 0
        view.isActive = false
        view.clipsToBounds = false
        view.layer.masksToBounds = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 4
        view.layer.shadowOpacity = 0.2
        return view
    }()
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Track interaction state
    private var isExpanded = false
    private var touchedIndex: Int?
    private var isDragging = false
    private var dragStartOffset: CGFloat = 0
    
    // Layout properties
    private let buttonWidth: CGFloat = 75.56
    private var thumbCenterXOffset: CGFloat = 0
    private var thumbWidth: CGFloat = 80
    
    // MARK: - Types
    
    public struct TabItem {
        public let icon: UIImage?
        public let selectedIcon: UIImage?
        public let title: String
        
        public init(icon: UIImage?, selectedIcon: UIImage?, title: String) {
            self.icon = icon
            self.selectedIcon = selectedIcon
            self.title = title
        }
    }
    
    // MARK: - Init
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    public convenience init(items: [TabItem]) {
        self.init(frame: .zero)
        setItems(items)
    }
    
    // MARK: - Setup
    
    private func setup() {
        backgroundColor = UIColor(white: 0.95, alpha: 0.9)
        clipsToBounds = false
        layer.masksToBounds = false
        
        // Add thumb container with both thumbs
        // Set autoresizing so thumbs fill container even when transformed
        normalThumb.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glassThumb.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        thumbContainer.addSubview(normalThumb)
        thumbContainer.addSubview(glassThumb)
        addSubview(thumbContainer)
        addSubview(stackView)
        
        // Add pan gesture to self for dragging the thumb
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        
        feedbackGenerator.prepare()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = bounds.height / 2
        
        // Stack view - centered horizontally
        let stackWidth = CGFloat(tabButtons.count) * buttonWidth
        stackView.frame = CGRect(
            x: (bounds.width - stackWidth) / 2,
            y: 2,
            width: stackWidth,
            height: bounds.height - 4
        )
        
        // Update thumb position
        updateThumbFrame()
        updateCornerRadii()
    }
    
    private func updateThumbFrame() {
        let stackCenterX = stackView.frame.midX
        let thumbHeight = stackView.bounds.height - 4
        
        thumbContainer.frame = CGRect(
            x: stackCenterX + thumbCenterXOffset - thumbWidth / 2,
            y: stackView.frame.minY + 2,
            width: thumbWidth,
            height: thumbHeight
        )
        
        normalThumb.frame = thumbContainer.bounds
        glassThumb.frame = thumbContainer.bounds
    }
    
    private func updateCornerRadii() {
        let thumbHeight = normalThumb.bounds.height
        if thumbHeight > 0 {
            normalThumb.layer.cornerRadius = thumbHeight / 2
            glassThumb.cornerRadius = Float(thumbHeight / 2)
        }
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    // MARK: - Public Methods
    
    public func setItems(_ items: [TabItem]) {
        // Remove existing buttons
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()
        tabItems = items
        
        // Create new buttons
        for (index, item) in items.enumerated() {
            let button = createTabButton(for: item, at: index)
            tabButtons.append(button)
            stackView.addArrangedSubview(button)
        }
        
        // Initial selection
        setNeedsLayout()
        layoutIfNeeded()
        updateThumbPositionForSelectedIndex(animated: false)
    }
    
    private func createTabButton(for item: TabItem, at index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = index
        
        // Configure image
        let image = index == selectedIndex ? item.selectedIcon : item.icon
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let configuredImage = image?.withConfiguration(symbolConfig)
        button.setImage(configuredImage, for: .normal)
        
        // Configure title
        button.setTitle(item.title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        
        // Configure color
        button.tintColor = index == selectedIndex ? .systemBlue : .gray
        
        // Configure layout - image on top, title below
        button.contentVerticalAlignment = .center
        button.contentHorizontalAlignment = .center
        
        // Adjust image and title positioning for vertical layout
        let imageSize: CGFloat = 22
        let spacing: CGFloat = 4
        button.imageEdgeInsets = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: -button.titleLabel!.intrinsicContentSize.width)
        button.titleEdgeInsets = UIEdgeInsets(top: imageSize + spacing, left: -imageSize, bottom: 0, right: 0)
        
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 2, bottom: 4, right: 2)
        
        // Add long press gesture for tap and hold behavior
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0
        button.addGestureRecognizer(longPress)
        
        // Fixed width
        button.frame.size.width = buttonWidth
        
        return button
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton else { return }
        let index = button.tag
        
        switch gesture.state {
        case .began:
            touchedIndex = index
            feedbackGenerator.impactOccurred()
            expandThumb()
            
        case .ended:
            guard let tappedIndex = touchedIndex else {
                collapseThumb()
                touchedIndex = nil
                return
            }
            
            if tappedIndex != selectedIndex {
                oldIndex = selectedIndex
                selectedIndex = tappedIndex
                indexChanged?(selectedIndex)
                
                // Update button appearances
                updateButtonAppearances()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.updateThumbPositionForSelectedIndex(animated: true) { [weak self] in
                        self?.collapseThumb()
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.collapseThumb()
                }
            }
            touchedIndex = nil
            
        case .cancelled, .failed:
            collapseThumb()
            touchedIndex = nil
            
        default:
            break
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let locationInStack = gesture.location(in: stackView)
        
        switch gesture.state {
        case .began:
            let thumbFrameInSelf = thumbContainer.frame
            let expandedThumbFrame = thumbFrameInSelf.insetBy(dx: -30, dy: -30)
            
            guard expandedThumbFrame.contains(location) else {
                isDragging = false
                return
            }
            
            isDragging = true
            feedbackGenerator.impactOccurred()
            expandThumb()
            
            glassThumb.wobbleAxis = .horizontal
            glassThumb.startWobble()
            
            touchedIndex = selectedIndex
            dragStartOffset = locationInStack.x - stackView.bounds.width / 2 - thumbCenterXOffset
            
        case .changed:
            guard isDragging else { return }
            
            let stackCenterX = stackView.bounds.width / 2
            var newCenterOffset = locationInStack.x - stackCenterX - dragStartOffset
            
            // Clamp to valid range
            if let firstButton = tabButtons.first, let lastButton = tabButtons.last {
                let firstCenter = firstButton.frame.midX
                let lastCenter = lastButton.frame.midX
                let minOffset = firstCenter - stackCenterX
                let maxOffset = lastCenter - stackCenterX
                newCenterOffset = max(minOffset, min(maxOffset, newCenterOffset))
            }
            
            thumbCenterXOffset = newCenterOffset
            updateThumbFrame()
            
            let velocity = gesture.velocity(in: self)
            glassThumb.updateWobble(velocity: velocity)
            
            let thumbCenterX = stackView.bounds.width / 2 + newCenterOffset
            let newHoveredIndex = indexForThumbPosition(thumbCenterX)
            if newHoveredIndex != touchedIndex {
                touchedIndex = newHoveredIndex
                if newHoveredIndex != nil {
                    feedbackGenerator.impactOccurred()
                }
                
                updateButtonAppearances(highlightedIndex: newHoveredIndex)
            }
            
        case .ended, .cancelled:
            guard isDragging else { return }
            isDragging = false
            
            glassThumb.stopWobble()
            
            let nearestIndex = indexForPosition(locationInStack.x)
            
            if nearestIndex != selectedIndex {
                oldIndex = selectedIndex
                selectedIndex = nearestIndex
                indexChanged?(selectedIndex)
                
                updateButtonAppearances()
            }
            
            updateThumbPositionForSelectedIndex(animated: true) { [weak self] in
                self?.collapseThumb()
            }
            touchedIndex = nil
            
        default:
            break
        }
    }
    
    private func indexForThumbPosition(_ thumbCenterX: CGFloat) -> Int? {
        for (index, button) in tabButtons.enumerated() {
            let buttonFrame = button.frame
            if thumbCenterX >= buttonFrame.minX && thumbCenterX <= buttonFrame.maxX {
                return index
            }
        }
        return nil
    }
    
    private func indexForPosition(_ x: CGFloat) -> Int {
        guard !tabButtons.isEmpty else { return 0 }
        
        var closestIndex = 0
        var closestDistance = CGFloat.greatestFiniteMagnitude
        
        for (index, button) in tabButtons.enumerated() {
            let distance = abs(button.frame.midX - x)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        
        return closestIndex
    }
    
    private func animateSelection(from oldIndex: Int, to newIndex: Int) {
        updateButtonAppearances(highlightedIndex: newIndex)
        
        expandThumb { [weak self] in
            self?.updateThumbPositionForSelectedIndex(animated: true) { [weak self] in
                self?.collapseThumb()
            }
        }
    }
    
    private func updateButtonAppearances(highlightedIndex: Int? = nil) {
        let indexToHighlight = highlightedIndex ?? selectedIndex
        for (i, btn) in tabButtons.enumerated() {
            let item = tabItems[i]
            let isSelected = i == indexToHighlight
            let image = isSelected ? item.selectedIcon : item.icon
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            let configuredImage = image?.withConfiguration(symbolConfig)
            btn.setImage(configuredImage, for: .normal)
            btn.tintColor = isSelected ? .systemBlue : .gray
        }
    }
    
    private func expandThumb(completion: (() -> Void)? = nil) {
        guard !isExpanded else {
            completion?()
            return
        }
        isExpanded = true
        glassThumb.isActive = true
        
        bringSubviewToFront(thumbContainer)
        
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.thumbContainer.transform = CGAffineTransform(scaleX: self.expansionScaleX, y: self.expansionScaleY)
            self.glassThumb.alpha = 1
            self.normalThumb.alpha = 0
        } completion: { _ in
            completion?()
        }
    }
    
    private func collapseThumb(completion: (() -> Void)? = nil) {
        guard isExpanded else {
            completion?()
            return
        }
        isExpanded = false
        
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.3,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.thumbContainer.transform = .identity
            self.glassThumb.alpha = 0
            self.normalThumb.alpha = 1
        } completion: { _ in
            self.glassThumb.isActive = false
            self.sendSubviewToBack(self.thumbContainer)
            completion?()
        }
    }
    
    private func updateThumbPositionForSelectedIndex(animated: Bool, completion: (() -> Void)? = nil) {
        guard selectedIndex < tabButtons.count else {
            completion?()
            return
        }
        
        let selectedButton = tabButtons[selectedIndex]
        let buttonCenterX = selectedButton.frame.midX
        let stackCenterX = stackView.bounds.width / 2
        let centerXOffset = buttonCenterX - stackCenterX
        let newThumbWidth = selectedButton.frame.width + 8
        
        thumbCenterXOffset = centerXOffset
        thumbWidth = newThumbWidth
        
        if animated {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0.5,
                options: [.allowUserInteraction]
            ) {
                self.updateThumbFrame()
                self.updateCornerRadii()
            } completion: { _ in
                completion?()
            }
        } else {
            updateThumbFrame()
            updateCornerRadii()
            completion?()
        }
    }
    
    // MARK: - Intrinsic Size
    
    public override var intrinsicContentSize: CGSize {
        return CGSize(width: 320, height: 59)
    }
}


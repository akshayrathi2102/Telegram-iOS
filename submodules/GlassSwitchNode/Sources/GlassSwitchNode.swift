import UIKit
import AsyncDisplayKit

/// AsyncDisplayKit node wrapper for GlassSwitch
public class GlassSwitchNode: ASDisplayNode {
    
    // MARK: - Properties
    
    public var isOn: Bool {
        get { glassSwitch.isOn }
        set { glassSwitch.isOn = newValue }
    }
    
    public var valueChanged: ((Bool) -> Void)? {
        get { glassSwitch.valueChanged }
        set { glassSwitch.valueChanged = newValue }
    }
    
    public var onTintColor: UIColor {
        get { glassSwitch.onTintColor }
        set { glassSwitch.onTintColor = newValue }
    }
    
    public var offTrackColor: UIColor {
        get { glassSwitch.offTrackColor }
        set { glassSwitch.offTrackColor = newValue }
    }
    
    // MARK: - Private Properties
    
    private let glassSwitch: GlassSwitch
    private var savedZPosition: CGFloat = 0
    
    // MARK: - Initialization
    
    public override init() {
        glassSwitch = GlassSwitch()
        
        super.init()
        
        setViewBlock { [weak self] () -> UIView in
            return self?.glassSwitch ?? UIView()
        }
        
        // Disable clipping so the expanded glass thumb can overflow
        clipsToBounds = false
    }
    
    public override func didLoad() {
        super.didLoad()
        
        // Ensure the view and layer don't clip the expanded thumb
        view.clipsToBounds = false
        layer.masksToBounds = false
        
        // Listen for expansion/collapse to manage z-ordering
        setupExpansionHandling()
    }
    
    private func setupExpansionHandling() {
        // When the switch starts expanding, bring it to front
        glassSwitch.onExpansionStart = { [weak self] in
            guard let self = self else { return }
            // Save current z position and bring to front
            self.savedZPosition = self.layer.zPosition
            self.layer.zPosition = 1000
            self.supernode?.view.bringSubviewToFront(self.view)
        }
        
        // When the switch finishes collapsing, restore z position
        glassSwitch.onExpansionEnd = { [weak self] in
            guard let self = self else { return }
            self.layer.zPosition = self.savedZPosition
        }
    }
    
    public func setOn(_ value: Bool, animated: Bool) {
        if animated {
            glassSwitch.isOn = value
        } else {
            glassSwitch.isOn = value
        }
    }
    
    // MARK: - Layout
    
    public override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 63, height: 28)
    }
}



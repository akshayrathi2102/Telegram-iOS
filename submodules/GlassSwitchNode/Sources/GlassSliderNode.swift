import UIKit
import AsyncDisplayKit

/// AsyncDisplayKit node wrapper for GlassSlider
public class GlassSliderNode: ASDisplayNode {
    
    // MARK: - Properties
    
    public var value: Float {
        get { glassSlider.value }
        set { glassSlider.value = newValue }
    }
    
    public var minimumValue: Float {
        get { glassSlider.minimumValue }
        set { glassSlider.minimumValue = newValue }
    }
    
    public var maximumValue: Float {
        get { glassSlider.maximumValue }
        set { glassSlider.maximumValue = newValue }
    }
    
    public var valueChanged: ((Float) -> Void)? {
        get { glassSlider.valueChanged }
        set { glassSlider.valueChanged = newValue }
    }
    
    // MARK: - Private Properties
    
    private let glassSlider: GlassSlider
    
    // MARK: - Initialization
    
    public override init() {
        glassSlider = GlassSlider()
        
        super.init()
        
        setViewBlock { [weak self] () -> UIView in
            return self?.glassSlider ?? UIView()
        }
    }
    
    // MARK: - Layout
    
    public override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: constrainedSize.width, height: 44)
    }
}


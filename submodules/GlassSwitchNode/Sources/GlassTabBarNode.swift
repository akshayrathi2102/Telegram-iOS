import UIKit
import AsyncDisplayKit

/// AsyncDisplayKit node wrapper for GlassTabBar
public class GlassTabBarNode: ASDisplayNode {
    
    // MARK: - Properties
    
    public var selectedIndex: Int {
        get { glassTabBar.selectedIndex }
        set { glassTabBar.selectedIndex = newValue }
    }
    
    public var indexChanged: ((Int) -> Void)? {
        get { glassTabBar.indexChanged }
        set { glassTabBar.indexChanged = newValue }
    }
    
    // MARK: - Private Properties
    
    private let glassTabBar: GlassTabBar
    
    // MARK: - Initialization
    
    public override init() {
        glassTabBar = GlassTabBar()
        
        super.init()
        
        setViewBlock { [weak self] () -> UIView in
            return self?.glassTabBar ?? UIView()
        }
    }
    
    // MARK: - Methods
    
    public func setItems(_ items: [GlassTabBar.TabItem]) {
        glassTabBar.setItems(items)
    }
    
    // MARK: - Layout
    
    public override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 320, height: 59)
    }
}


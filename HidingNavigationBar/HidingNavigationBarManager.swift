//
//  HidingNavigationBarManager.swift
//
//  The MIT License (MIT)
//
//  Copyright (c) 2015 Tristan Himmelman
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit

public protocol HidingNavigationBarManagerDelegate: class {
    func hidingNavigationBarManagerShouldUpdateScrollViewInsets(_ manager: HidingNavigationBarManager, insets: UIEdgeInsets) -> Bool
    func hidingNavigationBarManagerDidUpdateScrollViewInsets(_ manager: HidingNavigationBarManager)
    func hidingNavigationBarManagerDidChangeState(_ manager: HidingNavigationBarManager, toState state: HidingNavigationBarState)
}

public enum HidingNavigationBarState: String {
    case Closed            = "Closed"
    case Contracting    = "Contracting"
    case Expanding        = "Expanding"
    case Open            = "Open"
}

public enum HidingNavigationForegroundAction {
    case `default`
    case show
    case hide
}

open class HidingNavigationBarManager: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    // The view controller that is part of the navigation stack
    unowned var viewController: UIViewController
    
    // The scrollView that will drive the contraction/expansion
    unowned var scrollView: UIScrollView
    
    // The extension view to be shown beneath the navbar
    weak var extensionView: UIView?
    
    // Control the resistance when scrolling up/down before the navbar expands/contracts again.
    open var expansionResistance: CGFloat = 0
    open var contractionResistance: CGFloat = 0
    
    weak open var delegate: HidingNavigationBarManagerDelegate?
    
    open var refreshControl: UIRefreshControl?
    
    fileprivate var navBarController: HidingViewController
    fileprivate var extensionController: HidingViewController
    fileprivate var tabBarController: HidingViewController?
    
    // Scroll calculation values
    fileprivate var topInset: CGFloat = 0
    fileprivate var previousYOffset = CGFloat.nan
    fileprivate var resistanceConsumed: CGFloat = 0
    fileprivate var isUpdatingValues = false
    
    // Hiding navigation bar state
    fileprivate var currentState = HidingNavigationBarState.Open
    fileprivate var previousState = HidingNavigationBarState.Open
    fileprivate var panGesture: UIPanGestureRecognizer?
    
    //Options
    open var onForegroundAction = HidingNavigationForegroundAction.default
    
    public init(viewController: UIViewController, scrollView: UIScrollView){
        if viewController.navigationController == nil || viewController.navigationController?.navigationBar == nil {
            fatalError("ViewController must be within a UINavigationController")
        }
        
        viewController.extendedLayoutIncludesOpaqueBars = true
        
        self.viewController = viewController
        self.scrollView = scrollView
        
        // Create extensionController
        extensionController = HidingViewController()
        viewController.view.addSubview(extensionController.view)
        
        let navBar = viewController.navigationController!.navigationBar
        navBarController = HidingViewController(view: navBar)
        navBarController.child = extensionController
        navBarController.alphaFadeEnabled = true
        
        super.init()
        
        // track panning on scroll view
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(HidingNavigationBarManager.handlePanGesture(_:)))
        panGesture.delegate = self
        scrollView.addGestureRecognizer(panGesture)
        self.panGesture = panGesture
        
        navBarController.expandedCenter = {[weak self] (view: UIView) -> CGPoint in
            return CGPoint(x: view.bounds.midX, y: view.bounds.midY + (self?.statusBarHeight() ?? 0))
        }
        
        extensionController.expandedCenter = {[weak self] (view: UIView) -> CGPoint in
            let topOffset = (self?.navBarController.contractionAmountValue() ?? 0) + (self?.statusBarHeight() ?? 0)
            let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY + topOffset)
            
            return point
        }
        
        updateContentInsets()
        
        NotificationCenter.default.addObserver(self, selector: #selector(HidingNavigationBarManager.applicationWillEnterForeground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let panGesture = panGesture {
            scrollView.removeGestureRecognizer(panGesture)
        }
    }
    
    //MARK: Public methods
    
    open func manageBottomBar(_ view: UIView){
        tabBarController = HidingViewController(view: view)
        tabBarController?.contractsUpwards = false
        tabBarController?.expandedCenter = {[weak self] (view: UIView) -> CGPoint in
            let height = self?.viewController.view.frame.size.height ?? 0
            let point = CGPoint(x: view.bounds.midX, y: height - view.bounds.midY)
            
            return point
        }
    }
    
    open func addExtensionView(_ view: UIView) {
        extensionView?.removeFromSuperview()
        extensionView = view
        
        var bounds = view.frame
        bounds.origin = CGPoint.zero
        
        extensionView?.frame = bounds
        extensionController.view.frame = bounds
        extensionController.view.addSubview(view)
        _ = extensionController.expand()
        
        extensionController.view.superview?.bringSubviewToFront(extensionController.view)
        updateContentInsets()
    }
    
    open func viewWillAppear(_ animated: Bool) {
        panGesture?.isEnabled = true
        expand()
    }
    
    open func viewDidLayoutSubviews() {
        updateContentInsets()
    }
    
    open func viewWillDisappear(_ animated: Bool) {
        expand()
        panGesture?.isEnabled = false
    }
    
    open func updateValues()    {
        isUpdatingValues = true
        
        var scrolledToTop = false
        
        if scrollViewContentInset.top == -scrollView.contentOffset.y {
            scrolledToTop = true
        }
        
        if let extensionView = extensionView {
            var frame = extensionController.view.frame
            frame.size.width = extensionView.bounds.size.width
            frame.size.height = extensionView.bounds.size.height
            extensionController.view.frame = frame
        }
        
        updateContentInsets()
        
        if scrolledToTop {
            var offset = scrollView.contentOffset
            offset.y = -scrollViewContentInset.top
            scrollView.contentOffset = offset
        }
        
        isUpdatingValues = false
    }
    
    open func shouldScrollToTop(){
        // update content Inset
        let top = statusBarHeight() + navBarController.totalHeight()
        updateScrollContentInsetTop(top)
        
        _ = navBarController.snap(false, completion: nil)
        _ = tabBarController?.snap(false, completion: nil)
    }
    
    open func contract(){
        _ = navBarController.contract()
        _ = tabBarController?.contract()
        
        previousYOffset = CGFloat.nan
        
        handleScrolling()
    }
    
    open func expand() {
        _ = navBarController.expand()
        _ = tabBarController?.expand()
        
        previousYOffset = CGFloat.nan
        
        handleScrolling()
    }
    
    //MARK: NSNotification
    
    @objc func applicationWillEnterForeground() {
        switch onForegroundAction {
        case .show:
            _ = navBarController.expand()
            _ = tabBarController?.expand()
        case .hide:
            _ = navBarController.contract()
            _ = tabBarController?.contract()
        default:
            break;
        }
        handleScrolling()
    }
    
    //MARK: Private methods
    
    fileprivate func isViewControllerVisible() -> Bool {
        return viewController.isViewLoaded && viewController.view.window != nil
    }
    
    fileprivate func statusBarHeight() -> CGFloat {
        if UIApplication.shared.isStatusBarHidden {
            return 0
        }
        
        let statusBarSize = UIApplication.shared.statusBarFrame.size
        return min(statusBarSize.width, statusBarSize.height)
    }
    
    fileprivate func shouldHandleScrolling() -> Bool {
        // if scrolling down past top
        if scrollView.contentOffset.y <= -scrollViewContentInset.top && currentState == .Open {
            return false
        }
        
        // if refreshing
        if refreshControl?.isRefreshing == true {
            return false
        }
        
        let scrollFrame = scrollView.bounds.inset(by: scrollViewContentInset)
        let scrollableAmount: CGFloat = scrollView.contentSize.height - scrollFrame.height
        let scrollViewIsSuffecientlyLong: Bool = scrollableAmount > navBarController.totalHeight() * 3
        
        return isViewControllerVisible() && scrollViewIsSuffecientlyLong && !isUpdatingValues
    }
    
    fileprivate func handleScrolling(){
        if shouldHandleScrolling() == false {
            return
        }
        
        if previousYOffset.isNaN == false {
            // 1 - Calculate the delta
            var deltaY = previousYOffset - scrollView.contentOffset.y
            
            // 2 - Ignore any scrollOffset beyond the bounds
            let start = -topInset
            if previousYOffset < start {
                deltaY = min(0, deltaY - previousYOffset - start)
            }
            
            /* rounding to resolve a dumb issue with the contentOffset value */
            let end = floor(scrollView.contentSize.height - scrollView.bounds.height + scrollViewContentInset.bottom - 0.5)
            if previousYOffset > end {
                deltaY = max(0, deltaY - previousYOffset + end)
            }
            
            // 3 - Update contracting variable
            if Float(fabs(deltaY)) > .ulpOfOne {
                if deltaY < 0 {
                    currentState = .Contracting
                } else {
                    currentState = .Expanding
                }
            }
            
            // 4 - Check if contracting state changed, and do stuff if so
            if currentState != previousState {
                previousState = currentState
                resistanceConsumed = 0
            }
            
            // 5 - Apply resistance
            if currentState == .Contracting {
                let availableResistance = contractionResistance - resistanceConsumed
                resistanceConsumed = min(contractionResistance, resistanceConsumed - deltaY)
                
                deltaY = min(0, availableResistance + deltaY)
            } else if scrollView.contentOffset.y > -statusBarHeight() {
                let availableResistance = expansionResistance - resistanceConsumed
                resistanceConsumed = min(expansionResistance, resistanceConsumed + deltaY)
                
                deltaY = max(0, deltaY - availableResistance)
            }
            
            // 6 - Update the shyViewController
            _ = navBarController.updateYOffset(deltaY)
            _ = tabBarController?.updateYOffset(deltaY)
        }
        
        // update content Inset
        updateContentInsets()
        
        previousYOffset = scrollView.contentOffset.y
        
        // update the visible state
        let state = currentState
        if navBarController.view.center.equalTo(navBarController.expandedCenterValue()) && extensionController.view.center.equalTo(extensionController.expandedCenterValue()) {
            currentState = .Open
        } else if navBarController.view.center.equalTo(navBarController.contractedCenterValue()) &&  extensionController.view.center.equalTo(extensionController.contractedCenterValue()) {
            currentState = .Closed
        }
        
        if state != currentState {
            delegate?.hidingNavigationBarManagerDidChangeState(self, toState: currentState)
        }
    }
    
    fileprivate func updateContentInsets() {
        let navBarBottomY = navBarController.view.frame.origin.y + navBarController.view.frame.size.height
        let top: CGFloat
        if extensionController.isContracted() == false {
            top = extensionController.view.frame.origin.y + extensionController.view.bounds.size.height
        } else {
            top = navBarBottomY
        }
        updateScrollContentInsetTop(top)
    }
    
    fileprivate func updateScrollContentInsetTop(_ top: CGFloat) {
        let top = adjustTopInset(top)
        
        let contentInset = UIEdgeInsets(top: top, left: scrollViewContentInset.top, bottom: scrollViewContentInset.left, right: scrollViewContentInset.right)
        if delegate?.hidingNavigationBarManagerShouldUpdateScrollViewInsets(self, insets: contentInset) == false {
            return
        }
        
        if viewController.automaticallyAdjustsScrollViewInsets {
            var contentInset = scrollViewContentInset
            contentInset.top = top
            scrollView.contentInset = contentInset
        }
        var scrollInsets = scrollView.scrollIndicatorInsets
        scrollInsets.top = top
        scrollView.scrollIndicatorInsets = scrollInsets
        delegate?.hidingNavigationBarManagerDidUpdateScrollViewInsets(self)
    }
    
    fileprivate func handleScrollingEnded(_ velocity: CGFloat) {
        let minVelocity: CGFloat = 500.0
        if isViewControllerVisible() == false || (navBarController.isContracted() && velocity < minVelocity) {
            return
        }
        
        resistanceConsumed = 0
        if currentState == .Contracting || currentState == .Expanding || velocity > minVelocity {
            var contracting: Bool = currentState == .Contracting
            
            if velocity > minVelocity { // if velocity is greater than minVelocity we expand
                contracting = false
            }
            
            let deltaY = navBarController.snap(contracting, completion: nil)
            let tabBarShouldContract = deltaY < 0
            _ = tabBarController?.snap(tabBarShouldContract, completion: nil)
            
            var newContentOffset = scrollView.contentOffset
            newContentOffset.y -= deltaY
            
            let contentInset = scrollViewContentInset
            let top = contentInset.top + deltaY
            
            UIView.animate(withDuration: 0.2, animations: {
                self.updateScrollContentInsetTop(top)
                self.scrollView.contentOffset = newContentOffset
            })
            
            previousYOffset = CGFloat.nan
        }
    }
    
    //MARK: Scroll handling
    
    @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer){
        switch gesture.state {
        case .began:
            topInset = navBarController.view.frame.size.height + extensionController.view.bounds.size.height + statusBarHeight()
            handleScrolling()
        case .changed:
            handleScrolling()
        default:
            let velocity = gesture.velocity(in: scrollView).y
            handleScrollingEnded(velocity)
        }
    }
    
    //MARK: UIGestureRecognizerDelegate
    
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    //MARK: iOS 11 handling (adjustedContentInset, safeAreaInsets)
    
    var scrollViewContentInset: UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return scrollView.adjustedContentInset
        } else {
            return scrollView.contentInset
        }
    }
    
    fileprivate func adjustTopInset(_ top: CGFloat) -> CGFloat {
        if #available(iOS 11.0, *) {
            return top - scrollView.safeAreaInsets.top  // subtract safeAreaInsets for ios11
        }
        return top
    }
}

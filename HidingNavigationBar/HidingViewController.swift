//
//  HidingViewController.swift
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

class HidingViewController {
    
    var child: HidingViewController?
    var navSubviews: [UIView]?
    var view: UIView
    
    var expandedCenter: ((UIView) -> CGPoint)?
    
    var alphaFadeEnabled = false
    var contractsUpwards = true
    
    init(view: UIView) {
        self.view = view
    }
    
    init() {
        view = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        view.backgroundColor = UIColor.clear
        view.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
    }
    
    func expandedCenterValue() -> CGPoint {
        if let expandedCenter = expandedCenter {
            return expandedCenter(view)
        }
        return CGPoint(x: 0, y: 0)
    }
    
    func contractionAmountValue() -> CGFloat {
        return view.bounds.height
    }
    
    func contractedCenterValue() -> CGPoint {
        if contractsUpwards {
            return CGPoint(x: expandedCenterValue().x, y: expandedCenterValue().y - contractionAmountValue())
        } else {
            return CGPoint(x: expandedCenterValue().x, y: expandedCenterValue().y + contractionAmountValue())
        }
    }
    
    func isContracted() -> Bool {
        return Float(fabs(view.center.y - contractedCenterValue().y)) < .ulpOfOne
    }
    
    func isExpanded() -> Bool {
        return Float(fabs(view.center.y - expandedCenterValue().y)) < .ulpOfOne
    }
    
    func totalHeight() -> CGFloat {
        let height = expandedCenterValue().y - contractedCenterValue().y
        if let child = child {
            return child.totalHeight() + height
        }
        return height
    }
    
    func setAlphaFadeEnabled(_ alphaFadeEnabled: Bool) {
        self.alphaFadeEnabled = alphaFadeEnabled
        
        if !alphaFadeEnabled {
            updateSubviewsToAlpha(1.0)
        }
    }
    
    func updateYOffset(_ delta: CGFloat) -> CGFloat {
        var deltaY = delta
        if child != nil && deltaY < 0 {
            deltaY = child!.updateYOffset(deltaY)
            child!.view.isHidden = (deltaY) < 0;
        }
        
        var newYOffset = view.center.y + deltaY
        var newYCenter = max(min(expandedCenterValue().y, newYOffset), contractedCenterValue().y)
        if contractsUpwards == false {
            newYOffset = view.center.y - deltaY
            newYCenter = min(max(expandedCenterValue().y, newYOffset), contractedCenterValue().y)
        }
        
        view.center = CGPoint(x: view.center.x, y: newYCenter)
        
        if alphaFadeEnabled {
            var newAlpha: CGFloat = 1.0 - (expandedCenterValue().y - view.center.y) * 2 / contractionAmountValue()
            newAlpha = CGFloat(min(max(.ulpOfOne, Float(newAlpha)), 1.0))
            
            updateSubviewsToAlpha(newAlpha)
        }
        
        var residual = newYOffset - newYCenter
        
        if (child != nil && deltaY > 0 && residual > 0) {
            residual = child!.updateYOffset(residual)
            child!.view.isHidden = residual - (newYOffset - newYCenter) > 0
        }
        
        return residual;
    }
    
    func snap(_ contract: Bool, completion:(() -> Void)!) -> CGFloat {
        var deltaY: CGFloat = 0
        
        UIView.animate(withDuration: 0.2, delay: 0, options: UIView.AnimationOptions(), animations: {
            if let child = self.child {
                if contract && child.isContracted() {
                    deltaY = self.contract()
                } else {
                    deltaY = self.expand()
                }
            } else {
                if contract {
                    deltaY = self.contract()
                } else {
                    deltaY = self.expand()
                }
            }
        }) { (success: Bool) -> Void in
            if completion != nil{
                completion();
            }
        }
        
        return deltaY;
    }
    
    func expand() -> CGFloat {
        view.isHidden = false
        
        if alphaFadeEnabled {
            updateSubviewsToAlpha(1)
            navSubviews = nil
        }
        
        var amountToMove = expandedCenterValue().y - view.center.y
        
        view.center = expandedCenterValue()
        if let child = child {
            amountToMove += child.expand()
        }
        
        return amountToMove;
    }
    
    func contract() -> CGFloat {
        if alphaFadeEnabled {
            updateSubviewsToAlpha(0)
        }
        
        let amountToMove = contractedCenterValue().y - view.center.y
        
        view.center = contractedCenterValue()
        
        return amountToMove;
    }
    
    // MARK: - Private methods
    
    // Recursively applies an operation to all views in a view hierarchy
    fileprivate func applyToViewHierarchy(rootView: UIView, operation: (UIView) -> Void) {
        operation(rootView)
        rootView.subviews.forEach { view in
            applyToViewHierarchy(rootView: view, operation: operation)
        }
    }
    
    fileprivate func updateSubviewsToAlpha(_ alpha: CGFloat) {
        if navSubviews == nil {
            navSubviews = []
            
            // loops through and subview and save the visible ones in navSubviews array
            for subView in view.subviews {
                let isBackgroundView = subView === view.subviews[0]
                let isViewHidden = subView.isHidden || Float(subView.alpha) < .ulpOfOne
                
                if isBackgroundView == false && isViewHidden == false {
                    navSubviews?.append(subView)
                }
            }
        }
        navSubviews?.forEach { subView in
            applyToViewHierarchy(rootView: subView) { view in
                view.alpha = alpha
            }
        }
    }
}

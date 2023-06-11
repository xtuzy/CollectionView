//
//  CollectionViewDocumentView.swift
//  Lingo
//
//  Created by Wesley Byrne on 3/30/16.
//  Copyright © 2016 The Noun Project. All rights reserved.
//

import Foundation

extension Set {
  
    mutating func insertOverwrite(_ element: Element) {
        self.remove(element)
        self.insert(element)
    }
    
    mutating func formUnionOverwrite<S: Sequence>(_ other: S) where S.Iterator.Element == Element {
        self.subtract(other)
        self.formUnion(other)
    }
    
    func unionOverwrite<S: Sequence>(_ other: S) -> Set<Element> where S.Iterator.Element == Element {
        let new = self.subtracting(other)
        return new.union(other)
    }
}

internal struct ItemUpdate: Hashable {
  //操作类型  
  enum `Type` {
        case insert
        case remove
        case update
    }
    //更新的View
    let view: CollectionReusableView
  //布局属性
    let _attrs: CollectionViewLayoutAttributes?
  //哪一个Item
    let indexPath: IndexPath
    let type: Type
    let identifier: SupplementaryViewIdentifier?
    
    fileprivate var attrs: CollectionViewLayoutAttributes {
        if let a = _attrs { return a }
        //获得所属的collectionview
        guard let cv = self.view.collectionView else {
            preconditionFailure("CollectionView Error: A view was returned without using a deque() method.")
        }
        var a: CollectionViewLayoutAttributes?
        if let id = identifier {
            a = cv.layoutAttributesForSupplementaryView(ofKind: id.kind, at: indexPath)
        } else if view is CollectionViewCell {
          //是cell就获取item的属性, 获取是layout中的, 其存储了每个Item的
            a = cv.layoutAttributesForItem(at: indexPath)
        }
        a = a ?? view.attributes
        precondition(a != nil, "Internal error: unable to find layout attributes for view at \(indexPath)")
        return a!
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(view)
    }
//    var hashValue: Int {
//        return view.hashValue
//    }

    init(cell: CollectionViewCell, attrs: CollectionViewLayoutAttributes, type: Type) {
        self.view = cell
        self._attrs = attrs
        self.indexPath = attrs.indexPath
        self.identifier = nil
        self.type = type
    }
    init(cell: CollectionViewCell, indexPath: IndexPath, type: Type) {
        precondition(type != .remove, "Internal CollectionView Error: Cannot use UpdateItem(cell:indexPath:type:) for type remove")
        self.view = cell
        self._attrs = nil
        self.indexPath = indexPath
        self.identifier = nil
        self.type = type
    }
    init(view: CollectionReusableView, attrs: CollectionViewLayoutAttributes, type: Type, identifier: SupplementaryViewIdentifier) {
        self.view = view
        self._attrs = attrs
        self.indexPath = attrs.indexPath
        self.identifier = identifier
        self.type = type
    }
    init(view: CollectionReusableView, indexPath: IndexPath, type: Type, identifier: SupplementaryViewIdentifier) {
        precondition(type != .remove, "Internal CollectionView Error: Cannot use UpdateItem(view:indexPath:type:identifier) for type remove")
        self.view = view
        self._attrs = nil
        self.indexPath = indexPath
        self.identifier = identifier
        self.type = type
    }
    
    static func == (lhs: ItemUpdate, rhs: ItemUpdate) -> Bool {
        return lhs.view == rhs.view
    }
}

final public class CollectionViewDocumentView: NSView {

    public override var isFlipped: Bool { return true }
    
//    override public class func isCompatibleWithResponsiveScrolling() -> Bool { return true }
    
    fileprivate var collectionView: CollectionView {
        return self.superview!.superview as! CollectionView
    }
    
    public override func adjustScroll(_ newVisible: NSRect) -> NSRect {
//        super.adjustScroll(newVisible)
//        if self.collectionView.isScrolling == false {
//            
//        }
//        var rect = newVisible
//        rect.origin.x = 5 * rect.origin.x.truncatingRemainder(dividingBy: 5)
//        rect.origin.y = 5 * rect.origin.y.truncatingRemainder(dividingBy: 5)
        return newVisible
    }
    //准备好的, 也就是上一次的矩形
    var preparedRect = CGRect.zero
    //上一次显示的Cell
    var preparedCellIndex = IndexedSet<IndexPath, CollectionViewCell>()
    var preparedSupplementaryViewIndex = [SupplementaryViewIdentifier: CollectionReusableView]()
    
    func reset() {
        //把之前显示的的cell移除控件树, 回收
        for cell in preparedCellIndex {
            cell.1.removeFromSuperview()
            self.collectionView.enqueueCellForReuse(cell.1)
            self.collectionView.delegate?.collectionView?(self.collectionView, didEndDisplayingCell: cell.1, forItemAt: cell.0)
        }
        preparedCellIndex.removeAll()
        for view in preparedSupplementaryViewIndex {
            view.1.removeFromSuperview()
            let id = view.0
            self.collectionView.enqueueSupplementaryViewForReuse(view.1, withIdentifier: id)
            self.collectionView.delegate?.collectionView?(self.collectionView,
                                                          didEndDisplayingSupplementaryView: view.1,
                                                          ofElementKind: id.kind,
                                                          at: id.indexPath!)
        }
        for v in self.subviews where v is CollectionReusableView {
            v.removeFromSuperview()//其它没显示的移除空间树
        }
        for v in self.collectionView.floatingContentView.subviews where v is CollectionReusableView {
            v.removeFromSuperview()
        }
        preparedSupplementaryViewIndex.removeAll()
        self.preparedRect = CGRect.zero//重置显示区域
    }
    
    fileprivate var extending: Bool = false
    
    func extendPreparedRect(_ amount: CGFloat) {
        if self.preparedRect.isEmpty { return }
        self.extending = true
        self.prepareRect(preparedRect.insetBy(dx: -amount, dy: -amount), completion: nil)
        self.extending = false
    }
    
    var pendingUpdates: [ItemUpdate] = []
    
    func prepareRect(_ rect: CGRect, animated: Bool = false, force: Bool = false, completion: AnimationCompletion? = nil) {
        //与SCrollView相交的矩形
        let _rect = rect.intersection(CGRect(origin: CGPoint.zero, size: self.frame.size))
        
        if !force && !self.preparedRect.isEmpty && self.preparedRect.contains(_rect) {
            
            for _view in self.preparedSupplementaryViewIndex {
                let view = _view.1
                let id = _view.0
                guard let ip = id.indexPath,
                    var attrs = self.collectionView.layoutAttributesForSupplementaryView(ofKind: id.kind, at: ip) else { continue }
                
                guard attrs.frame.intersects(self.preparedRect) else {
                    self.collectionView.delegate?.collectionView?(self.collectionView,
                                                                  didEndDisplayingSupplementaryView: view,
                                                                  ofElementKind: id.kind,
                                                                  at: ip)
                    self.preparedSupplementaryViewIndex[id] = nil
                    self.collectionView.enqueueSupplementaryViewForReuse(view, withIdentifier: id)
                    continue
                }
                
                if attrs.floating == true {
                    if view.superview != self.collectionView._floatingSupplementaryView {
                        view.removeFromSuperview()
                        self.collectionView._floatingSupplementaryView.addSubview(view)
                    }
                    attrs = attrs.copy()
                    attrs.frame = self.collectionView._floatingSupplementaryView.convert(attrs.frame, from: self)
                    view.apply(attrs, animated: false)
                } else if view.superview == self.collectionView._floatingSupplementaryView {
                    view.removeFromSuperview()
                    self.collectionView.contentDocumentView.addSubview(view)
                    view.apply(attrs, animated: false)
                }
            }
            completion?(true)
            return
        }
        
        let supps = self.layoutSupplementaryViewsInRect(_rect, animated: animated, forceAll: force)
        let items = self.layoutItemsInRect(_rect, animated: animated, forceAll: force)
        let sRect = supps.rect
        let iRect = items.rect
        
        var newRect = sRect.union(iRect)
        if !self.preparedRect.isEmpty && self.preparedRect.intersects(newRect) {
            newRect = newRect.union(self.preparedRect)
        }
        self.preparedRect = newRect//新的显示区域
        
        var updates = Set<ItemUpdate>(supps.updates)
        updates.formUnion(pendingUpdates)
        updates.formUnionOverwrite(items.updates)

        pendingUpdates.removeAll()
        
        self.applyUpdates(updates, animated: animated, completion: completion)
    }
    //在某矩形里布局Item
    fileprivate func layoutItemsInRect(_ rect: CGRect, animated: Bool = false, forceAll: Bool = false) -> (rect: CGRect, updates: [ItemUpdate]) {
        var _rect = rect

        var updates = [ItemUpdate]()
        //之前显示的
        let oldIPs = self.preparedCellIndex.indexSet
        //该矩形内的items
        var inserted = Set(self.collectionView.indexPathsForItems(in: rect))
        let removed = oldIPs.removing(inserted)//不要显示了的
        let updated = inserted.remove(oldIPs)//新的要显示的
        
        if !extending {
            var removedRect = CGRect.zero
            for ip in removed {
                if let cell = self.collectionView.cellForItem(at: ip) {
                    if removedRect.isEmpty { removedRect = cell.frame } else { removedRect = removedRect.union(cell.frame) }
                    
                    cell.layer?.zPosition = 0
                    if animated, let attrs = self.collectionView.layoutAttributesForItem(at: ip) ?? cell.attributes {//动画
                        self.preparedCellIndex[ip] = nil//从之前显示的集合移除
                        updates.append(ItemUpdate(cell: cell, attrs: attrs, type: .remove))//添加到updates集合
                    } else {//没有动画就直接回收
                        self.collectionView.enqueueCellForReuse(cell)
                        self.preparedCellIndex[ip] = nil
                        self.collectionView.delegate?.collectionView?(self.collectionView, didEndDisplayingCell: cell, forItemAt: ip)
                    }
                }
            }
            
            if !removedRect.isEmpty {
                if self.collectionView.collectionViewLayout.scrollDirection == .vertical {
                    let edge = self.visibleRect.origin.y > removedRect.origin.y ? CGRectEdge.minYEdge : CGRectEdge.maxYEdge
                    self.preparedRect = self.preparedRect.subtracting(removedRect, edge: edge)
                } else {
                    let edge = self.visibleRect.origin.x > removedRect.origin.x ? CGRectEdge.minXEdge : CGRectEdge.maxXEdge
                    self.preparedRect = self.preparedRect.subtracting(removedRect, edge: edge)
                }
            }
        }
        
        for ip in inserted {//全部要显示的
            guard let attrs = self.collectionView.collectionViewLayout.layoutAttributesForItem(at: ip) else { continue }
            let cell = self.collectionView._loadCell(at: ip)
            
            cell.setSelected(self.collectionView.itemAtIndexPathIsSelected(ip), animated: false)
//            _rect = _rect.union(attrs.frame.insetBy(dx: -1, dy: -1) )
            
            self.collectionView.delegate?.collectionView?(self.collectionView, willDisplayCell: cell, forItemAt: ip)
            cell.viewWillDisplay()
            if cell.superview == nil {
                self.addSubview(cell)//添加cell到scrollview
            }
            if animated {//如果要动画
                cell.apply(attrs, animated: false)//设置位置等属性
                cell.isHidden = true//先设置不可见
                cell.alphaValue = 0
            }
            updates.append(ItemUpdate(cell: cell, attrs: attrs, type: .insert))//添加到updates集合
            
            self.preparedCellIndex[ip] = cell//添加到要显示集合
        }

        if forceAll {//没懂为什么还要算一次, 前面不是已经算了新的么
            for ip in updated {//新的
                if let attrs = self.collectionView.collectionViewLayout.layoutAttributesForItem(at: ip),
                let cell = preparedCellIndex[ip] {
                    _rect = _rect.union(attrs.frame)//新的的矩形取并集, 不理解为什么, 获取的时候不应该计算了么
                    updates.append(ItemUpdate(cell: cell, attrs: attrs, type: .update))
                }
            }
        }

        return (_rect, updates)
    }
    
    fileprivate func layoutSupplementaryViewsInRect(_ rect: CGRect, animated: Bool = false, forceAll: Bool = false) -> (rect: CGRect, updates: [ItemUpdate]) {
        var _rect = rect
        
        var updates = [ItemUpdate]()
        
        let oldIdentifiers = Set(self.preparedSupplementaryViewIndex.keys)
        var inserted = self.collectionView._identifiersForSupplementaryViews(in: rect)
        let removed = oldIdentifiers.removing(inserted)
        let updated = inserted.remove(oldIdentifiers)
        
        if !extending {
            var removedRect = CGRect.zero
            
            for identifier in removed {
                if let view = self.preparedSupplementaryViewIndex[identifier] {
                    
                    if removedRect.isEmpty { removedRect = view.frame } else { removedRect = removedRect.union(view.frame) }
                    
                    view.layer?.zPosition = -100
                    
                    if animated,
                        var attrs = self.collectionView.collectionViewLayout
                            .layoutAttributesForSupplementaryView(ofKind: identifier.kind,
                                                                  at: identifier.indexPath!) ?? view.attributes {
                        if attrs.floating == true {
                            if view.superview != self.collectionView._floatingSupplementaryView {
                                view.removeFromSuperview()
                                self.collectionView._floatingSupplementaryView.addSubview(view)
                            }
                            attrs = attrs.copy()
                            attrs.frame = self.collectionView._floatingSupplementaryView.convert(attrs.frame, from: self)
                        } else if view.superview == self.collectionView._floatingSupplementaryView {
                            view.removeFromSuperview()
                            self.collectionView.contentDocumentView.addSubview(view)
                        }
                        updates.append(ItemUpdate(view: view, attrs: attrs, type: .remove, identifier: identifier))
                    } else {
                        self.collectionView.delegate?.collectionView?(self.collectionView,
                                                                      didEndDisplayingSupplementaryView: view,
                                                                      ofElementKind: identifier.kind,
                                                                      at: identifier.indexPath!)
                        self.collectionView.enqueueSupplementaryViewForReuse(view, withIdentifier: identifier)
                    }
                    self.preparedSupplementaryViewIndex[identifier] = nil
                }
            }
            if !removedRect.isEmpty {
                if self.collectionView.collectionViewLayout.scrollDirection == .vertical {
                    let edge = self.visibleRect.origin.y > removedRect.origin.y ? CGRectEdge.minYEdge : CGRectEdge.maxYEdge
                    self.preparedRect = self.preparedRect.subtracting(removedRect, edge: edge)
                } else {
                    let edge = self.visibleRect.origin.x > removedRect.origin.x ? CGRectEdge.minXEdge : CGRectEdge.maxXEdge
                    self.preparedRect = self.preparedRect.subtracting(removedRect, edge: edge)
                }
            }
        }
        
        for identifier in inserted {
            
            if let view = self.preparedSupplementaryViewIndex[identifier]
                ?? self.collectionView.dataSource?.collectionView?(self.collectionView,
                                                                   viewForSupplementaryElementOfKind: identifier.kind,
                                                                   at: identifier.indexPath!) {
                
                assert(view.collectionView != nil, "Attempt to insert a view without using deque:")
                
                guard var attrs = self.collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(ofKind: identifier.kind,
                                                                                                                at: identifier.indexPath!)
                    else { continue }
                _rect = _rect.union(attrs.frame)
                
                self.collectionView.delegate?.collectionView?(self.collectionView,
                                                              willDisplaySupplementaryView: view,
                                                              ofElementKind: identifier.kind,
                                                              at: identifier.indexPath!)
                view.viewWillDisplay()
                if view.superview == nil {
                    if attrs.floating == true {
                        self.collectionView._floatingSupplementaryView.addSubview(view)
                    } else {
                        self.addSubview(view)
                    }
                }
                if view.superview == self.collectionView._floatingSupplementaryView {
                    attrs = attrs.copy()
                    attrs.frame = self.collectionView._floatingSupplementaryView.convert(attrs.frame, from: self)
                }
                if animated {
                    view.isHidden = true
                    view.frame = attrs.frame
                }
                updates.append(ItemUpdate(view: view, attrs: attrs, type: .insert, identifier: identifier))
                self.preparedSupplementaryViewIndex[identifier] = view
            }
        }
        
        for id in updated {
            if let view = preparedSupplementaryViewIndex[id],
                var attrs = self.collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(ofKind: id.kind, at: id.indexPath!) {
                _rect = _rect.union(attrs.frame)
                
                if attrs.floating == true {
                    if view.superview != self.collectionView._floatingSupplementaryView {
                        view.removeFromSuperview()
                        self.collectionView._floatingSupplementaryView.addSubview(view)
                    }
                    attrs = attrs.copy()
                    attrs.frame = self.collectionView._floatingSupplementaryView.convert(attrs.frame, from: self)
                } else if view.superview == self.collectionView._floatingSupplementaryView {
                    view.removeFromSuperview()
                    self.collectionView.contentDocumentView.addSubview(view)
                }
                updates.append(ItemUpdate(view: view, attrs: attrs, type: .update, identifier: id))
            }
        }
        
        return (_rect, updates)
    }
    
    internal func applyUpdates(_ updates: Set<ItemUpdate>, animated: Bool, completion: AnimationCompletion?) {
        
        let _updates = updates
        
        if animated {//动画
            let _animDuration = self.collectionView.animationDuration
            let _allowImplicitAnimations = self.collectionView.allowImplicitAnimations

            // Dispatch to allow frame changes from reloadLayout() to apply before beginning the animations
            DispatchQueue.main.async { [unowned self] in
                var removals = [ItemUpdate]()
                NSAnimationContext.runAnimationGroup({ (context) -> Void in
                    context.duration = _animDuration
                    context.allowsImplicitAnimation = _allowImplicitAnimations
                    context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
                    
                    for item in _updates {
                        var attrs = item.attrs
                        if item.type == .remove {
                            removals.append(item)
                            attrs = attrs.copy()
                            attrs.alpha = 0
                        }
                        item.view.apply(attrs, animated: true)//设置cell
                        if item.type == .insert {
                            item.view.viewDidDisplay()
                        }
                    }
                }) { () -> Void in
                    self.finishRemovals(removals)//结束时回收
                    completion?(true)
                }
             }
        } else {//不动画
            for item in _updates {
                if item.type == .remove {
                    removeItem(item)//回收
                } else {//插入和更新
                    let attrs = item.attrs
                    item.view.apply(attrs, animated: false)//对cell直接设置位置等属性
                    if item.type == .insert {
                        item.view.viewDidDisplay()
                    }
                }
            }
            completion?(!animated)
        }
    }
    
    fileprivate func finishRemovals(_ removals: [ItemUpdate]) {
        for item in removals {
            removeItem(item)//回收cell
        }
    }
    func removeItem(_ item: ItemUpdate) {
        if let cell = item.view as? CollectionViewCell {
            self.collectionView.delegate?.collectionView?(self.collectionView, didEndDisplayingCell: cell, forItemAt: cell.attributes!.indexPath)
            self.collectionView.enqueueCellForReuse(cell)//回收
        } else if let id = item.identifier {
            self.collectionView.delegate?.collectionView?(self.collectionView,
                                                          didEndDisplayingSupplementaryView: item.view,
                                                          ofElementKind: id.kind,
                                                          at: id.indexPath!)
            self.collectionView.enqueueSupplementaryViewForReuse(item.view, withIdentifier: id)
        } else {
            log.error("Invalid item for removal")
        }
    }
    
}

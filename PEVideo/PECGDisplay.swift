//
//  PECGDisplay.swift
//  PEVideo
//
//  Created by hao yin on 2020/11/20.
//

import AVFoundation
import CoreImage
import UIKit

public class PEVideoLayer:CALayer,PEMTVideoPlayerDisplay{
    public func handleThumbnail(img: CGImage) {
        let ci = CIImage(cgImage: img)
        self.renderCIImage(img: ci)
    }
    public var filter:functionFilter?
    public var externOffset:CGSize = .zero
    public func handlePixelBuffer(pixel: CVPixelBuffer) {
        let img = CIImage(cvPixelBuffer: pixel)
        self.renderCIImage(img: img)
        
    }
    func renderCIImage(img:CIImage){
        if let f = self.filter{
            if let oimg = f(img){
                self.contents = PEVideoLayer.context .createCGImage(oimg, from: img.extent.insetBy(dx: externOffset.width, dy: externOffset.height))
            }
        }else{
            self.contents = PEVideoLayer.context .createCGImage(img, from: img.extent.insetBy(dx: externOffset.width, dy: externOffset.height))
        }
    }
    public override init() {
        super.init()
        self.contentsGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        super.init()
        self.contentsGravity = .resizeAspect
    }
    public override init(layer: Any) {
        super.init(layer: layer)
        if let a = layer as? PEVideoLayer{
            self.filter = a.filter
            self.externOffset = a.externOffset
        }
    }
    
    public static var context:CIContext = {
        if let dev = MTLCreateSystemDefaultDevice(){
            return CIContext(mtlDevice: dev)
        }else{
           return CIContext()
        }
    }()
}
public func +<A,B,C>(left:@escaping (A)->B,right:@escaping (B)->C)->(A)->C{
    return { i in
        return right(left(i))
    }
}
public typealias functionFilter = (CIImage?)->CIImage?

extension CIFilter{
    var functionFilter:functionFilter{
        return { img in
            if let wi = img{
                self.setValue(wi, forKey: kCIInputImageKey)
            }
            return self.outputImage
        }
    }
}

public class PEMTVideoSimpleView:UIView {
    static var player:PEMTVideoPlayer?
    var real:PEVideoLayer
    @objc public var videoGravity:CALayerContentsGravity{
        get{
            return self.real.contentsGravity
        }
        set{
            self.real.contentsGravity = newValue;
        }
    }
    @objc public func load(item:AVAsset){
        if let p = PEMTVideoView.player{
            p.removeAllDisplay()
            p.stop()
            p.replaceCurrent(asset: item)
        }else{
            PEMTVideoView.player = PEMTVideoPlayer(asset: item)
        }
        PEMTVideoView.player?.addDisplay(display: self.real)
        self.delegate?.videoPlayer?(player: self, state: PEMTVideoView.player!.state)
        self.layer.addSublayer(real)
        PEMTVideoView.player?.callback = { [weak self] p in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, percent: p)
            }
        }
        PEMTVideoView.player?.endCallBack = { [weak self] b in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, success: b)
            }
        }
        PEMTVideoView.player?.stateChange = { [weak self] state in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, state: state)
            }
        }
        self.delegate?.videoPlayer?(player: self, percent: 0)

    }
    @objc public override init(frame: CGRect) {
        self.real = PEVideoLayer()
        super.init(frame: frame)
    }
    
    @objc required init?(coder: NSCoder) {
        self.real = PEVideoLayer()
        super.init(coder: coder)
    }
    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.real.frame = self.bounds
        CATransaction.commit()
    }
    @objc public func replay(){
        PEMTVideoView.player?.play()
    }
    @objc public func pause(){
        PEMTVideoView.player?.pause()
    }
    @objc public var percent:Float{
        get{
            return PEMTVideoView.player?.percent ?? 0
        }
        set{
            PEMTVideoView.player?.seek(percent: newValue)
        }
    }
    @objc public func cancel(){
        PEMTVideoView.player?.stop()
    }
    @objc public func mute(bool:Bool){
        PEMTVideoView.player?.mute(state: bool)
    }
    @objc public weak var delegate:PEMTVideoViewDelegate?
    
    @objc public static func createItem(url:URL)->AVPlayerItem{
        let i = AVPlayerItem(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: ["isPlayable"])
        return i
    }
}




public class PEMTVideoView:PEMTVideoSimpleView{
    public override class var layerClass: AnyClass{
        return PEVideoLayer.self
    }
    var gaussianRadius:CGFloat = 10
   
    var backLayer:PEVideoLayer{
        return self.layer as! PEVideoLayer
    }
    @objc public override func load(item:AVAsset){
        if let p = PEMTVideoView.player{
            p.removeAllDisplay()
            p.replaceCurrent(asset: item)
        }else{
            PEMTVideoView.player = PEMTVideoPlayer(asset: item)
        }
        PEMTVideoView.player?.addDisplay(display: self.backLayer)
        PEMTVideoView.player?.addDisplay(display: self.real)
        self.delegate?.videoPlayer?(player: self, state: PEMTVideoView.player!.state)
        let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius":6])!
        let filter2 = CIFilter(name: "CIExposureAdjust", parameters: ["inputEV":-3])!
        self.backLayer.filter = filter.functionFilter + filter2.functionFilter
        self.backLayer.externOffset = CGSize(width: self.gaussianRadius, height: self.gaussianRadius)
        self.backLayer.contentsGravity = .resizeAspectFill
        self.layer.addSublayer(real)
        PEMTVideoView.player?.callback = { [weak self] p in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, percent: p)
            }
        }
        PEMTVideoView.player?.endCallBack = { [weak self] b in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, success: b)
            }
        }
        PEMTVideoView.player?.stateChange = { [weak self] state in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, state: state)
            }
        }
        self.delegate?.videoPlayer?(player: self, percent: 0)

    }
    @objc public override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    @objc required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.real.frame = self.bounds
        CATransaction.commit()
    }
}

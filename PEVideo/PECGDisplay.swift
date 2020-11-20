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
    public var index: UInt32 = 0
    
    public var backgroundfilter: functionFilter?
    
    public func loadLayer(parant: CALayer) {
        parant.addSublayer(self)
        self.zPosition = CGFloat(index) - 100;
    }
    
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
        if let p = PECGVideoView.player{
            p.removeAllDisplay()
            p.stop()
            p.replaceCurrent(asset: item)
        }else{
            PECGVideoView.player = PEMTVideoPlayer(asset: item)
        }
        PECGVideoView.player?.addDisplay(display: self.real)
        self.delegate?.videoPlayer?(player: self, state: PECGVideoView.player!.state)
        self.layer.addSublayer(real)
        PECGVideoView.player?.callback = { [weak self] p in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, percent: p)
            }
        }
        PECGVideoView.player?.endCallBack = { [weak self] b in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, success: b)
            }
        }
        PECGVideoView.player?.stateChange = { [weak self] state in
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
        PECGVideoView.player?.play()
    }
    @objc public func pause(){
        PECGVideoView.player?.pause()
    }
    @objc public var percent:Float{
        get{
            return PECGVideoView.player?.percent ?? 0
        }
        set{
            PECGVideoView.player?.seek(percent: newValue)
        }
    }
    @objc public func cancel(){
        PECGVideoView.player?.stop()
    }
    @objc public func mute(bool:Bool){
        PECGVideoView.player?.mute(state: bool)
    }
    @objc public weak var delegate:PEMTVideoViewDelegate?
    
    @objc public static func createItem(url:URL)->AVPlayerItem{
        let i = AVPlayerItem(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: ["isPlayable"])
        return i
    }
}




public class PECGVideoView:PEMTVideoSimpleView{
  
    var gaussianRadius:CGFloat = 10
   
    var backLayer:PEVideoLayer = PEVideoLayer()
    @objc public override func load(item:AVAsset){
        if let p = PECGVideoView.player{
            p.removeAllDisplay()
            p.replaceCurrent(asset: item)
        }else{
            PECGVideoView.player = PEMTVideoPlayer(asset: item)
        }
        PECGVideoView.player?.addDisplay(display: self.backLayer)
        PECGVideoView.player?.addDisplay(display: self.real)
        self.delegate?.videoPlayer?(player: self, state: PECGVideoView.player!.state)
        let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius":self.gaussianRadius])!
        let filter2 = CIFilter(name: "CIExposureAdjust", parameters: ["inputEV":-3])!
        self.backLayer.filter = filter.functionFilter + filter2.functionFilter
        self.backLayer.externOffset = CGSize(width: self.gaussianRadius, height: self.gaussianRadius)
        self.backLayer.contentsGravity = .resizeAspectFill
        self.layer.addSublayer(self.backLayer)
        self.backLayer.addSublayer(real)
        
        PECGVideoView.player?.callback = { [weak self] p in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, percent: p)
            }
        }
        PECGVideoView.player?.endCallBack = { [weak self] b in
            if let ws = self{
                ws.delegate?.videoPlayer?(player: ws, success: b)
            }
        }
        PECGVideoView.player?.stateChange = { [weak self] state in
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
        self.real.zPosition = -1
        self.backLayer.frame = self.bounds
        self.backLayer.zPosition = -2
        CATransaction.commit()
    }
}

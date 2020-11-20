//
//  PEMTDisplay.swift
//  PEVideo
//
//  Created by hao yin on 2020/11/20.
//

import UIKit
import Metal
import AVFoundation
import CoreImage

public class PEGPULayer:CAMetalLayer,PEMTVideoPlayerDisplay {

    public var index: UInt32 = 0
    
    public func loadLayer(parant: CALayer) {
        parant.addSublayer(self)
        parant.insertSublayer(self, at: index)
        self.zPosition = CGFloat(index) - 100;
    }
    public var filter:functionFilter?
    public var backgroundfilter:functionFilter?
    public var externOffset:CGSize = .zero
    public override init() {
        super.init()
        self.contentsScale = UIScreen.main.scale;
        self.framebufferOnly = false
    }
    public lazy var commandQueue:MTLCommandQueue? = {
        return self.device?.makeCommandQueue()
    }()
    
    public lazy var context:CIContext? = {
        if let queue = self.commandQueue{
            if #available(iOS 13.0, *) {
                return CIContext(mtlCommandQueue: queue)
            }
        }
        if let ctx = self.device{
            return CIContext(mtlDevice: ctx)
        }
        return nil
    }()
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.framebufferOnly = false
    }
    public func handlePixelBuffer(pixel: CVPixelBuffer) {
        let img = CIImage(cvPixelBuffer: pixel)
        self.renderCIImage(img: img)
    }
    func renderCIImage(img:CIImage){
        let rect = CGRect(x: 0, y: 0, width: self.bounds.size.width * UIScreen.main.scale, height: self.bounds.size.height * UIScreen.main.scale)
        if let drawable = self.nextDrawable(){
            let buffer = self.commandQueue?.makeCommandBuffer()
            let texture = drawable.texture
            if let backfilter = self.backgroundfilter{
                if let backimg = backfilter(img){
                    let tram = self.imageTransform(img: backimg,gravity:.resizeAspectFill,originRect: img.extent)
                    self.context?.render(tram, to: texture, commandBuffer: buffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
                }
            }else{
                let img = CIImage(color: CIColor.white)
                self.context?.render(img, to: texture, commandBuffer: buffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
            }
            if let new = self.filter?(img){
                let tram = self.imageTransform(img: new,gravity: self.contentsGravity,originRect: img.extent)
                
                self.context?.render(tram, to: texture, commandBuffer: buffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
            }else{
                let tram = self.imageTransform(img: img,gravity:self.contentsGravity,originRect: img.extent)
                self.context?.render(tram, to: texture, commandBuffer: buffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
            }
            buffer?.present(drawable)
            
            buffer?.commit()
        }
    }
    func imageTransform(img:CIImage,gravity:CALayerContentsGravity,originRect:CGRect)->CIImage{
        let rect = originRect
        let pxw = self.frame.width * UIScreen.main.scale
        let pxh = self.frame.height * UIScreen.main.scale
        
        let wratio = pxw / rect.width
        let hratio = pxh / rect.height
        if gravity == .resizeAspectFill{
            
            let dw = pxw - rect.width * max(wratio, hratio)
            let dh = pxh - rect.height * max(wratio, hratio)
            return img.transformed(by: CGAffineTransform(translationX: dw / 2, y: dh / 2).scaledBy(x: max(wratio, hratio), y: max(wratio, hratio)))
        }else{
            let dw = pxw - rect.width * min(wratio, hratio)
            let dh = pxh - rect.height * min(wratio, hratio)
            return img.transformed(by: CGAffineTransform(translationX: dw / 2, y: dh / 2).scaledBy(x: min(wratio, hratio), y: min(wratio, hratio)))
        }
        
    }
    public func handleThumbnail(img: CGImage) {
        let iimg = CIImage(cgImage: img)
        self.renderCIImage(img: iimg)
    }
}


public class PEMTGPUView:UIView {
    var real:PEMTVideoPlayerDisplay
    var back:PEMTVideoPlayerDisplay?
    var useFilter:Bool{
        get{
            return self.real.filter != nil
        }
        set{
            if(newValue){
                let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius":6])!
                let filter2 = CIFilter(name: "CIExposureAdjust", parameters: ["inputEV":-3])!
                self.real.backgroundfilter = filter.functionFilter + filter2.functionFilter
                self.back?.filter = filter.functionFilter + filter2.functionFilter
            }else{
                self.real.backgroundfilter = nil
                self.back?.filter = nil
                self.back?.filter = nil
            }
            
        }
    }
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
        if let b = self.back{
            PECGVideoView.player?.addDisplay(display:b)
        }
        self.delegate?.videoPlayer?(player: self, state: PECGVideoView.player!.state)
        if let b = self.back{
            b.loadLayer(parant: self.layer)
        }
        real.loadLayer(parant: self.layer)
        
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
        if MTLCreateSystemDefaultDevice() != nil{
            self.real = PEGPULayer()
            
        }else{
            self.real = PEVideoLayer()
            self.back = PEVideoLayer()
            self.real.index = 0
            self.back?.index = 1
            self.real.contentsGravity = .resizeAspect
            self.back?.contentsGravity = .resizeAspectFill
        }
        super.init(frame: frame)
    }
    @objc required init?(coder: NSCoder) {
        if MTLCreateSystemDefaultDevice() != nil{
            self.real = PEGPULayer()
            
        }else{
            self.real = PEVideoLayer()
            self.back = PEVideoLayer()
            self.real.contentsGravity = .resizeAspect
            self.back?.contentsGravity = .resizeAspectFill
        }
        super.init(coder: coder)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.real.frame = self.bounds
        self.back?.frame = self.bounds
        
        self.back?.loadLayer(parant: self.layer)
        self.real.loadLayer(parant: self.layer)
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

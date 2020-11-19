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
        let buffer = self.commandQueue?.makeCommandBuffer()
        if let drawable = self.nextDrawable(){
            let texture = drawable.texture
            if let backfilter = self.backgroundfilter{
                if let backimg = backfilter(img){
                    let tram = self.imageTransform(img: backimg,gravity:.resizeAspectFill,originRect: img.extent)
                    self.context?.render(tram, to: texture, commandBuffer: buffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
                }
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
    static var player:PEMTVideoPlayer?
    var real:PEGPULayer
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
        self.real = PEGPULayer()
        let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius":6])!
        let filter2 = CIFilter(name: "CIExposureAdjust", parameters: ["inputEV":-3])!
        self.real.backgroundfilter = filter.functionFilter + filter2.functionFilter
        super.init(frame: frame)
    }
    
    @objc required init?(coder: NSCoder) {
        self.real = PEGPULayer()
        let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius":6])!
        let filter2 = CIFilter(name: "CIExposureAdjust", parameters: ["inputEV":-3])!
        self.real.backgroundfilter = filter.functionFilter + filter2.functionFilter
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

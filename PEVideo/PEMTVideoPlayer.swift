//
//  PEMTVideoPlayer.swift
//  PushExtension
//
//  Created by hao yin on 2020/11/12.
//

import UIKit
import Metal
import AVFoundation
import CoreImage

@objc public enum PEMTVideoPlayerState:Int{
    case prepare
    case pausing
    case playing
    case caching
    case seeking
    case end
}

typealias timeCallBack = (Float)->Void

typealias endCallBack = (Bool)->Void

typealias stateChange = (PEMTVideoPlayerState)->Void

public protocol PEMTVideoPlayerDisplay:class {
    func    handlePixelBuffer(pixel:CVPixelBuffer)
    func    handleThumbnail(img:CGImage)
    var     filter:functionFilter? { get set }
    var     backgroundfilter:functionFilter? { get set }
    var     contentsGravity:CALayerContentsGravity {get set}
    var     frame:CGRect {get set}
    func    loadLayer(parant:CALayer)
    var     index:UInt32 {get set}
}

public class PEMTVideoPlayer{
    public var state:PEMTVideoPlayerState = .prepare{
        didSet{
            DispatchQueue.main.async {
                self.stateChange?(self.state)
            }
        }
    }
    public var asset:AVAsset
    public var item:AVPlayerItem
    public var percent:Float = 0
    var itemOutput:AVPlayerItemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
    var player:AVPlayer
    var array:Array<PEMTVideoPlayerDisplay> = []
    var timer:PEMTTimer?
    var observer:Any?
    var callback:timeCallBack?
    var endCallBack:endCallBack?
    var stateChange:stateChange?
    var timeObs:Any?
    var timeFailObs:Any?
    var coverImage:CGImage?

    public init(asset:AVAsset) {
        self.asset = asset
        let ass = AVPlayerItem(asset: asset)
        self.item = ass
        self.player = AVPlayer(playerItem: self.item)
        
        self.item.add(self.itemOutput)
        self.observer = self.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1,
                                                                preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: DispatchQueue.main) { [weak self] (t)  in
            if let ws = self{
                if ws.state == .seeking{
                    return
                }
                if let du = ws.player.currentItem?.duration{
                    let v = (Float(t.value) / Float(t.timescale)) / (Float(du.value) / Float(du.timescale))
                    ws.percent = v;
                    ws.callback?(v)
                }
            }
            
        }
        self.loadItemObserver()
    }
    func loadItemObserver(){
        self.timeObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: self.player.currentItem, queue: OperationQueue.main) { [weak self] (no) in
            self?.percent = 1;
            self?.state = .end
            self?.timer?.close()
            self?.endCallBack?(true)
        }
        self.timeFailObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: self.player.currentItem, queue: OperationQueue.main, using: { [weak self](no) in
            self?.percent = 1;
            self?.timer?.close()
            self?.state = .end
            self?.endCallBack?(false)
        })
    }
    func removeItemOberser(){
        if let time = self.timeObs{
            NotificationCenter.default.removeObserver(time)
        }
        if let faiTime = self.timeFailObs{
            NotificationCenter.default.removeObserver(faiTime)
        }
    }
    public func replaceCurrent(asset:AVAsset){
        self.stateChange?(.end)
        self.removeItemOberser()
        self.player.currentItem?.remove(self.itemOutput)
        self.item = AVPlayerItem(asset: asset)
        self.player.replaceCurrentItem(with:self.item)
        self.loadItemObserver()
        self.player.currentItem?.add(self.itemOutput)
    }
    public func play(){
        self.timer?.close()
        self.timer = PEMTTimer(call: { [weak self] in
            self?.render()
        })
        self.player.play()
        self.timer?.run()
    }
    public func render(){
        let time = self.itemOutput.itemTime(forHostTime: CACurrentMediaTime())
        if #available(iOS 10.0, *) {
            switch self.player.timeControlStatus {
            case .paused:
                if self.state != .seeking{
                    self.state = .pausing
                }
                break
            case .playing:
                self.state = .playing
                break
            case .waitingToPlayAtSpecifiedRate:
                self.state = .caching
                break
            @unknown default:
                self.state = .prepare
                break
            }
        } else {
            if(self.player.rate != 0){
                if self.player.currentItem!.isPlaybackLikelyToKeepUp {
                    self.state = .playing
                } else {
                    self.state = .caching
                }
            }else{
                self.state = .pausing
            }
        }
        if self.itemOutput.hasNewPixelBuffer(forItemTime: time) {
            self.display(time: time)
        }
    }
    public func addDisplay(display:PEMTVideoPlayerDisplay) {
        self.array.append(display)
    }
    
    public func pause(){
        self.player.pause()
    }
    public func mute(state:Bool){
        self.player.isMuted = state;
    }
    public func stop(){
        self.timer?.close()
        self.player.pause()
        self.state = .end
        if let time = self.timeObs{
            NotificationCenter.default.removeObserver(time)
            self.timeObs = nil
        }
        if let faiTime = self.timeFailObs{
            NotificationCenter.default.removeObserver(faiTime)
            self.timeFailObs = nil
        }
    }
    public func seek(percent:Float){
        
        if let time = self.timePercent(percent: percent){
            self.state = .seeking
            self.player.pause()
            self.player.seek(to: time)
        }
    }
    public func timePercent(percent:Float)->CMTime?{
        
        if let dur = self.player.currentItem?.duration{
            return CMTime(value: Int64(Float(dur.value) * percent), timescale: dur.timescale)
        }
        return nil
    }
    public func copyPixelAt(time:CMTime)->CVPixelBuffer?{
        if let px = self.itemOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil){
            return px
        }
        return nil
    }
    func display(time:CMTime){
        for display in self.array {
            if let px = self.copyPixelAt(time: time){
                DispatchQueue.main.async {
                    display.handlePixelBuffer(pixel: px)
                }
            }
        }
    }
    public func removeAllDisplay(){
        self.array.removeAll()
    }
    deinit {
        self.removeItemOberser()
    }
}

public class PEMTTimer:NSObject{
    let call:()->Void
    var link:CADisplayLink?
    public init(call:@escaping () ->Void) {
        self.call = call
        super.init()
        self.link = CADisplayLink(target: self, selector: #selector(callAction))
    }
    public func run(){
        thread = Thread(target: self, selector: #selector(threadMain(ib:)), object: self)
        thread?.start()
    }
    @objc func callAction(){
        self.call()
    }
    @objc func threadMain(ib:PEMTTimer){
        ib.link?.add(to: RunLoop.current, forMode: .common)
        RunLoop.current.run()
    }
    func close() {
        self.link?.invalidate()
        self.link = nil
        self.thread?.cancel()
        self.thread = nil
    }
    var thread:Thread?
}

@objc public protocol PEMTVideoViewDelegate:class,NSObjectProtocol{
    @objc optional func videoPlayer(player:UIView,percent:Float)
    @objc optional func videoPlayer(player:UIView,success:Bool)
    @objc optional func videoPlayer(player:UIView,state:PEMTVideoPlayerState)
}





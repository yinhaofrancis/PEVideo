//
//  ViewController.swift
//  PEVideo
//
//  Created by hao yin on 2020/11/19.
//

import UIKit
import AVFoundation
class ViewController: UIViewController {

    @IBOutlet weak var url: UITextField!
    @IBOutlet weak var videoView:PEMTGPUView!
 
    override func viewDidLoad() {
        super.viewDidLoad()
        print("\(try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))")
//        self.videoView.
    }
    
    
}
extension ViewController{
    @IBAction func play(){
        if let text = self.url.text{
            if let a = URL(string: text){
                self.videoView.load(item: AVAsset(url: a))
                self.videoView.replay()
            }
            
        }
        
    }
    @IBAction func change(_ sender: Any) {
        self.videoView.useFilter = false
    }
}


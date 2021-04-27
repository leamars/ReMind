//
//  ViewController.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 20/04/2021.
//

import UIKit
import AudioKit
import AudioKitUI

enum PlaybackState {
    case moving
    case playing
}

class ViewController: UIViewController {
    
    var player: AKPlayer!
    var completionHandler: AKCallback?
    var splits: [Split] = []
    var selectedSplit: Split?
    var isLooping: Bool = false
    
    // UI components
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var playPauseImageView: UIImageView!
    @IBOutlet weak var startLabel: UILabel!
    @IBOutlet weak var endLabel: UILabel!
    
    @IBOutlet weak var leadingPlayheadConstraint: NSLayoutConstraint!
    @IBOutlet weak var playHead: UIView!
    
    private var originalPlayheadLeadingConstant: CGFloat = 0.0
    
    var playbackTimer: Timer?
    
    var previousHapticX: CGFloat = 0
    
    let timeRemainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()
    
    var indexPathAtPlayheadPoint: IndexPath? {
        // If we only have 1 item, it's the full thing, so we need to split it in multiple
        // The end will be player.currentTime, and the start will be 0
        
        let playHeadPointX = playHead.center.x - collectionView.frame.origin.x
        let collectionViewY = collectionView.frame.height/2
        let splitPoint = CGPoint(x: playHeadPointX, y: collectionViewY)
        
        return collectionView.indexPathForItem(at: splitPoint)
    }
    
    // Gesture recognizers
    @IBOutlet var playTapGesture: UITapGestureRecognizer!
    
    var panGestureRecognizer = UIPanGestureRecognizer()
    
    // Haptics
    private var hapticGenerator = HapticGenerator()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupPlayer()
        setupGestureRecognizers()
        setupPlaybackTimer()
        
        collectionView.automaticallyAdjustsScrollIndicatorInsets = false
        
        // Tracks if we've moved 5 steps or more to play another haptic feedback through the Feedback generator
        previousHapticX = leadingPlayheadConstraint.constant
        originalPlayheadLeadingConstant = leadingPlayheadConstraint.constant
    }
    
    private func setupGestureRecognizers() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(recognizer:)))
        collectionView.addGestureRecognizer(longPress)
        longPress.delegate = self
        
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(recognizer:)))
        collectionView.addGestureRecognizer(panGestureRecognizer)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:)))
        collectionView.addGestureRecognizer(tapGestureRecognizer)
        
        let doubleTap = UITapGestureRecognizer(target: self, action:  #selector(handleDoubleTap(recognizer:)))
        doubleTap.numberOfTapsRequired = 2
        collectionView.addGestureRecognizer(doubleTap)
        
        tapGestureRecognizer.require(toFail: doubleTap)
    }
    
    private func setupPlayer() {
        let path = Bundle.main.path(forResource: "zemlja", ofType: "mp3")!
        let url = URL(fileURLWithPath: path)
        
        player = AKPlayer(url: url)
        
        player.buffering = .always
        player.completionHandler = { [weak self] in
            guard let self = self,
                  let split = self.selectedSplit, self.isLooping else { return }
            
            self.player.play(from: split.startTime, to: split.endTime)
        }
        
        AKManager.output = player
        try! AKManager.start()
        
        let fullSplit = Split(startTime: 0.0, endTime: player.duration)
        splits.append(fullSplit)
        collectionView.reloadData()
        
        updateTimeStrings()
    }
    
    private func setupPlaybackTimer() {
        if playbackTimer == nil {
            let timeInterval = 0.05
            
            playbackTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { [weak self ]timer in
                guard let self = self, self.player.isPlaying else { return }

                // Simply use the currentTime of the player and multiply to extrapolate across the full width of the collection view
                let maxWidth = self.collectionView.frame.width
                let multiplier = Double(maxWidth) / self.player.duration
                
                // Update playhead position
                let newConstant = self.originalPlayheadLeadingConstant + CGFloat(multiplier * Float(self.player.currentTime))
                self.leadingPlayheadConstraint.constant = newConstant
                
                // Update text on time strings
                self.updateTimeStrings()
            }
        }
    }
    
    // MARK: - Gesture recgnizers
    @objc func handleTap(recognizer: UITapGestureRecognizer) {
        FeedbackGenerator.shared.fire(for: .heavy)
        playMusic(shouldSwitch: true)
    }
    
    @objc func handlePan(recognizer: UILongPressGestureRecognizer) {
        player.stop()
        
        switch recognizer.state {
        case .began: return
            //hapticGenerator?.fireContinuous()
        case .changed:
            let touchPoint = recognizer.location(in: collectionView)
            var newX = touchPoint.x
            
            print("Touch point: \(touchPoint)")
            print("Collection view frame: \(collectionView.frame)")
            
            if newX < collectionView.frame.origin.x {
                newX = collectionView.frame.origin.x
            } else if newX > collectionView.frame.size.width {
                newX = collectionView.frame.origin.x + collectionView.frame.size.width
            }
            
            if abs(previousHapticX - newX) > 10 {
                FeedbackGenerator.shared.fire(for: .heavy)
                previousHapticX = newX
            }
            
            leadingPlayheadConstraint.constant = newX
        case .ended:
            playMusic(shouldSwitch: false)
            //hapticGenerator?.stop()
            
        case .possible, .cancelled, .failed: break
        @unknown default: break
        }
    }
        
    @objc func handleLongPress(recognizer: UILongPressGestureRecognizer) {
        player.stop()
        
        switch recognizer.state {
        case .began:
            FeedbackGenerator.shared.fire(for: .heavy)
            let touchPoint = recognizer.location(in: collectionView)
            leadingPlayheadConstraint.constant = touchPoint.x
            
        case .ended:
            playMusic(shouldSwitch: false)
            
        case .possible, .cancelled, .failed, .changed: break
        @unknown default: break
        }
    }
    
    @objc func handleDoubleTap(recognizer: UILongPressGestureRecognizer) {
        let touchPoint = recognizer.location(in: collectionView)
        
        switch recognizer.state {
        case .ended:
            playSplitIfPossible(at: touchPoint)
        case .began, .possible, .cancelled, .failed, .changed: break
        @unknown default: break
        }
    }
    
    // MARK: - IBActions
    @IBAction func playPauseTap(_ sender: UITapGestureRecognizer) {
        playMusic(shouldSwitch: true)
    }
    
    private func playMusic(shouldSwitch: Bool, loop: Bool = false, from: Double? = nil, to: Double? = nil) {
        defer {
            isLooping = loop
            
            if shouldSwitch {
                if player.isPlaying {
                    player.stop()
                } else {
                    if let from = from, let to = to {
                        player.play(from: from, to: to)
                    } else {
                        let currentPosition = leadingPlayheadConstraint.constant - collectionView.frame.origin.x
                        let currentTime = currentPosition / maxWidth * CGFloat(player.duration)
                        player.play(from: Double(currentTime))
                    }
                }
            }
            
            if let from = from, let to = to {
                player.play(from: from, to: to)
            }
            
            if player.isPlaying {
                playPauseImageView.image = #imageLiteral(resourceName: "pause")
            } else {
                playPauseImageView.image = #imageLiteral(resourceName: "play")
            }
        }
        
        let maxWidth = self.collectionView.frame.width
        
        guard let from = from, let _ = to else {
            let currentPosition = leadingPlayheadConstraint.constant - collectionView.frame.origin.x
            let currentTime = currentPosition / maxWidth * CGFloat(player.duration)
            
            startLabel.text = createTimeString(time: Float(currentTime))
            
            player.setPosition(Double(currentTime))
            return
        }
                
        startLabel.text = createTimeString(time: Float(from))
        
    }
    
    private func updateTimeStrings() {
        let newDurationSeconds = Float(player.duration)
        let currentTime = Float(CMTimeGetSeconds(CMTime(seconds: player.currentTime, preferredTimescale: 1)))
        
        startLabel.text = createTimeString(time: currentTime)
        endLabel.text = createTimeString(time: newDurationSeconds)
    }
    
    private func splitTrack() {
        if let indexPath = indexPathAtPlayheadPoint {

            let row = indexPath.row
            
            let split = splits[row]
            let newSplit = Split(startTime: split.startTime, endTime: player.currentTime)
            
            // Update the start time of the split that's being cut
            splits[row].startTime = player.currentTime
            splits.insert(newSplit, at: row)
        }
        
        collectionView.reloadData()
    }
    
    private func playSplitIfPossible(at touchLocation: CGPoint) {
        if let indexPath = collectionView.indexPathForItem(at: touchLocation) {

            let row = indexPath.row
            let split = splits[row]
            selectedSplit = split
            isLooping = true

            playMusic(shouldSwitch: false, loop: true, from: split.startTime, to: split.endTime)
        }
    }
}

// MARK: - Collection View Delegate
extension ViewController: UICollectionViewDelegate { }

// MARK: Gesture Recognizer
extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if let _ = gestureRecognizer as? UILongPressGestureRecognizer,
           let _ = otherGestureRecognizer as? UIPanGestureRecognizer {
            
            // User did pan after long press, prefer pan
            return true
        } else {
            return false
        }
    }
}

// MARK: - Collection View Flow Layout Delegate

extension ViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 2
        let height: Double = 128
        let split = splits[indexPath.row]
        
        let maxWidth = collectionView.frame.width
        let multiplier = Double(maxWidth) / player.duration
        
        let timeWidth = split.endTime - split.startTime
        let width: Double = timeWidth * multiplier
        
        let size = CGSize(width: width, height: height)
        
        return size
    }
}


// MARK: - UICollectionViewDataSource
extension ViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        splits.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CollectionSplitCell", for: indexPath) as! SplitCell
                        
        return cell
    }
}

// MARK: - Helper functions
extension ViewController {
    func createTimeString(time: Float) -> String {
        let components = NSDateComponents()
        components.second = Int(max(0.0, time))
        return timeRemainingFormatter.string(from: components as DateComponents)!
    }
}

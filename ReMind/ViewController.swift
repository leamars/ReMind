//
//  ViewController.swift
//  ReMind
//
//  Created by Lea Marolt Sonnenschein on 20/04/2021.
//

import UIKit
import AudioKit
import AudioKitUI
import Speech
import AVFoundation
import LofeltHaptics

enum PlaybackState {
    case moving
    case playing
}

class ViewController: UIViewController {
    
    // Need to keep this guy here and alive, otherwise the audio/haptic engines become null
    let lofeltGenerator = LofeltGenerator()
    
    // Speech Recognition
    let audioEngine = AVAudioEngine()
    let speechRecognizer = SFSpeechRecognizer()
    let request = SFSpeechAudioBufferRecognitionRequest()
    var recognitionTask: SFSpeechRecognitionTask?
    var mostRecentlyProcessedSegmentDuration: TimeInterval = 0
    
    var player: AKPlayer!
    var timePitch: AKTimePitch!
    var completionHandler: AKCallback?
    var splits: [Split] = []
    var selectedSplit: Split?
    var isLooping: Bool = false
    
    // UI components
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var startLabel: UILabel!
    @IBOutlet weak var endLabel: UILabel!
    @IBOutlet weak var speedLabel: UILabel!
    
    @IBOutlet weak var leadingPlayheadConstraint: NSLayoutConstraint!
    @IBOutlet weak var playHead: UIView!
    
    @IBOutlet weak var fasterBtn: UIButton!
    @IBOutlet weak var slowerBtn: UIButton!
    @IBOutlet weak var splitBtn: UIButton!
    @IBOutlet weak var playPauseBtn: UIButton!
    @IBOutlet weak var loopBtn: UIButton!
    @IBOutlet weak var clearBtn: UIButton!
    @IBOutlet weak var panel: UIView!
    
    private var originalPlayheadLeadingConstant: CGFloat = 0.0
    
    var playbackTimer: Timer?
    
    var previousHapticX: CGFloat = 0
    
    private let timeRemainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()
    
    private var indexPathAtPlayheadPoint: IndexPath? {
        // If we only have 1 item, it's the full thing, so we need to split it in multiple
        // The end will be player.currentTime, and the start will be 0
        
        let playHeadPointX = playHead.center.x - collectionView.frame.origin.x
        let collectionViewY = collectionView.frame.height/2
        let splitPoint = CGPoint(x: playHeadPointX, y: collectionViewY)
        
        return collectionView.indexPathForItem(at: splitPoint)
    }
    
    private var indexPathBeingTouched: IndexPath?
    
    private var indexOfSelectedSplit: Int? {
        guard let currentSplit = selectedSplit else { return nil }
        return splits.firstIndex(where: { $0.startTime == currentSplit.startTime })
    }
    
    // Gesture recognizers
    @IBOutlet var playTapGesture: UITapGestureRecognizer!
        
    // Haptics
    private var hapticGenerator = HapticGenerator()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupPlayer()
        setupGestureRecognizers()
        setupPlaybackTimer()

        setupSpeechRecognition()

        setupPanelGestures()
        //setupRightPanelGestures()

        collectionView.automaticallyAdjustsScrollIndicatorInsets = false

        previousHapticX = leadingPlayheadConstraint.constant
        originalPlayheadLeadingConstant = leadingPlayheadConstraint.constant

        collectionView.isScrollEnabled = false
    }
    
    private func setupPanelGestures() {
        // Skip back 3 seconds
        let twoFingerDoubleTap = UITapGestureRecognizer(target: self, action:  #selector(panelTwoFingerDoubleTap(recognizer:)))
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        twoFingerDoubleTap.numberOfTapsRequired = 2
        panel.addGestureRecognizer(twoFingerDoubleTap)
        
        let singleTap = UITapGestureRecognizer(target: self, action:  #selector(panelSingleTap(recognizer:)))
        panel.addGestureRecognizer(singleTap)
        
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(panelSwipeUp(recognizer:)))
        swipeUp.numberOfTouchesRequired = 1
        swipeUp.direction = .up
        swipeUp.delegate = self
        panel.addGestureRecognizer(swipeUp)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(panelSwipeDown(recognizer:)))
        swipeDown.numberOfTouchesRequired = 1
        swipeDown.direction = .down
        swipeDown.delegate = self
        panel.addGestureRecognizer(swipeDown)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(recognizer:)))
        panel.addGestureRecognizer(longPress)
        longPress.delegate = self
        
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(recognizer:)))
        panel.addGestureRecognizer(panGestureRecognizer)
    }
    
    @objc func panelTwoFingerDoubleTap(recognizer: UILongPressGestureRecognizer) {
        lofeltGenerator.play(pattern: .airPop)
        let touchPoint = recognizer.location(in: panel)
        let inLeftPanel = touchPoint.x < panel.frame.size.width/2
        
        switch recognizer.state {
        case .ended:
            if inLeftPanel {
                back(by: 3)
            } else {
                forward(by: 3)
            }
        case .began, .possible, .cancelled, .failed, .changed: break
        @unknown default: break
        }
    }
    
    @objc func panelSingleTap(recognizer: UILongPressGestureRecognizer) {
        lofeltGenerator.play(pattern: .tab2)
        switch recognizer.state {
        case .ended:
            playMusic(shouldSwitch: true)
        case .began, .possible, .cancelled, .failed, .changed: break
        @unknown default: break
        }
    }
    
    @objc func panelSwipeUp(recognizer: UISwipeGestureRecognizer) {
        hapticGenerator?.fireSwipePattern()
        handleSwipe(recognizer: recognizer)
    }
    
    @objc func panelSwipeDown(recognizer: UISwipeGestureRecognizer) {
        hapticGenerator?.fireSwipePattern()
        handleSwipe(recognizer: recognizer)
    }
    
    @objc func panelLongPress(recognizer: UILongPressGestureRecognizer) {
        player.stop()
        
        switch recognizer.state {
        case .began: return
        case .ended:
            panel.backgroundColor = .clear
            
        case .possible, .cancelled, .failed, .changed: break
        @unknown default: break
        }
    }
    
    private func setupGestureRecognizers() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(recognizer:)))
        collectionView.addGestureRecognizer(longPress)
        longPress.delegate = self
        
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(recognizer:)))
        collectionView.addGestureRecognizer(panGestureRecognizer)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:)))
        collectionView.addGestureRecognizer(tapGestureRecognizer)
        
        let doubleTap = UITapGestureRecognizer(target: self, action:  #selector(handleDoubleTap(recognizer:)))
        doubleTap.numberOfTapsRequired = 2
        collectionView.addGestureRecognizer(doubleTap)
        
        tapGestureRecognizer.require(toFail: doubleTap)
        
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(recognizer:)))
        collectionView.addGestureRecognizer(pinchRecognizer)
        
        let swipeUpGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp(recognizer:)))
        swipeUpGesture.numberOfTouchesRequired = 1
        swipeUpGesture.direction = .up
        swipeUpGesture.delegate = self
        collectionView.addGestureRecognizer(swipeUpGesture)
        
        let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown(recognizer:)))
        swipeDownGesture.numberOfTouchesRequired = 1
        swipeDownGesture.direction = .down
        swipeDownGesture.delegate = self
        collectionView.addGestureRecognizer(swipeDownGesture)
    }
    
    private func setupPlayer() {
        let path = Bundle.main.path(forResource: "Speechless_Piano", ofType: "mp3")!
        let url = URL(fileURLWithPath: path)
        
        player = AKPlayer(url: url)
        
        player.buffering = .always
        player.completionHandler = { [weak self] in
            guard let self = self,
                  let split = self.selectedSplit, self.isLooping else { return }
            
            self.player.play(from: split.startTime, to: split.endTime)
        }
        
        timePitch = AKTimePitch(player)
        timePitch.rate = 1.0
        AKManager.output = timePitch
        try! AKManager.start()
        
        let newDurationSeconds = Float(player.duration)
        let currentTime = Float(CMTimeGetSeconds(CMTime(seconds: player.currentTime, preferredTimescale: 1)))
                
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
    
    private func setupSpeechRecognition() {
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord,
                                                         options: [AVAudioSession.CategoryOptions.defaultToSpeaker,
                                                                   .allowBluetoothA2DP,
                                                                   .allowAirPlay])
        
        try! AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        
        SFSpeechRecognizer.requestAuthorization {
          [unowned self] (authStatus) in
          switch authStatus {
          case .authorized:
            do {
              try self.startRecording()
            } catch let error {
              print("There was a problem starting recording: \(error.localizedDescription)")
            }
          case .denied:
            print("Speech recognition authorization denied")
          case .restricted:
            print("Not available on this device")
          case .notDetermined:
            print("Not determined")
          @unknown default: break
          }
        }
    }
    
    private func startRecording() throws {
      mostRecentlyProcessedSegmentDuration = 0

      // 1
      let node = audioEngine.inputNode
      let recordingFormat = node.outputFormat(forBus: 0)

      // 2
      node.installTap(onBus: 0, bufferSize: 1024,
                      format: recordingFormat) { [unowned self]
                        (buffer, _) in
                        self.request.append(buffer)
      }

      // 3
      audioEngine.prepare()
      try audioEngine.start()
      recognitionTask = speechRecognizer?.recognitionTask(with: request) {
        [unowned self]
        (result, _) in
        if let transcription = result?.bestTranscription,
           let lastSegment = transcription.segments.last
           //lastSegment.duration > mostRecentlyProcessedSegmentDuration
            //print(transcription.formattedString)
           {
            
            mostRecentlyProcessedSegmentDuration = lastSegment.duration
            
            switch lastSegment.substring {
            case "cut":
                splitTrack()
            case "add":
                // Puts tracks together again
                combineLoopingSplitWithNext()
            case "up":
                changeTime(by: 0.1)
            case "down":
                changeTime(by: -0.1)
            case "loop":
                if let selectedIndex = indexPathAtPlayheadPoint {
                    selectedSplit = splits[selectedIndex.row]
                    isLooping = true

                    playMusic(shouldSwitch: false, loop: true, from: selectedSplit!.startTime, to: selectedSplit!.endTime)
                }
            case "play":
                playMusic(shouldSwitch: true)
            case "stop":
                // TODO: This should probably start it form the beginning
                playMusic(shouldSwitch: true)
            case "pause":
                playMusic(shouldSwitch: true)
            case "start":
                // Plays from the start
                break
            default: break
            }
        }
      }
    }
    
    private func stopRecording() {
      audioEngine.stop()
      request.endAudio()
      recognitionTask?.cancel()
    }
    
    // MARK: - Gesture recognizers
    @objc func handleTap(recognizer: UITapGestureRecognizer) {
        FeedbackGenerator.shared.fire(for: .heavy)
        playMusic(shouldSwitch: true)
    }
    
    @objc func handlePan(recognizer: UIPanGestureRecognizer) {
        player.stop()
        
        switch recognizer.state {
        case .began: return
            //hapticGenerator?.fireContinuous()
        case .changed:
            let touchPoint = recognizer.location(in: panel)
            let convertedTouchPoint = panel.convert(touchPoint, to: collectionView)
            var newX = convertedTouchPoint.x
            if newX < collectionView.frame.origin.x {
                newX = collectionView.frame.origin.x
            } else if newX > collectionView.frame.origin.x + collectionView.frame.size.width {
                newX = collectionView.frame.origin.x + collectionView.frame.size.width
            }
            
            // Play feedback when user's finger crosses an indexPath's line to indicate a new segment
            if let currentIndexPath = indexPathBeingTouched,
               let playheadIndexPath = indexPathAtPlayheadPoint {
                if currentIndexPath.row != playheadIndexPath.row {
                    // Play feedback
                    FeedbackGenerator.shared.fire(for: .heavy)
                    // Assign new indexPath
                    indexPathBeingTouched = indexPathAtPlayheadPoint
                }
            } else {
                indexPathBeingTouched = indexPathAtPlayheadPoint
            }
                        
            if abs(previousHapticX - newX) > 20 {
                FeedbackGenerator.shared.fire(for: .light)
                previousHapticX = newX
            }
            
            // Only fire haptic if we've crossed over into a new indexPath
            
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
            let touchPoint = recognizer.location(in: panel)
            let convertedTouchPoint = panel.convert(touchPoint, to: collectionView)
            leadingPlayheadConstraint.constant = convertedTouchPoint.x
            
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
    
    @objc func handlePinch(recognizer: UIPinchGestureRecognizer) {
        
        switch recognizer.state {
        case .ended:
            // If player is looping, combine the looping split with the next one
            combineLoopingSplitWithNext()
        case .began, .possible, .cancelled, .failed, .changed: break
        @unknown default: break
        }
    }
    
    private func combineLoopingSplitWithNext() {
        if let selectedSplit = selectedSplit, isLooping,
           let splitIndex = indexOfSelectedSplit,
           splits.count > splitIndex + 1 {
            
            let nextSplit = splits[splitIndex+1]
            let combinedSplit = Split(startTime: selectedSplit.startTime, endTime: nextSplit.endTime)
            
            splits.remove(at: splitIndex)
            splits.remove(at: splitIndex)
            
            splits.insert(combinedSplit, at: splitIndex)
            
            self.selectedSplit = combinedSplit
            playMusic(shouldSwitch: false, loop: true, from: combinedSplit.startTime, to: combinedSplit.endTime)
            
            collectionView.reloadData()
        }
    }
    
    @objc func handleSwipeUp(recognizer: UISwipeGestureRecognizer) {
        handleSwipe(recognizer: recognizer)
    }
    
    @objc func handleSwipeDown(recognizer: UISwipeGestureRecognizer) {
        handleSwipe(recognizer: recognizer)
    }
    
    private func handleSwipe(recognizer: UISwipeGestureRecognizer) {
        switch recognizer.state {
        case .ended:
            switch recognizer.direction {
            case .down:
                changeTime(by: -0.1)
            case .up:
                changeTime(by: 0.1)
            case .left, .right: break
            default: break
            }
        case .possible, .cancelled, .failed, .changed: break
        @unknown default: break
        }
    }
    
    // MARK: - IBActions
    @IBAction func playPause(_ sender: Any) {
        playMusic(shouldSwitch: true)
    }
    
    @IBAction func turnRateUp(_ sender: Any) {
        changeTime(by: 0.1)
    }
    
    @IBAction func turnRateDown(_ sender: Any) {
        changeTime(by: -0.1)
    }
    
    @IBAction func split(_ sender: Any) {
        splitTrack()
    }
    
    @IBAction func loop(_ sender: Any) {
        if selectedSplit == nil {
            selectedSplit = splits.first
        }
        
        playCurrentSplit()
    }
    
    @IBAction func clearSplits(_ sender: Any) {
        clearSplits()
    }
    
    // Only gets triggered when user interacts with this
    @IBAction func timerSliderChanged(_ sender: UISlider) {
        print("My value is: \(sender.value)")
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
            
            updatePlayButtonText()
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
    
    private func updatePlayButtonText() {
        let text = player.isPlaying ? "Pause" : "Play"
        
        playPauseBtn.setTitle(text, for: .normal)
        playPauseBtn.setTitle(text, for: .selected)
        playPauseBtn.setTitle(text, for: .highlighted)
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
    
    private func playCurrentSplit() {
        guard let selectedSplit = selectedSplit else { return }
        
        isLooping = true
        playMusic(shouldSwitch: false, loop: true, from: selectedSplit.startTime, to: selectedSplit.endTime)
    }
    
    private func playNextSplitIfPossible() {
        guard let currentIndex = indexOfSelectedSplit else { return }
        
        if currentIndex + 1 < splits.count {
            let nextIndex = currentIndex + 1
            let nextSplit = splits[nextIndex]
            selectedSplit = nextSplit
            isLooping = true

            playMusic(shouldSwitch: false, loop: true, from: nextSplit.startTime, to: nextSplit.endTime)
        }
    }
    
    private func playPreviousSplitIfPossible() {
        guard let currentIndex = indexOfSelectedSplit else { return }
        
        if currentIndex - 1 >= 0 && !splits.isEmpty {
            let previousIndex = currentIndex - 1
            let previousSplit = splits[previousIndex]
            selectedSplit = previousSplit
            isLooping = true

            playMusic(shouldSwitch: false, loop: true, from: previousSplit.startTime, to: previousSplit.endTime)
        }
    }
    
    private func changeTime(by delta: Double) {
        timePitch.rate = timePitch.rate + delta
        
        let numString = String(format: "Speed: %.1f", timePitch.rate)
        speedLabel.text = "\(numString)x"
    }
    
    private func clearSplits() {
        guard let last = splits.last else { return }
        let fullSplit = Split(startTime: 0.0, endTime: last.endTime)
        splits = [fullSplit]
        collectionView.reloadData()
    }
    
    private func back(by seconds: Double) {
        player.pause()
        player.play(from: player.currentTime - seconds)
    }
    
    private func forward(by seconds: Double) {
        player.pause()
        player.play(from: player.currentTime + seconds)
    }
}

// MARK: - Collection View Delegate
extension ViewController: UICollectionViewDelegate { }

// MARK: Gesture Recognizer
extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if let longPress = gestureRecognizer as? UILongPressGestureRecognizer,
           let pan = otherGestureRecognizer as? UIPanGestureRecognizer {
            print("This was a longPress + pan")
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

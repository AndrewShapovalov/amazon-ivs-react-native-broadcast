import UIKit
import AVFoundation

class IVSBroadcastCameraView: UIView {
  private let broadcastSession: IVSBroadcastSessionService = IVSBroadcastSessionService() // The primary interaction point with the IVS Broadcast SDK
  
  @objc var streamKey: NSString?
  @objc var rtmpsUrl: NSString?
  @objc var isCameraPreviewMirrored: Bool = false
  @objc var cameraPreviewAspectMode: NSString = "none"
  @objc var sessionLogLevel: NSString?
  @objc var cameraPosition: NSString? {
    didSet {
      self.broadcastSession.setCameraPosition(cameraPosition)
    }
  }
  @objc var logLevel: NSString? {
    didSet {
      self.broadcastSession.setLogLevel(logLevel)
    }
  }
  @objc var videoConfig: NSDictionary? {
    didSet {
      do {
        try self.broadcastSession.setVideoConfig(videoConfig)
      } catch {
        self.onErrorHandler(error)
      }
    }
  }
  @objc var audioConfig: NSDictionary? {
    didSet {
      do {
        try self.broadcastSession.setAudioConfig(audioConfig)
      } catch {
        self.onErrorHandler(error)
      }
    }
  }
  
  @objc var onError: RCTDirectEventBlock?
  @objc var onIsBroadcastReady: RCTDirectEventBlock?
  @objc var onAudioSessionInterrupted: RCTDirectEventBlock?
  @objc var onAudioSessionResumed: RCTDirectEventBlock?
  @objc var onMediaServicesWereLost: RCTDirectEventBlock?
  @objc var onMediaServicesWereReset: RCTDirectEventBlock?
  @objc var onBroadcastError: RCTDirectEventBlock? {
    didSet {
      self.broadcastSession.setBroadcastErrorHandler(onBroadcastError)
    }
  }
  @objc var onBroadcastAudioStats: RCTDirectEventBlock? {
    didSet {
      self.broadcastSession.setBroadcastAudioStatsHandler(onBroadcastAudioStats)
    }
  }
  @objc var onBroadcastStateChanged: RCTDirectEventBlock? {
    didSet {
      self.broadcastSession.setBroadcastStateChangedHandler(onBroadcastStateChanged)
    }
  }
  @objc var onBroadcastQualityChanged: RCTDirectEventBlock? {
    didSet {
      self.broadcastSession.setBroadcastQualityChangedHandler(onBroadcastQualityChanged)
    }
  }
  @objc var onNetworkHealthChanged: RCTDirectEventBlock? {
    didSet {
      self.broadcastSession.setNetworkHealthChangedHandler(onNetworkHealthChanged)
    }
  }
  
  @objc
  private func audioSessionInterrupted(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }
    
    switch type {
    case .began:
      self.onAudioSessionInterrupted?([:])
    case .ended:
      self.onAudioSessionResumed?([:])
    @unknown default:
      break
    }
  }
  
  @objc
  private func mediaServicesWereLost(_ notification: Notification) {
    self.onMediaServicesWereLost?([:])
  }
  
  @objc
  private func mediaServicesWereReset(_ notification: Notification) {
    self.onMediaServicesWereReset?([:])
  }
  
  // Observing notifications sent through NSNotificationCenter (Audio Interruptions & Media Services Lost sections)
  private func subscribeToNotificationCenter() {
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(audioSessionInterrupted(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil)
    center.addObserver(
      self,
      selector: #selector(mediaServicesWereLost(_:)),
      name: AVAudioSession.mediaServicesWereLostNotification,
      object: nil)
    center.addObserver(
      self,
      selector:  #selector(mediaServicesWereReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: nil)
  }
  
  private func unsubscribeNotificationCenter() {
    let center = NotificationCenter.default
    center.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
    center.removeObserver(self, name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
    center.removeObserver(self, name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
  }
  
  private func onErrorHandler(_ error: Error) {
    self.onError?(["message": error.localizedDescription])
  }
  
  // Handler to receive camera preview
  private func onCameraPreviewHandler(error: Error?, preview: UIView?) {
    if error != nil {
      self.onErrorHandler(error!)
    } else if preview != nil  {
      self.addSubview(preview!)
      self.onIsBroadcastReady?(["isReady": self.broadcastSession.isReady()])
    } else {
      assertionFailure("Unexpected behaviour.")
    }
  }
  
  override init(frame: CGRect) {
    super.init(frame: frame)
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented.")
  }
  
  override func didMoveToWindow() {
    if self.window != nil {
      // Disable the Application Idle Timer. Prevents device from going to sleep while using the broadcast SDK, which would interrupt the broadcast
      UIApplication.shared.isIdleTimerDisabled = true
      if self.broadcastSession.isInitiated() == false {
        self.subscribeToNotificationCenter()
        do {
          try self.broadcastSession.initiate()
          self.broadcastSession.setSessionLogLevel(self.sessionLogLevel)
          // Receive camera preview asynchronously to ensure that all devices have been attached
          self.broadcastSession.getCameraPreviewAsync(aspectModeName: self.cameraPreviewAspectMode, isMirrored: self.isCameraPreviewMirrored, callback: self.onCameraPreviewHandler)
        } catch {
          self.onErrorHandler(error)
        }
      }
    } else {
      // Enable the Application Idle Timer
      UIApplication.shared.isIdleTimerDisabled = false
      unsubscribeNotificationCenter()
      self.subviews.forEach { $0.removeFromSuperview() }
      self.broadcastSession.deinitiate()
    }
  }
  
  public func start() {
    guard let rtmpsUrl = self.rtmpsUrl else {
      assertionFailure("'rtmpsUrl' prop is required.")
      return;
    }
    
    guard let streamKey = self.streamKey else {
      assertionFailure("'streamKey' prop is required.")
      return;
    }
    
    do {
      try self.broadcastSession.start(ivsRTMPSUrl: rtmpsUrl , ivsStreamKey: streamKey)
    } catch {
      self.onErrorHandler(error)
    }
  }
  
  public func stop() {
    self.broadcastSession.stop()
  }
  
  public func swapCamera() {
    do {
      try self.broadcastSession.swapCamera()
    } catch {
      self.onErrorHandler(error)
    }
  }
}

import Flutter
import UIKit
import VideoToolbox
import CoreMedia
import CoreVideo
import ReplayKit
import MediaPlayer
import NetworkExtension

/// Native iOS 60fps Hardware H.264 VideoToolbox Encoder (`VTCompressionSession`),
/// `RPScreenRecorder` / `RPSystemBroadcastPickerView` Mirroring, `MPNowPlayingInfoCenter` Media Bridge,
/// and `NEHotspotConfigurationManager` Car Wi-Fi Joiner for iPhone 15 Pro Max (`ios_carlife_sender`).
final class CarLifeHardwareVideoEngine: NSObject, FlutterStreamHandler {
  static let shared = CarLifeHardwareVideoEngine()

  private var compressionSession: VTCompressionSession?
  private var eventSink: FlutterEventSink?
  private var width: Int32 = 1920
  private var height: Int32 = 1080
  private var fps: Int32 = 60
  private var bitrate: Int32 = 4_000_000
  private var frameCount: Int64 = 0
  private var forceNextKeyframe: Bool = true
  private var configSent: Bool = false

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  func startEncoder(width: Int32, height: Int32, fps: Int32, bitrate: Int32) {
    stopEncoder()
    self.width = width
    self.height = height
    self.fps = fps
    self.bitrate = bitrate
    self.frameCount = 0
    self.forceNextKeyframe = true
    self.configSent = false

    var session: VTCompressionSession?
    let status = VTCompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      width: width,
      height: height,
      codecType: kCMVideoCodecType_H264,
      encoderSpecification: nil,
      imageBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey: [:]
      ] as CFDictionary,
      compressedDataAllocator: nil,
      outputCallback: { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
        guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
        let engine = Unmanaged<CarLifeHardwareVideoEngine>.fromOpaque(refCon).takeUnretainedValue()
        engine.handleEncodedSampleBuffer(sampleBuffer)
      },
      refcon: Unmanaged.passUnretained(self).toOpaque(),
      compressionSessionOut: &session
    )

    guard status == noErr, let vtSession = session else { return }
    self.compressionSession = vtSession

    // Configure Baseline Profile, Zero B-Frames, Real-Time Low Latency, 1-second Keyframe interval
    VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
    VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
    VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps))
    VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1.0))
    VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
    VTSessionSetProperty(vtSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
    VTCompressionSessionPrepareToEncodeFrames(vtSession)
  }

  func requestKeyframe() {
    forceNextKeyframe = true
  }

  func encodeRgbaBytes(_ rgbaData: Data, width: Int, height: Int) {
    guard let vtSession = compressionSession else { return }
    var pixelBuffer: CVPixelBuffer?
    let attrs = [
      kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
      kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
    ] as CFDictionary

    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pb = pixelBuffer else { return }

    CVPixelBufferLockBaseAddress(pb, [])
    if let baseAddress = CVPixelBufferGetBaseAddress(pb) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
      let dst = baseAddress.assumingMemoryBound(to: UInt8.self)
      rgbaData.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
        guard let src = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        let rowBytes = min(width * 4, bytesPerRow)
        for y in 0..<height {
          let srcRow = src.advanced(by: y * width * 4)
          let dstRow = dst.advanced(by: y * bytesPerRow)
          var x = 0
          while x + 3 < rowBytes {
            // Convert RGBA -> BGRA for VideoToolbox hardware pipeline
            dstRow[x] = srcRow[x + 2]
            dstRow[x + 1] = srcRow[x + 1]
            dstRow[x + 2] = srcRow[x]
            dstRow[x + 3] = srcRow[x + 3]
            x += 4
          }
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(pb, [])

    let pts = CMTimeMake(value: frameCount, timescale: fps)
    frameCount += 1
    var frameProps: CFDictionary? = nil
    if forceNextKeyframe {
      forceNextKeyframe = false
      frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
    }

    VTCompressionSessionEncodeFrame(
      vtSession,
      imageBuffer: pb,
      presentationTimeStamp: pts,
      duration: CMTimeMake(value: 1, timescale: fps),
      frameProperties: frameProps,
      sourceFrameRefcon: nil,
      infoFlagsOut: nil
    )
  }

  private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
    let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
    let isKeyFrame = !notSync

    let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

    // Extract SPS & PPS Annex-B codec config on keyframe
    if isKeyFrame, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
      var spsSize: Int = 0
      var spsCount: Int = 0
      var spsPtr: UnsafePointer<UInt8>?
      var ppsSize: Int = 0
      var ppsCount: Int = 0
      var ppsPtr: UnsafePointer<UInt8>?

      if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDesc,
        parameterSetIndex: 0,
        parameterSetPointerOut: &spsPtr,
        parameterSetSizeOut: &spsSize,
        parameterSetCountOut: &spsCount,
        nalUnitHeaderLengthOut: nil
      ) == noErr,
         CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
          formatDesc,
          parameterSetIndex: 1,
          parameterSetPointerOut: &ppsPtr,
          parameterSetSizeOut: &ppsSize,
          parameterSetCountOut: &ppsCount,
          nalUnitHeaderLengthOut: nil
         ) == noErr,
         let sps = spsPtr, let pps = ppsPtr {
        var configData = Data(startCode)
        configData.append(sps, count: spsSize)
        configData.append(contentsOf: startCode)
        configData.append(pps, count: ppsSize)
        DispatchQueue.main.async { [weak self] in
          self?.eventSink?([
            "type": "config",
            "bytes": FlutterStandardTypedData(bytes: configData),
            "isKey": true
          ])
        }
      }
    }

    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
    var totalLength: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    guard CMBlockBufferGetDataPointer(
      dataBuffer,
      atOffset: 0,
      lengthAtOffsetOut: nil,
      totalLengthOut: &totalLength,
      dataPointerOut: &dataPointer
    ) == noErr, let ptr = dataPointer else { return }

    // Convert AVCC (4-byte length prefix) -> Annex-B (0x00 0x00 0x00 0x01 start code)
    var annexB = Data()
    var offset = 0
    while offset + 4 < totalLength {
      var nalLength: UInt32 = 0
      memcpy(&nalLength, ptr.advanced(by: offset), 4)
      nalLength = CFSwapInt32BigToHost(nalLength)
      offset += 4
      guard nalLength > 0 && offset + Int(nalLength) <= totalLength else { break }
      annexB.append(contentsOf: startCode)
      let rawBytes = UnsafeRawPointer(ptr.advanced(by: offset)).assumingMemoryBound(to: UInt8.self)
      annexB.append(rawBytes, count: Int(nalLength))
      offset += Int(nalLength)
    }

    guard !annexB.isEmpty else { return }
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?([
        "type": "frame",
        "bytes": FlutterStandardTypedData(bytes: annexB),
        "isKey": isKeyFrame
      ])
    }
  }

  func startReplayKitCapture(completion: @escaping (Bool) -> Void) {
    let recorder = RPScreenRecorder.shared()
    guard recorder.isAvailable else {
      completion(false)
      return
    }
    if recorder.isRecording {
      completion(true)
      return
    }
    recorder.startCapture(handler: { [weak self] (sampleBuffer, sampleType, error) in
      guard error == nil, sampleType == .video, let self = self, let vtSession = self.compressionSession else { return }
      guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
      let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      VTCompressionSessionEncodeFrame(
        vtSession,
        imageBuffer: imageBuffer,
        presentationTimeStamp: pts,
        duration: .invalid,
        frameProperties: nil,
        sourceFrameRefcon: nil,
        infoFlagsOut: nil
      )
    }, completionHandler: { error in
      DispatchQueue.main.async {
        completion(error == nil)
      }
    })
  }

  func stopReplayKitCapture() {
    let recorder = RPScreenRecorder.shared()
    if recorder.isRecording {
      recorder.stopCapture(handler: nil)
    }
  }

  func showSystemBroadcastPicker(in viewController: UIViewController?) {
    guard let vc = viewController else { return }
    let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
    picker.showsMicrophoneButton = false
    vc.view.addSubview(picker)
    for subview in picker.subviews {
      if let button = subview as? UIButton {
        button.sendActions(for: .allTouchEvents)
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      picker.removeFromSuperview()
    }
  }

  func stopEncoder() {
    stopReplayKitCapture()
    if let vtSession = compressionSession {
      VTCompressionSessionCompleteFrames(vtSession, untilPresentationTimeStamp: .invalid)
      VTCompressionSessionInvalidate(vtSession)
      compressionSession = nil
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      GeneratedPluginRegistrant.register(with: self)
      registerCarLifeChannels(messenger: controller.binaryMessenger, viewController: controller)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerCarLifeChannels(messenger: engineBridge.applicationRegistrar.messenger(), viewController: nil)
  }

  private func registerCarLifeChannels(messenger: FlutterBinaryMessenger, viewController: UIViewController?) {
    let methodChannel = FlutterMethodChannel(
      name: "com.mydevsketch.carlife/native_bridge",
      binaryMessenger: messenger
    )
    let eventChannel = FlutterEventChannel(
      name: "com.mydevsketch.carlife/h264_stream",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(CarLifeHardwareVideoEngine.shared)

    methodChannel.setMethodCallHandler { [weak viewController] (call, result) in
      switch call.method {
      case "initVideoToolbox":
        let args = call.arguments as? [String: Any]
        let w = Int32(args?["width"] as? Int ?? 1920)
        let h = Int32(args?["height"] as? Int ?? 1080)
        let fps = Int32(args?["fps"] as? Int ?? 60)
        let bitrate = Int32(args?["bitrate"] as? Int ?? 4_000_000)
        CarLifeHardwareVideoEngine.shared.startEncoder(width: w, height: h, fps: fps, bitrate: bitrate)
        result(nil)

      case "encodeRgbaFrame":
        guard let args = call.arguments as? [String: Any],
              let typedData = args["rgba"] as? FlutterStandardTypedData,
              let w = args["width"] as? Int,
              let h = args["height"] as? Int else {
          result(nil)
          return
        }
        CarLifeHardwareVideoEngine.shared.encodeRgbaBytes(typedData.data, width: w, height: h)
        result(nil)

      case "requestKeyframe":
        CarLifeHardwareVideoEngine.shared.requestKeyframe()
        result(nil)

      case "startReplayKitCapture":
        CarLifeHardwareVideoEngine.shared.startReplayKitCapture { ok in
          result(ok)
        }

      case "stopReplayKitCapture":
        CarLifeHardwareVideoEngine.shared.stopReplayKitCapture()
        result(nil)

      case "showBroadcastPicker":
        let activeVC = viewController ?? UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first { $0.isKeyWindow }?.rootViewController
        CarLifeHardwareVideoEngine.shared.showSystemBroadcastPicker(in: activeVC)
        result(nil)

      case "getNowPlaying":
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let title = info?[MPMediaItemPropertyTitle] as? String ?? ""
        let artist = info?[MPMediaItemPropertyArtist] as? String ?? ""
        let album = info?[MPMediaItemPropertyAlbumTitle] as? String ?? ""
        result([
          "title": title,
          "artist": artist,
          "album": album
        ])

      case "joinCarHotspot":
        guard let args = call.arguments as? [String: Any],
              let ssid = args["ssid"] as? String,
              let password = args["password"] as? String else {
          result(false)
          return
        }
        let config = password.isEmpty
          ? NEHotspotConfiguration(ssid: ssid)
          : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        config.joinOnce = false
        NEHotspotConfigurationManager.shared.apply(config) { err in
          result(err == nil)
        }

      case "stopVideoToolbox":
        CarLifeHardwareVideoEngine.shared.stopEncoder()
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

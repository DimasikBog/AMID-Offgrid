import Flutter
import UIKit
import MessageUI
import Speech
import AVFoundation
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler, MFMessageComposeViewControllerDelegate {
  private var emergencyChannel: FlutterMethodChannel?
  private var voiceChannel: FlutterEventChannel?
  private var voiceSink: FlutterEventSink?
  private var voiceId: Int?
  private var voiceStartResult: FlutterResult?
  private var audioEngine: AVAudioEngine?
  private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
  private var speechTask: SFSpeechRecognitionTask?
  private var audioActive = false
  private var voiceTimeout: DispatchWorkItem?
  private var voiceFinish: DispatchWorkItem?
  private var filesChannel: FlutterMethodChannel?
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureEmergency(engineBridge.applicationRegistrar.messenger())
    let channel = FlutterMethodChannel(name: "com.amid.offgrid/files", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    filesChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
        result(FlutterError(code: "INVALID_PATH", message: "File path is required", details: nil)); return
      }
      do {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath().standardizedFileURL
        var file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(support.path + "/") else {
          result(FlutterError(code: "INVALID_PATH", message: "Path must be inside app support", details: nil)); return
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "BACKUP_FLAG_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }
  private func configureEmergency(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.amid.offgrid/emergency", binaryMessenger: messenger)
    emergencyChannel = channel
    let stream = FlutterEventChannel(name: "com.amid.offgrid/emergency_voice", binaryMessenger: messenger)
    voiceChannel = stream
    stream.setStreamHandler(self)
    NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.stopVoice() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(false); return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "composeSms":
        guard args["number"] as? String == "112", let body = args["body"] as? String, body.utf16.count <= 2000 else {
          result(FlutterError(code: "INVALID_SMS", message: "Invalid emergency message", details: nil)); return
        }
        guard MFMessageComposeViewController.canSendText(),
          let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
          var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { result(false); return }
        while let top = presenter.presentedViewController { presenter = top }
        guard !presenter.isBeingDismissed, !presenter.isBeingPresented else { result(false); return }
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.recipients = ["112"]
        composer.body = body
        presenter.present(composer, animated: true) { result(true) }
      case "voiceStart":
        self.stopVoice()
        guard let id = args["session"] as? Int, let locale = args["locale"] as? String,
          ["uk-UA", "cs-CZ", "en-US"].contains(locale),
          let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else { result(false); return }
        self.voiceId = id
        self.voiceStartResult = result
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
          DispatchQueue.main.async {
            guard let self, self.voiceId == id else { return }
            guard status == .authorized, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { self.stopVoice(); return }
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
              DispatchQueue.main.async {
                guard let self, self.voiceId == id else { return }
                guard allowed, UIApplication.shared.applicationState == .active else { self.stopVoice(); return }
                self.startVoice(id, recognizer: recognizer)
              }
            }
          }
        }
      case "voiceCancel":
        if args["session"] as? Int == self.voiceId { self.stopVoice() }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func startVoice(_ id: Int, recognizer: SFSpeechRecognizer) {
    guard voiceId == id else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true)
      audioActive = true
      let engine = AVAudioEngine()
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = false
      request.taskHint = .confirmation
      let format = engine.inputNode.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else { stopVoice(); return }
      engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in request?.append(buffer) }
      audioEngine = engine
      speechRequest = request
      speechTask = recognizer.recognitionTask(with: request) { [weak self] response, error in
        DispatchQueue.main.async {
          guard let self, self.voiceId == id else { return }
          if let response, response.isFinal {
            self.voiceSink?(["session": id, "words": response.bestTranscription.formattedString, "final": true])
            self.stopVoice()
          } else if error != nil {
            self.voiceSink?(["session": id, "error": true])
            self.stopVoice()
          }
        }
      }
      engine.prepare()
      try engine.start()
      // End input before the hard deadline so local recognition can emit a final result.
      let finish = DispatchWorkItem { [weak self] in
        guard let self, self.voiceId == id else { return }
        if let engine = self.audioEngine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        self.audioEngine = nil
        self.speechRequest?.endAudio()
      }
      voiceFinish = finish
      DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: finish)
      let deadline = DispatchWorkItem { [weak self] in
        guard let self, self.voiceId == id else { return }
        self.voiceSink?(["session": id, "error": true])
        self.stopVoice()
      }
      voiceTimeout = deadline
      DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: deadline)
      let result = voiceStartResult; voiceStartResult = nil; result?(true)
    } catch { stopVoice() }
  }
  private func stopVoice() {
    voiceId = nil
    voiceTimeout?.cancel(); voiceTimeout = nil
    voiceFinish?.cancel(); voiceFinish = nil
    let result = voiceStartResult; voiceStartResult = nil; result?(false)
    if let engine = audioEngine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
    audioEngine = nil
    speechRequest?.endAudio(); speechRequest = nil
    speechTask?.cancel(); speechTask = nil
    if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    audioActive = false
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { voiceSink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { stopVoice(); voiceSink = nil; return nil }
  func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { controller.dismiss(animated: true) }

}

import AVFoundation
import CoreML
import CoreMedia
import UIKit
import Vision

var mlModel = try! yolo11m(configuration: .init()).model
var conf = Double(round(100 * 0.8)) / 100
var iou = Double(round(100 * 0.3)) / 100

class ViewController: UIViewController {
  @IBOutlet var videoPreview: UIView!
  @IBOutlet var View0: UIView!
  @IBOutlet var segmentedControl: UISegmentedControl!
  @IBOutlet var playButtonOutlet: UIBarButtonItem!
  @IBOutlet var pauseButtonOutlet: UIBarButtonItem!
  @IBOutlet weak var labelName: UILabel!
  @IBOutlet weak var labelFPS: UILabel!
  @IBOutlet weak var labelZoom: UILabel!
  @IBOutlet weak var labelVersion: UILabel!
  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var forcus: UIImageView!
  @IBOutlet weak var toolBar: UIToolbar!
  @IBOutlet weak var busCountLabel: UITextField!
    
  var busCount = 0
    
  let selection = UISelectionFeedbackGenerator()
  var detector = try! VNCoreMLModel(for: mlModel)
  var session: AVCaptureSession!
    var videoCapture: VideoCapture!
  var currentBuffer: CVPixelBuffer?
  var framesDone = 0
  var t0 = 0.0  // inference start
  var t1 = 0.0  // inference dt
  var t2 = 0.0  // inference dt smoothed
  var t3 = CACurrentMediaTime()  // FPS start
  var t4 = 0.0  // FPS dt smoothed
  // var cameraOutput: AVCapturePhotoOutput!
  var longSide: CGFloat = 3
  var shortSide: CGFloat = 4
  var frameSizeCaptured = false

  // Developer mode
  let developerMode = UserDefaults.standard.bool(forKey: "developer_mode")  // developer mode selected in settings
  let save_detections = false  // write every detection to detections.txt
  let save_frames = false  // write every frame to frames.txt

  lazy var visionRequest: VNCoreMLRequest = {
    let request = VNCoreMLRequest(
      model: detector,
      completionHandler: {
        [weak self] request, error in
        self?.processObservations(for: request, error: error)
      })
    // NOTE: BoundingBoxView object scaling depends on request.imageCropAndScaleOption https://developer.apple.com/documentation/vision/vnimagecropandscaleoption
    request.imageCropAndScaleOption = .scaleFill  // .scaleFit, .scaleFill, .centerCrop
    return request
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    setUpBoundingBoxViews()
    setUpOrientationChangeNotification()
    startVideo()
    setModel()
  }

  override func viewWillTransition(
    to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)

    if size.width > size.height {
      toolBar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
      toolBar.setShadowImage(UIImage(), forToolbarPosition: .any)
    } else {
      toolBar.setBackgroundImage(nil, forToolbarPosition: .any, barMetrics: .default)
      toolBar.setShadowImage(nil, forToolbarPosition: .any)
    }
    self.videoCapture.previewLayer?.frame = CGRect(
      x: 0, y: 0, width: size.width, height: size.height)

  }

  private func setUpOrientationChangeNotification() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(orientationDidChange),
      name: UIDevice.orientationDidChangeNotification, object: nil)
  }

  @objc func orientationDidChange() {
    videoCapture.updateVideoOrientation()
    //      frameSizeCaptured = false
  }

  @IBAction func vibrate(_ sender: Any) {
    selection.selectionChanged()
  }

  func setModel() {

    /// VNCoreMLModel
    detector = try! VNCoreMLModel(for: mlModel)
    detector.featureProvider = ThresholdProvider(iouThreshold: iou, confidenceThreshold: conf)

    /// VNCoreMLRequest
    let request = VNCoreMLRequest(
      model: detector,
      completionHandler: { [weak self] request, error in
        self?.processObservations(for: request, error: error)
      })
    request.imageCropAndScaleOption = .scaleFill  // .scaleFit, .scaleFill, .centerCrop
    visionRequest = request
    t2 = 0.0  // inference dt smoothed
    t3 = CACurrentMediaTime()  // FPS start
    t4 = 0.0  // FPS dt smoothed
  }

  @IBAction func takePhoto(_ sender: Any?) {
    let t0 = DispatchTime.now().uptimeNanoseconds

    // 1. captureSession and cameraOutput
    // session = videoCapture.captureSession  // session = AVCaptureSession()
    // session.sessionPreset = AVCaptureSession.Preset.photo
    // cameraOutput = AVCapturePhotoOutput()
    // cameraOutput.isHighResolutionCaptureEnabled = true
    // cameraOutput.isDualCameraDualPhotoDeliveryEnabled = true
    // print("1 Done: ", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1E9)

    // 2. Settings
    let settings = AVCapturePhotoSettings()
    // settings.flashMode = .off
    // settings.isHighResolutionPhotoEnabled = cameraOutput.isHighResolutionCaptureEnabled
    // settings.isDualCameraDualPhotoDeliveryEnabled = self.videoCapture.cameraOutput.isDualCameraDualPhotoDeliveryEnabled

    // 3. Capture Photo
    usleep(20_000)  // short 10 ms delay to allow camera to focus
    self.videoCapture.cameraOutput.capturePhoto(
      with: settings, delegate: self as AVCapturePhotoCaptureDelegate)
    print("3 Done: ", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1E9)
  }

  @IBAction func logoButton(_ sender: Any) {
    selection.selectionChanged()
    if let link = URL(string: "https://www.ultralytics.com") {
      UIApplication.shared.open(link)
    }
  }

  func setLabels() {
    self.labelName.text = "YOLO11m"
    self.labelVersion.text = "Version " + UserDefaults.standard.string(forKey: "app_version")!
  }

  @IBAction func playButton(_ sender: Any) {
    selection.selectionChanged()
    self.videoCapture.start()
    playButtonOutlet.isEnabled = false
    pauseButtonOutlet.isEnabled = true
  }

  @IBAction func pauseButton(_ sender: Any?) {
    selection.selectionChanged()
    self.videoCapture.stop()
    playButtonOutlet.isEnabled = true
    pauseButtonOutlet.isEnabled = false
  }

  @IBAction func switchCameraTapped(_ sender: Any) {
    self.videoCapture.captureSession.beginConfiguration()
    let currentInput = self.videoCapture.captureSession.inputs.first as? AVCaptureDeviceInput
    self.videoCapture.captureSession.removeInput(currentInput!)
    // let newCameraDevice = currentInput?.device == .builtInWideAngleCamera ? getCamera(with: .front) : getCamera(with: .back)

    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
    guard let videoInput1 = try? AVCaptureDeviceInput(device: device) else {
      return
    }

    self.videoCapture.captureSession.addInput(videoInput1)
    self.videoCapture.captureSession.commitConfiguration()
  }

  // share image
  @IBAction func shareButton(_ sender: Any) {
    selection.selectionChanged()
    let settings = AVCapturePhotoSettings()
    self.videoCapture.cameraOutput.capturePhoto(
      with: settings, delegate: self as AVCapturePhotoCaptureDelegate)
  }

  // share screenshot
  @IBAction func saveScreenshotButton(_ shouldSave: Bool = true) {
    // let layer = UIApplication.shared.keyWindow!.layer
    // let scale = UIScreen.main.scale
    // UIGraphicsBeginImageContextWithOptions(layer.frame.size, false, scale);
    // layer.render(in: UIGraphicsGetCurrentContext()!)
    // let screenshot = UIGraphicsGetImageFromCurrentImageContext()
    // UIGraphicsEndImageContext()

    // let screenshot = UIApplication.shared.screenShot
    // UIImageWriteToSavedPhotosAlbum(screenshot!, nil, nil, nil)
  }

  let maxBoundingBoxViews = 100
  var boundingBoxViews = [BoundingBoxView]()
  var colors: [String: UIColor] = [:]
  let ultralyticsColorsolors: [UIColor] = [
    UIColor(red: 4 / 255, green: 42 / 255, blue: 255 / 255, alpha: 0.6),  // #042AFF
    UIColor(red: 11 / 255, green: 219 / 255, blue: 235 / 255, alpha: 0.6),  // #0BDBEB
    UIColor(red: 243 / 255, green: 243 / 255, blue: 243 / 255, alpha: 0.6),  // #F3F3F3
    UIColor(red: 0 / 255, green: 223 / 255, blue: 183 / 255, alpha: 0.6),  // #00DFB7
    UIColor(red: 17 / 255, green: 31 / 255, blue: 104 / 255, alpha: 0.6),  // #111F68
    UIColor(red: 255 / 255, green: 111 / 255, blue: 221 / 255, alpha: 0.6),  // #FF6FDD
    UIColor(red: 255 / 255, green: 68 / 255, blue: 79 / 255, alpha: 0.6),  // #FF444F
    UIColor(red: 204 / 255, green: 237 / 255, blue: 0 / 255, alpha: 0.6),  // #CCED00
    UIColor(red: 0 / 255, green: 243 / 255, blue: 68 / 255, alpha: 0.6),  // #00F344
    UIColor(red: 189 / 255, green: 0 / 255, blue: 255 / 255, alpha: 0.6),  // #BD00FF
    UIColor(red: 0 / 255, green: 180 / 255, blue: 255 / 255, alpha: 0.6),  // #00B4FF
    UIColor(red: 221 / 255, green: 0 / 255, blue: 186 / 255, alpha: 0.6),  // #DD00BA
    UIColor(red: 0 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.6),  // #00FFFF
    UIColor(red: 38 / 255, green: 192 / 255, blue: 0 / 255, alpha: 0.6),  // #26C000
    UIColor(red: 1 / 255, green: 255 / 255, blue: 179 / 255, alpha: 0.6),  // #01FFB3
    UIColor(red: 125 / 255, green: 36 / 255, blue: 255 / 255, alpha: 0.6),  // #7D24FF
    UIColor(red: 123 / 255, green: 0 / 255, blue: 104 / 255, alpha: 0.6),  // #7B0068
    UIColor(red: 255 / 255, green: 27 / 255, blue: 108 / 255, alpha: 0.6),  // #FF1B6C
    UIColor(red: 252 / 255, green: 109 / 255, blue: 47 / 255, alpha: 0.6),  // #FC6D2F
    UIColor(red: 162 / 255, green: 255 / 255, blue: 11 / 255, alpha: 0.6),  // #A2FF0B
  ]

  func setUpBoundingBoxViews() {
    // Ensure all bounding box views are initialized up to the maximum allowed.
    while boundingBoxViews.count < maxBoundingBoxViews {
      boundingBoxViews.append(BoundingBoxView())
    }

    // Retrieve class labels directly from the CoreML model's class labels, if available.
    guard let classLabels = mlModel.modelDescription.classLabels as? [String] else {
      fatalError("Class labels are missing from the model description")
    }

    // Assign random colors to the classes.
    var count = 0
    for label in classLabels {
      let color = ultralyticsColorsolors[count]
      count += 1
      if count > 19 {
        count = 0
      }
      colors[label] = color

    }
  }

  func startVideo() {
    videoCapture = VideoCapture()
    videoCapture.delegate = self

    videoCapture.setUp(sessionPreset: .photo) { success in
      // .hd4K3840x2160 or .photo (4032x3024)  Warning: 4k may not work on all devices i.e. 2019 iPod
      if success {
        // Add the video preview into the UI.
        if let previewLayer = self.videoCapture.previewLayer {
          self.videoPreview.layer.addSublayer(previewLayer)
          self.videoCapture.previewLayer?.frame = self.videoPreview.bounds  // resize preview layer
        }

        // Add the bounding box layers to the UI, on top of the video preview.
        for box in self.boundingBoxViews {
          box.addToLayer(self.videoPreview.layer)
        }

        // Once everything is set up, we can start capturing live video.
        self.videoCapture.start()
      }
    }
  }

  func predict(sampleBuffer: CMSampleBuffer) {
    if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      currentBuffer = pixelBuffer
      if !frameSizeCaptured {
        let frameWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let frameHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        longSide = max(frameWidth, frameHeight)
        shortSide = min(frameWidth, frameHeight)
        frameSizeCaptured = true
      }
      /// - Tag: MappingOrientation
      // The frame is always oriented based on the camera sensor,
      // so in most cases Vision needs to rotate it for the model to work as expected.
      let imageOrientation: CGImagePropertyOrientation
      switch UIDevice.current.orientation {
      case .portrait:
        imageOrientation = .up
      case .portraitUpsideDown:
        imageOrientation = .down
      case .landscapeLeft:
        imageOrientation = .up
      case .landscapeRight:
        imageOrientation = .up
      case .unknown:
        imageOrientation = .up
      default:
        imageOrientation = .up
      }

      // Invoke a VNRequestHandler with that image
      let handler = VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer, orientation: imageOrientation, options: [:])
      if UIDevice.current.orientation != .faceUp {  // stop if placed down on a table
        t0 = CACurrentMediaTime()  // inference start
        do {
          try handler.perform([visionRequest])
        } catch {
          print(error)
        }
        t1 = CACurrentMediaTime() - t0  // inference dt
      }

      currentBuffer = nil
    }
  }

  func processObservations(for request: VNRequest, error: Error?) {
    DispatchQueue.main.async {
      if let results = request.results as? [VNRecognizedObjectObservation] {
        self.handlePredictions(results)
      } else {
        self.handlePredictions([])
      }

      // Measure FPS
      if self.t1 < 10.0 {  // valid dt
        self.t2 = self.t1 * 0.05 + self.t2 * 0.95  // smoothed inference time
      }
      self.t4 = (CACurrentMediaTime() - self.t3) * 0.05 + self.t4 * 0.95  // smoothed delivered FPS
      self.labelFPS.text = String(format: "%.1f FPS - %.1f ms", 1 / self.t4, self.t2 * 1000)  // t2 seconds to ms
      self.t3 = CACurrentMediaTime()
    }
  }

  // Save text file
  func saveText(text: String, file: String = "saved.txt") {
    if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      let fileURL = dir.appendingPathComponent(file)

      // Writing
      do {  // Append to file if it exists
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write(text.data(using: .utf8)!)
        fileHandle.closeFile()
      } catch {  // Create new file and write
        do {
          try text.write(to: fileURL, atomically: false, encoding: .utf8)
        } catch {
          print("no file written")
        }
      }

      // Reading
      // do {let text2 = try String(contentsOf: fileURL, encoding: .utf8)} catch {/* error handling here */}
    }
  }

  // Save image file
  func saveImage() {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    let fileURL = dir!.appendingPathComponent("saved.jpg")
    let image = UIImage(named: "ultralytics_yolo_logotype.png")
    FileManager.default.createFile(
      atPath: fileURL.path, contents: image!.jpegData(compressionQuality: 0.5), attributes: nil)
  }

  // Return hard drive space (GB)
  func freeSpace() -> Double {
    let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
    do {
      let values = try fileURL.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey
      ])
      return Double(values.volumeAvailableCapacityForImportantUsage!) / 1E9  // Bytes to GB
    } catch {
      print("Error retrieving storage capacity: \(error.localizedDescription)")
    }
    return 0
  }

  // Return RAM usage (GB)
  func memoryUsage() -> Double {
    var taskInfo = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    if kerr == KERN_SUCCESS {
      return Double(taskInfo.resident_size) / 1E9  // Bytes to GB
    } else {
      return 0
    }
  }

  func handlePredictions(_ predictions: [VNRecognizedObjectObservation]) {
    // 1) ----- COUNT BUSES FIRST -----
    var newBusCount = 0
    var busObservations = [VNRecognizedObjectObservation]()

    for prediction in predictions {
      guard let bestClass = prediction.labels.first?.identifier else { continue }
      if bestClass == "bus" {
        newBusCount += 1
        busObservations.append(prediction)
      }
    }

    // 2) ----- UPDATE BUS COUNT & ANNOUNCE IF NEEDED -----
    if newBusCount != busCount {
      busCount = newBusCount

      // Call a function if there's more than one bus
      if newBusCount > 0 {
        busFound(newCount: newBusCount)
      } else {
          busDissapeared()
      }
    }

    // 3) ----- OPTIONAL: ADDITIONAL LOGGING BEFORE SHOWING BOXES -----
    // e.g. developerMode checks, saving frames/detections, etc.

    // 4) ----- IF BUSES FOUND, SHOW BOUNDING BOXES AND PERFORM OCR -----
    // (Only call this method if there is at least one bus)
    //if newBusCount > 0 {
    showBuses(busObservations)
    
    // Perform OCR on bus regions
    if newBusCount > 0 && currentBuffer != nil {
        performOCROnBuses(busObservations, pixelBuffer: currentBuffer!)
    }
    //}
  }

  func busFound(newCount: Int) {
    // Update the busCountLabel text field
    busCountLabel.text = "Bus count: \(newCount)"

    // Make an accessibility announcement
    UIAccessibility.post(
            notification: .announcement,
            argument: "Bus count: \(newCount)"
    )

    //print
    print("New bus count is \(newCount). Updating the UI and announcing via accessibility.")
  }

  func busDissapeared() {
    // Update the busCountLabel text field
    busCountLabel.text = "No bus"

    // Make an accessibility announcement
    UIAccessibility.post(
            notification: .announcement,
            argument: "No bus"
    )

    //print
    print("Bus has gone")
  }

  // MARK: - Show bounding boxes for bus observations only
  func showBuses(_ busObservations: [VNRecognizedObjectObservation]) {
    // You can still use `boundingBoxViews.count` to match the number of boxes you need.
    // Here, we'll hide or show bounding boxes accordingly.

    // We need to use two bounding box views per bus: one for the bus and one for OCR region
    let maxBusesWithOCR = boundingBoxViews.count / 2
    
    // First, hide all bounding boxes before showing only needed ones
    for i in 0..<boundingBoxViews.count {
      boundingBoxViews[i].hide()
    }

    // Show buses and their OCR regions
    for i in 0..<min(busObservations.count, maxBusesWithOCR) {
      let busPrediction = busObservations[i]
      guard let bestClass = busPrediction.labels.first?.identifier else {
        continue
      }

      // 1) Get the bounding box from the prediction
      let rect = busPrediction.boundingBox
      
      // 2) Compute label and alpha
      let confidence = busPrediction.labels.first?.confidence ?? 0.0
      let label = String(format: "%@ %.1f", bestClass, confidence * 100)
      let alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)

      // 3) Show the main bus bounding box
      let busBoxIndex = i * 2
      if busBoxIndex < boundingBoxViews.count {
        boundingBoxViews[busBoxIndex].show(
          frame: rect,
          label: label,
          color: colors[bestClass] ?? UIColor.white,
          alpha: alpha
        )
      }
      
      // 4) Show the OCR region (top third of the bus where number is likely to be)
      let ocrBoxIndex = busBoxIndex + 1
      if ocrBoxIndex < boundingBoxViews.count {
        // Create a smaller rectangle for the OCR region at the top third of the bus
        let ocrRect = CGRect(
          x: rect.origin.x,
          y: rect.origin.y + (rect.height * 2/3),
          width: rect.width,
          height: rect.height/3
        )
        
        // Show the OCR region with a distinctive color and label
        boundingBoxViews[ocrBoxIndex].show(
          frame: ocrRect,
          label: "OCR",
          color: UIColor.yellow,
          alpha: 0.7
        )
      }
    }
  }

  // Pinch to Zoom Start ---------------------------------------------------------------------------------------------
  let minimumZoom: CGFloat = 1.0
  let maximumZoom: CGFloat = 10.0
  var lastZoomFactor: CGFloat = 1.0

  @IBAction func pinch(_ pinch: UIPinchGestureRecognizer) {
    let device = videoCapture.captureDevice

    // Return zoom value between the minimum and maximum zoom values
    func minMaxZoom(_ factor: CGFloat) -> CGFloat {
      return min(min(max(factor, minimumZoom), maximumZoom), device.activeFormat.videoMaxZoomFactor)
    }

    func update(scale factor: CGFloat) {
      do {
        try device.lockForConfiguration()
        defer {
          device.unlockForConfiguration()
        }
        device.videoZoomFactor = factor
      } catch {
        print("\(error.localizedDescription)")
      }
    }

    let newScaleFactor = minMaxZoom(pinch.scale * lastZoomFactor)
    switch pinch.state {
    case .began, .changed:
      update(scale: newScaleFactor)
      self.labelZoom.text = String(format: "%.2fx", newScaleFactor)
      self.labelZoom.font = UIFont.preferredFont(forTextStyle: .title2)
    case .ended:
      lastZoomFactor = minMaxZoom(newScaleFactor)
      update(scale: lastZoomFactor)
      self.labelZoom.font = UIFont.preferredFont(forTextStyle: .body)
    default: break
    }
  }  // Pinch to Zoom End --------------------------------------------------------------------------------------------
  
  // MARK: - OCR Processing
  
  /// Perform OCR on detected bus regions to extract bus numbers
  func performOCROnBuses(_ busObservations: [VNRecognizedObjectObservation], pixelBuffer: CVPixelBuffer) {
    // Convert the pixel buffer to a CIImage
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    
    // For each bus observation, extract the region and perform OCR
    for observation in busObservations {
      // Get the bounding box
      let boundingBox = observation.boundingBox
      
      // Convert normalized coordinates to pixel coordinates
      let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
      let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
      
      // Calculate region of interest in the image
      // Note: Vision's coordinate system has (0,0) at the bottom left
      let imageRect = CGRect(x: boundingBox.origin.x * width,
                           y: boundingBox.origin.y * height,
                           width: boundingBox.width * width,
                           height: boundingBox.height * height)
      
      // Extract the region of interest
      // We'll focus on the top third of the bus where the number is typically located
      let topThirdRect = CGRect(x: imageRect.origin.x,
                               y: imageRect.origin.y + (imageRect.height * 2/3),
                               width: imageRect.width,
                               height: imageRect.height/3)
      
      // Create a request handler with the cropped image
      // Create a Vision text recognition request
      let textRecognitionRequest = VNRecognizeTextRequest { [weak self] (request, error) in
        guard let self = self,
              let results = request.results as? [VNRecognizedTextObservation],
              !results.isEmpty else {
          return
        }
        
        // Process text recognition results
        self.processOCRResults(results)
      }
      
      // Configure the text recognition request
      textRecognitionRequest.recognitionLevel = .accurate
      textRecognitionRequest.usesLanguageCorrection = false
      textRecognitionRequest.regionOfInterest = boundingBox // Use normalized coordinates
      
      // Set recognition language to English for bus numbers
      textRecognitionRequest.recognitionLanguages = ["en-US"]
      
      // Process the request
      let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
      try? requestHandler.perform([textRecognitionRequest])
    }
  }
  
  /// Process OCR results to extract and display bus numbers
  func processOCRResults(_ results: [VNRecognizedTextObservation]) {
    // Extract text from observations
    var detectedTexts = [String]()
    
    for observation in results {
      // Get the top candidate for each text observation
      guard let candidate = observation.topCandidates(1).first else { continue }
      
      // Extract the recognized text
      let recognizedText = candidate.string
      
      // Filter for potential bus numbers (typically numeric, may include letters)
      if containsValidBusNumber(recognizedText) {
        detectedTexts.append(recognizedText)
      }
    }
    
    // Update UI with detected bus numbers
    if !detectedTexts.isEmpty {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        
        // Join all detected numbers with commas
        let busNumbersText = detectedTexts.joined(separator: ", ")
        
        // Update bus count label to include detected numbers
        self.busCountLabel.text = "Bus: \(busNumbersText)"
        
        // Make accessibility announcement
        UIAccessibility.post(
          notification: .announcement,
          argument: "Bus number \(busNumbersText) detected"
        )
        
        print("Detected bus numbers: \(busNumbersText)")
      }
    }
  }
  
  /// Check if the recognized text is likely to be a valid bus number
  func containsValidBusNumber(_ text: String) -> Bool {
    // Remove whitespace and check if empty
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return false }
    
    // Bus numbers are typically 1-3 digits, sometimes with a letter
    // This regex matches common bus number patterns
    let busNumberPattern = "^[A-Z]?\\d{1,3}[A-Z]?$"
    
    if let regex = try? NSRegularExpression(pattern: busNumberPattern, options: []) {
      let range = NSRange(location: 0, length: trimmedText.utf16.count)
      return regex.firstMatch(in: trimmedText, options: [], range: range) != nil
    }
    
    return false
  }
}  // ViewController class End

extension ViewController: VideoCaptureDelegate {
  func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
    predict(sampleBuffer: sampleBuffer)
  }
}

// Programmatically save image
extension ViewController: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
  ) {
    if let error = error {
      print("error occurred : \(error.localizedDescription)")
    }
    if let dataImage = photo.fileDataRepresentation() {
      let dataProvider = CGDataProvider(data: dataImage as CFData)
      let cgImageRef: CGImage! = CGImage(
        jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)
      var orientation = CGImagePropertyOrientation.right
      switch UIDevice.current.orientation {
      case .landscapeLeft:
        orientation = .up
      case .landscapeRight:
        orientation = .down
      default:
        break
      }
      var image = UIImage(cgImage: cgImageRef, scale: 0.5, orientation: .right)
      if let orientedCIImage = CIImage(image: image)?.oriented(orientation),
        let cgImage = CIContext().createCGImage(orientedCIImage, from: orientedCIImage.extent)
      {
        image = UIImage(cgImage: cgImage)
      }
      let imageView = UIImageView(image: image)
      imageView.contentMode = .scaleAspectFill
      imageView.frame = videoPreview.frame
      let imageLayer = imageView.layer
      videoPreview.layer.insertSublayer(imageLayer, above: videoCapture.previewLayer)

      let bounds = UIScreen.main.bounds
      UIGraphicsBeginImageContextWithOptions(bounds.size, true, 0.0)
      self.View0.drawHierarchy(in: bounds, afterScreenUpdates: true)
      let img = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
      imageLayer.removeFromSuperlayer()
      let activityViewController = UIActivityViewController(
        activityItems: [img!], applicationActivities: nil)
      activityViewController.popoverPresentationController?.sourceView = self.View0
      self.present(activityViewController, animated: true, completion: nil)
      //
      //            // Save to camera roll
      //            UIImageWriteToSavedPhotosAlbum(img!, nil, nil, nil);
    } else {
      print("AVCapturePhotoCaptureDelegate Error")
    }
  }
}


import UIKit
import AVFoundation

class CameraController: UIViewController {
    var mlModel = try! classification()
    @IBOutlet weak var descriptionLabel: UILabel!
    
    
    var captureSession = AVCaptureSession()
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configure()
    }

    override func viewDidAppear(_ animated: Bool) {
        // Start video capture.
        captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        captureSession.stopRunning()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    private func configure() {
        // Get the back-facing camera for capturing videos
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            print("Failed to get the camera device")
            return
        }
 
        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous device object.
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            // Set the input device on the capture session.
            captureSession.addInput(input)
            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "imageRecognition.queue"))
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            captureSession.addOutput(videoDataOutput)
            
                        
        } catch {
            // If any error occurs, simply print it out and don't continue any more.
            print(error)
            return
        }
        
        // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        videoPreviewLayer?.frame = view.layer.bounds
        view.layer.addSublayer(videoPreviewLayer!)
        
        // Bring the label to the front
        descriptionLabel.font = descriptionLabel.font.withSize(20)
        descriptionLabel.text = "正在检测健康码。。。"
        view.bringSubviewToFront(descriptionLabel)
        
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        connection.videoOrientation = .portrait

        // Resize the frame to 224x224
        // This is the required size of the inceptionv3 model
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let image = UIImage(ciImage: ciImage)

        UIGraphicsBeginImageContext(CGSize(width: 299, height: 299))
        image.draw(in: CGRect(x: 0, y: 0, width: 299, height: 299))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        // Convert UIImage to CVPixelBuffer
        // The code for the conversion is adapted from this post of StackOverflow
        // https://stackoverflow.com/questions/44462087/how-to-convert-a-uiimage-to-a-cvpixelbuffer

        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(resizedImage.size.width), Int(resizedImage.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: Int(resizedImage.size.width), height: Int(resizedImage.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.translateBy(x: 0, y: resizedImage.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context!)
        resizedImage.draw(in: CGRect(x: 0, y: 0, width: resizedImage.size.width, height: resizedImage.size.height))
        UIGraphicsPopContext()

        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        if let pixelBuffer = pixelBuffer,
            let output = try? mlModel.prediction(image: pixelBuffer) {

            DispatchQueue.main.async {
                self.descriptionLabel.text = output.classLabel
            }
            for (key, value) in output.classLabelProbs {
                print("\(key) = \(value)")
            }
        }
    }
}


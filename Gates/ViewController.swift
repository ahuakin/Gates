//
//  ViewController.swift
//  Screenx
//
//  Created by Efe Kosanoglu on 25.07.2023.
//

import UIKit
import AVFoundation
import Vision
import CoreImage
import SceneKit

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var mars: UIImageView!
    @IBOutlet var sceneView: SCNView!
    var scene: SCNScene!
    let cameraNode = SCNNode()
    var theNode: SCNNode!
    var theCamera: SCNNode!
    
    // Önceki yüz merkez koordinatları
    var previousFaceCenter: CGPoint?

    // Düzgünleştirme faktörü
    let smoothingFactor: CGFloat = 0.2
    
    private var previousDistanceX: CGFloat = 0
    private var previousDistanceY: CGFloat = 0

    // Define a threshold value for determining the zooming effect
    let zoomThreshold: CGFloat = 100.0 // You can adjust this value based on your needs

    // Maximum and minimum sizes for the window
    private var drawings: [CAShapeLayer] = []
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let capturesession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: capturesession)
    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()

        // Kamera girişini ekleyin
        addCameraInput()

        // Kameradan kareleri alın ve yüz tespiti yapın
        getCameraFrames()
        DispatchQueue.global(qos: .background).async {
            self.capturesession.startRunning()
        }
    }
    func setupScene() {
        scene = SCNScene(named: "Scenes.scn")
        sceneView.scene = scene

        theNode = scene.rootNode.childNode(withName: "Thenode", recursively: true)!
        theCamera = scene.rootNode.childNode(withName: "Thecamera", recursively: true)!

    }
    
    func smoothFaceCenter(newFaceCenter: CGPoint) -> CGPoint {
        // Eğer önceki yüz merkez koordinatları yoksa, ilk merkez koordinatını döndür
        guard let previousCenter = previousFaceCenter else {
            previousFaceCenter = newFaceCenter
            return newFaceCenter
            print("hi man")
        }

        // Düzgünleştirilmiş yüz merkez koordinatları hesapla
        let smoothedX = previousCenter.x + (newFaceCenter.x - previousCenter.x) * smoothingFactor
        let smoothedY = previousCenter.y + (newFaceCenter.y - previousCenter.y) * smoothingFactor

        // Yeni düzgünleştirilmiş yüz merkez koordinatları
        let smoothedFaceCenter = CGPoint(x: smoothedX, y: smoothedY)

        // Önceki yüz merkez koordinatlarını güncelle
        previousFaceCenter = smoothedFaceCenter

        return smoothedFaceCenter
    }
    


    func convertCGRectToSCNVector3(rect: CGRect) -> SCNVector3 {
        // CGRect'nin merkezini hesaplayın
        let centerX = Float(rect.midX)
        let centerY = Float(rect.midY)

        // CGPoint'ı SCNVector3'e dönüştürün (x, y, z sırasıyla)
        return SCNVector3(centerX, centerY, 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.frame

    }

    //    Image Move Part ------------------------------------------------------------------------------------------

    //    Camre Settings Part ------------------------------------------------------------------------------------------

    private func addCameraInput() {

        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInWideAngleCamera], mediaType: .video, position: .front).devices.first else{
            fatalError("fatal error")
        }

        let cameraInput = try! AVCaptureDeviceInput(device: device)
        capturesession.addInput(cameraInput)
    }

    private func showcameraFeed(){
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.frame

    }

    private func getCameraFrames() {
        videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString): NSNumber(value: kCVPixelFormatType_32BGRA)] as [String: Any]

        videoDataOutput.alwaysDiscardsLateVideoFrames = true


        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))

        capturesession.addOutput(videoDataOutput)

        guard let connection = videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported else {
            return
        }

        connection.videoOrientation = .portrait
    }

    private func detectFace(image: CVPixelBuffer) {
        let faceDetectionRequest = VNDetectFaceLandmarksRequest { vnRequest, error in
            DispatchQueue.main.async {
                if let results = vnRequest.results as? [VNFaceObservation], results.count > 0 {
                    // print("✅ Detected \(results.count) faces!")
                    self.handleFaceDetectionResults(observedFaces: results)
                } else {
                    // print("❌ No face was detected")
                    self.clearDrawings()
                }
            }
        }

        let imageResultHandler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .leftMirrored, options: [:])
        try? imageResultHandler.perform([faceDetectionRequest])
    }

    private func handleFaceDetectionResults(observedFaces: [VNFaceObservation]) {
        clearDrawings()

        // Mars görselinin merkezi
        let marsCenter = CGPoint(x: mars.center.x, y: mars.center.y)

        // Yüzler için kutular oluştur
        observedFaces.forEach { observedFace in
            // Yüz dikdörtgeninin ekran koordinatlarına dönüştürülmesi
            var faceBoundingBoxOnScreen = previewLayer.layerRectConverted(fromMetadataOutputRect: observedFace.boundingBox)

            // Eğer yüz yatay olarak algılanmışsa (boy > genişlik)
            if observedFace.boundingBox.height > observedFace.boundingBox.width {
                // Boyutları değiştirmek için genişlik ve boyu yer değiştir
                let tempWidth = faceBoundingBoxOnScreen.width
                faceBoundingBoxOnScreen.size.width = faceBoundingBoxOnScreen.height
                faceBoundingBoxOnScreen.size.height = tempWidth
            }

            // Yüz kutusunun merkezi
            let faceCenter = CGPoint(x: faceBoundingBoxOnScreen.midX, y: faceBoundingBoxOnScreen.midY)
            
            let smoothedFaceCenter = smoothFaceCenter(newFaceCenter: faceCenter)
            
            smoothFaceCenter(newFaceCenter: smoothedFaceCenter)


            // X ve Y uzaklıklarını hesapla
            let distanceX = faceCenter.x - marsCenter.x
            let distanceY = faceCenter.y - marsCenter.y

            // Yeni kamera rotasyonunu belirle
            let newCameraRotation = SCNVector3(distanceX * -1, distanceY, 0)

            // Kameranın rotasyonunu güncelle
            updateCameraRotation(rotation: newCameraRotation)

            // Yüz kutusunun şeklini oluştur
            let faceBoundingBoxPath = CGPath(rect: faceBoundingBoxOnScreen, transform: nil)
            let faceBoundingBoxShape = CAShapeLayer()
            faceBoundingBoxShape.path = faceBoundingBoxPath
            faceBoundingBoxShape.fillColor = UIColor.clear.cgColor
            faceBoundingBoxShape.strokeColor = UIColor.green.cgColor

            // Kutuyu katmana ekle
            view.layer.addSublayer(faceBoundingBoxShape)

            // Yeni çizimleri dizisine ekle
            drawings.append(faceBoundingBoxShape)

            // X ve Y uzaklıklarını güncelle
            previousDistanceX = distanceX
            previousDistanceY = distanceY

            // Yüz kutusunun boyutunu al
            let boundingBoxWidth = faceBoundingBoxOnScreen.size.width
            let boundingBoxHeight = faceBoundingBoxOnScreen.size.height

            // Yeni alan derinliğini hesapla ve kameranın görüş açısını ayarla
            let newFieldOfView = calculateFieldOfView(boundingBoxWidth: boundingBoxWidth, boundingBoxHeight: boundingBoxHeight)
            theCamera.camera?.fieldOfView = newFieldOfView
        }
    }

    private func calculateFieldOfView(boundingBoxWidth: CGFloat, boundingBoxHeight: CGFloat) -> CGFloat {
        // Ölçek faktörünü hesapla (genişlik ve yükseklikten)
        let scaleFactor = (boundingBoxWidth + boundingBoxHeight) / zoomThreshold
        // Yeni alan derinliğini hesapla
        let newFieldOfView = scaleFactor * 25 // İsteğe bağlı bir katsayı ile çarpabilirsiniz
        return newFieldOfView
    }



    func updateCameraRotation(rotation: SCNVector3, speedFactor: Float = 500) {
        // Hız faktörünü kullanarak rotasyonu ayarla
        let adjustedRotation = SCNVector3(rotation.x / speedFactor, rotation.y / speedFactor, rotation.z / speedFactor)
        theNode.eulerAngles = adjustedRotation
    }





    private func clearDrawings() {
        drawings.forEach({ drawing in drawing.removeFromSuperlayer() })
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugPrint("Unable to get image from the sample buffer")
            return
        }

        detectFace(image: frame)
    }

}
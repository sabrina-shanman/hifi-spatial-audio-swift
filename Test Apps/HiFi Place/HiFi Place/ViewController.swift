//
//  ViewController.swift
//
//  Created by Zach Fox on 2021-05-25.
//  Copyright 2021 High Fidelity, Inc.
//

import UIKit
import CoreLocation
import CoreMotion
import HiFiSpatialAudio
import Promises
import JWTKit

struct HiFiJWT: JWTPayload {
    enum CodingKeys: String, CodingKey {
        case user_id = "user_id"
        case app_id = "app_id"
        case space_name = "space_name"
    }
    
    var user_id: String
    var app_id: String
    var space_name: String
    
    func verify(using signer: JWTSigner) throws {
        if (self.app_id == "") {
            throw NSError(domain: "", code: 1, userInfo: ["error": "app_id was blank"])
        }
        if (self.space_name == "") {
            throw NSError(domain: "", code: 1, userInfo: ["error": "space_name was blank"])
        }
    }
}

struct AvatarData {
    var position: Point3D
    var orientationEuler: OrientationEuler3D
    var volumeDecibels: Float
}

extension UIColor {
    public convenience init(hex: String) {
        let r, g, b, a: CGFloat

        if hex.hasPrefix("#") {
            let start = hex.index(hex.startIndex, offsetBy: 1)
            let hexColor = String(hex[start...])

            if hexColor.count == 8 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0

                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
                    g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
                    b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
                    a = CGFloat(hexNumber & 0x000000ff) / 255

                    self.init(red: r, green: g, blue: b, alpha: a)
                    return
                }
            } else if hexColor.count == 6 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0

                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
                    g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
                    b = CGFloat((hexNumber & 0x0000ff) >> 0) / 255
                    self.init(red: r, green: g, blue: b, alpha: 255)
                    return
                }
            }
        }
        
        self.init(red: 0, green: 0, blue: 0, alpha: 255)
        return
    }
}

extension String {
    func padLeft (totalWidth: Int, with: String) -> String {
        let toPad = totalWidth - self.count
        if toPad < 1 { return self }
        return "".padding(toLength: toPad, withPad: with, startingAt: 0) + self
    }
}

class DataModel : NSObject, CLLocationManagerDelegate, CMHeadphoneMotionManagerDelegate, ObservableObject {
    @Published var hostURL: String = "api.highfidelity.com"
    @Published var appID: String = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    @Published var appSecret: String = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    @Published var spaceName: String = "ABCDEFGHI"
    
    @Published var myHashedVisitID: String? = nil
    @Published var myAvatarOrientationRadians: Double = 0.0
    @Published var myAvatarPosition = Point3D()
    @Published var myAvatarVolumeDecibels: Float = -96.0
    @Published var isMuted: Bool = false
    
    var otherAvatarData: [String : AvatarData] = [:]
    
    var communicator: HiFiCommunicator? = nil
    var audioAPIData = HiFiAudioAPIData()
    
    let locationManager = CLLocationManager()
    let headphoneMotionManager = CMHeadphoneMotionManager()
    var usingDeviceOrHeadphoneMotion = false
    var usingHeadphoneMotion = false
    
    var lastDeviceYawRadians: Double? = nil
    var lastHeadphonesYawRadians: Double? = nil
    
    override init() {
        print("Initializing `DataModel`...")
        
        super.init()
        
        self.audioAPIData = HiFiAudioAPIData(position: Point3D(), orientationEuler: OrientationEuler3D())
        
        HiFiLogger.setHiFiLogLevel(newLogLevel: HiFiLogLevel.debug)
        
        locationManager.delegate = self
        headphoneMotionManager.delegate = self
        
        if (CLLocationManager.headingAvailable()) {
            print("Using device motion to drive avatar orientation.")
            self.usingHeadphoneMotion = false
            self.locationManager.headingFilter = kCLHeadingFilterNone
            self.locationManager.startUpdatingHeading()
        }
        
        self.initHeadphoneMotion()
    }
    
    func connect() {
        if (self.appSecret.count == 0) {
            HiFiLogger.error("Couldn't create HiFi JWT: App Secret was blank!")
            return
        }
        
        let signers = JWTSigners()
        signers.use(.hs256(key: self.appSecret))
        
        let payload = HiFiJWT(
            user_id: "iOS Test",
            app_id: self.appID,
            space_name: self.spaceName
        )
        
        let hifiJWT: String
        do {
            hifiJWT = try signers.sign(payload)
        } catch {
            HiFiLogger.error("Couldn't create HiFi JWT:\n\(error)")
            return
        }
        
        self.communicator = HiFiCommunicator(initialHiFiAudioAPIData: self.audioAPIData)
        
        print("Connecting to HiFi Audio API server...")
        
        self.communicator!.connectToHiFiAudioAPIServer(hifiAuthJWT: hifiJWT, signalingHostURL: self.hostURL).then { response in
            print("Successfully connected! Response:\n\(response)")
            
            if (response.success) {
                self.myHashedVisitID = response.responseData!.visit_id_hash
                
                self.communicator?.addUserDataSubscription(newSubscription: UserDataSubscription(providedUserID: nil, components: [.VolumeDecibels, .Position, .OrientationEuler], callback: { allReceivedData in
                    for receivedData in allReceivedData {
                        if (receivedData.hashedVisitID == self.myHashedVisitID) {
                            if (receivedData.volumeDecibels != nil) {
//                                DispatchQueue.main.async {
                                    self.myAvatarVolumeDecibels = receivedData.volumeDecibels!
//                                }
                            }
                        } else if (receivedData.hashedVisitID != nil) {
                            if (self.otherAvatarData[receivedData.hashedVisitID!] == nil) {
//                                DispatchQueue.main.async {
                                    self.otherAvatarData[receivedData.hashedVisitID!] = AvatarData(position: Point3D(), orientationEuler: OrientationEuler3D(), volumeDecibels: -96.0)
//                                }
                            }
                            
                            if (receivedData.volumeDecibels != nil) {
//                                DispatchQueue.main.async {
                                    self.otherAvatarData[receivedData.hashedVisitID!]!.volumeDecibels = receivedData.volumeDecibels!
//                                }
                            }
                            if (receivedData.position != nil) {
//                                DispatchQueue.main.async {
                                    self.otherAvatarData[receivedData.hashedVisitID!]!.position = receivedData.position!
//                                }
                            }
                            if (receivedData.orientationEuler != nil) {
//                                DispatchQueue.main.async {
                                    self.otherAvatarData[receivedData.hashedVisitID!]!.orientationEuler = receivedData.orientationEuler!
//                                }
                            }
                        }
                    }
                }))
            } else {
                print("Failed to connect!")
            }
        }.catch { error in
            print("Failed to connect! Error:\n\(error)")
        }
    }
    
    func disconnect() {
        self.communicator!.disconnectFromHiFiAudioAPIServer().then { disconnectedResult in
            print("Disconnect status: \(disconnectedResult)")
        }.catch { error in
            print("Failed to disconnect! Error:\n\(error)")
        }
    }
    
    func enableDeviceMotion() {
        if (self.usingDeviceOrHeadphoneMotion) {
            return
        }
        
        self.usingDeviceOrHeadphoneMotion = true
        print("USING device motion to drive avatar orientation.")
    }
    
    func disableDeviceMotion() {
        if (!self.usingDeviceOrHeadphoneMotion) {
            return
        }
        
        self.usingDeviceOrHeadphoneMotion = false
        print("NOT USING device motion to drive avatar orientation.")
    }
    
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphone motion manager connected!")
        self.initHeadphoneMotion()
    }
    
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphone motion manager disconnected!")
        self.usingHeadphoneMotion = false
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        let currentMagneticHeadingRadians = heading.magneticHeading * Double.pi / 180
        if (!self.usingHeadphoneMotion) {
            if (self.usingDeviceOrHeadphoneMotion) {
                let radiansDelta = (currentMagneticHeadingRadians - (self.lastDeviceYawRadians ?? 0.0))
                
                var newRadians = self.myAvatarOrientationRadians + radiansDelta
                newRadians = newRadians.truncatingRemainder(dividingBy: (2 * Double.pi))
                if (newRadians < 0.0) {
                    newRadians += 2 * Double.pi
                }
                
                self.myAvatarOrientationRadians = newRadians
                self.audioAPIData.orientationEuler!.yawDegrees = -1 * newRadians * 180.0 / Double.pi
                _ = self.communicator?.updateUserDataAndTransmit(newUserData: self.audioAPIData)
            }
        }
        self.lastDeviceYawRadians = currentMagneticHeadingRadians
    }
    
    func initHeadphoneMotion() {
        if (self.headphoneMotionManager.isDeviceMotionAvailable) {
            print("Starting headphone motion updates...")
            self.headphoneMotionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (motion, error) in
                if (!self.usingHeadphoneMotion) {
                    self.usingHeadphoneMotion = true
                    print("Now using headphone motion instead of device motion...")
                }
                
                if (self.usingDeviceOrHeadphoneMotion) {
                    let radiansDelta = ((motion?.attitude.yaw)! - (self.lastHeadphonesYawRadians ?? 0))
                    
                    var newRadians = self.myAvatarOrientationRadians - radiansDelta
                    newRadians = newRadians.truncatingRemainder(dividingBy: (2 * Double.pi))
                    if (newRadians < 0.0) {
                        newRadians += 2 * Double.pi
                    }
                    
                    self.myAvatarOrientationRadians = newRadians
                    self.audioAPIData.orientationEuler!.yawDegrees = -1 * newRadians * 180.0 / Double.pi
                    _ = self.communicator?.updateUserDataAndTransmit(newUserData: self.audioAPIData)
                }
                
                self.lastHeadphonesYawRadians = (motion?.attitude.yaw)!
            }
        }
    }
}

class ViewController: UIViewController {
    var dataModel: DataModel = DataModel()
    private var drawTimer: Timer? = nil
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var muteMicSwitchLabel: UILabel!
    @IBOutlet weak var muteMicSwitch: UISwitch!
    @IBOutlet weak var deviceOrientationSwitchLabel: UILabel!
    @IBOutlet weak var deviceOrientationSwitch: UISwitch!
    var startingRotationGestureYawRadians: CGFloat? = nil
    let mapImage: UIImage = UIImage(named: "Demo_map")!
    var mapImageCG: CGImage?
    let genericAvatarImage: UIImage = UIImage(named: "generic_avatar_image")!
    var genericAvatarImageCG: CGImage?
    var pxPerM: CGFloat = 50
    let AVATAR_SIZE_MIN_M: CGFloat = 0.2
    let AVATAR_SIZE_MAX_M: CGFloat = 0.35
    let AVATAR_DIRECTION_CIRCLE_SIZE_M: CGFloat = 0.08
    var context: CGContext?
    
    let SPACE_DIMENSION_MAX_M: CGFloat = 24.0

    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        self.setupLabelTaps()
        self.setupRotationHandler()
        
        self.mapImageCG = self.mapImage.cgImage!
        self.genericAvatarImageCG = self.genericAvatarImage.cgImage!
        
        DispatchQueue.main.async {
            self.drawTimer = Timer.scheduledTimer(
                withTimeInterval: 0.03333,
                repeats: true
            ) { (timer) in
                self.drawAll()
            }
        }
        
        self.dataModel.connect()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    @objc func muteMicSwitchLabelTapped(_ sender: UITapGestureRecognizer) {
        if (self.dataModel.communicator == nil) {
            self.dataModel.isMuted = false
            self.muteMicSwitch.isOn = false
            return
        }
        
        self.muteMicSwitch.isOn = !self.dataModel.isMuted
        self.dataModel.communicator?.setInputAudioMuted(isMuted: muteMicSwitch.isOn)
        self.dataModel.isMuted = self.muteMicSwitch.isOn
    }
    
    @objc func deviceOrientationSwitchLabelTapped(_ sender: UITapGestureRecognizer) {
        self.deviceOrientationSwitch.isOn = !self.deviceOrientationSwitch.isOn
        if (self.dataModel.usingDeviceOrHeadphoneMotion) {
            self.dataModel.disableDeviceMotion()
        } else {
            self.dataModel.enableDeviceMotion()
        }
    }
    
    func setupLabelTaps() {
        let muteMicSwitchLabelTap = UITapGestureRecognizer(target: self, action: #selector(self.muteMicSwitchLabelTapped(_:)))
        self.muteMicSwitchLabel.isUserInteractionEnabled = true
        self.muteMicSwitchLabel.addGestureRecognizer(muteMicSwitchLabelTap)
        
        let deviceOrientationSwitchLabelTap = UITapGestureRecognizer(target: self, action: #selector(self.deviceOrientationSwitchLabelTapped(_:)))
        self.deviceOrientationSwitchLabel.isUserInteractionEnabled = true
        self.deviceOrientationSwitchLabel.addGestureRecognizer(deviceOrientationSwitchLabelTap)
    }
    
    @objc func onImageViewRotation(_ gestureRecognizer: UIRotationGestureRecognizer) {
        guard gestureRecognizer.view != nil else { return }
        
        if (gestureRecognizer.state == .began) {
            self.startingRotationGestureYawRadians = gestureRecognizer.rotation
        } else if (gestureRecognizer.state == .changed) {
            self.dataModel.myAvatarOrientationRadians -= Double(gestureRecognizer.rotation - (self.startingRotationGestureYawRadians ?? 0.0))
            self.startingRotationGestureYawRadians = gestureRecognizer.rotation
            
            if (self.dataModel.communicator != nil) {
                self.dataModel.audioAPIData.orientationEuler!.yawDegrees = -1 * self.dataModel.myAvatarOrientationRadians * 180.0 / Double.pi
                _ = self.dataModel.communicator!.updateUserDataAndTransmit(newUserData: self.dataModel.audioAPIData)
            }
        }
    }
    
    func setupRotationHandler() {
        let imageViewRotation = UIRotationGestureRecognizer(target: self, action: #selector(self.onImageViewRotation(_:)))
        self.imageView.isUserInteractionEnabled = true
        self.imageView.isMultipleTouchEnabled = true
        self.imageView.addGestureRecognizer(imageViewRotation)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let firstTouch = touches.first
        if (firstTouch?.view != self.imageView!) {
            return;
        }
        
        let firstPoint = firstTouch!.location(in: self.imageView)
        
        if (touches.count > 1) {
            let secondTouch = Array(touches)[1]
            let secondPoint = secondTouch.location(in: self.imageView)
            
            var xMovement = secondPoint.x - firstPoint.x
            var yMovement = secondPoint.y - firstPoint.y
            let currentTwoTouchDistance = sqrt(xMovement * xMovement + yMovement * yMovement)
            
            let prevFirstPoint = firstTouch?.previousLocation(in: self.imageView)
            let prevSecondPoint = secondTouch.previousLocation(in: self.imageView)
            xMovement = prevSecondPoint.x - (prevFirstPoint?.x ?? 0)
            yMovement = prevSecondPoint.y - (prevFirstPoint?.y ?? 0)
            let prevTwoTouchDistance = sqrt(xMovement * xMovement + yMovement * yMovement)
            
            let twoTouchDistanceDelta = currentTwoTouchDistance - prevTwoTouchDistance
            
            pxPerM += twoTouchDistanceDelta * 0.2
            
            pxPerM = self.clamp(value: pxPerM, min: 50, max: 120)
        } else {
            let prevFirstPoint = firstTouch?.previousLocation(in: self.imageView)
            
            let deltaX: CGFloat = firstPoint.x - (prevFirstPoint?.x ?? 0)
            let deltaY: CGFloat = firstPoint.y - (prevFirstPoint?.y ?? 0)
            
            let rotatedDeltaX = deltaX * cos(CGFloat(self.dataModel.myAvatarOrientationRadians)) - deltaY * sin(CGFloat(self.dataModel.myAvatarOrientationRadians))
            let rotatedDeltaY = deltaX * sin(CGFloat(self.dataModel.myAvatarOrientationRadians)) + deltaY * cos(CGFloat(self.dataModel.myAvatarOrientationRadians))
            
            self.dataModel.myAvatarPosition.x -= Double(rotatedDeltaX / pxPerM)
            self.dataModel.myAvatarPosition.y -= Double(rotatedDeltaY / pxPerM)
            
            self.dataModel.myAvatarPosition.x = Double(self.clamp(value: CGFloat(self.dataModel.myAvatarPosition.x), min: 0.0, max: SPACE_DIMENSION_MAX_M))
            self.dataModel.myAvatarPosition.y = Double(self.clamp(value: CGFloat(self.dataModel.myAvatarPosition.y), min: 0.0, max: SPACE_DIMENSION_MAX_M))
        }
        
        self.dataModel.audioAPIData.position!.x = self.dataModel.myAvatarPosition.x
        self.dataModel.audioAPIData.position!.z = self.dataModel.myAvatarPosition.y
        _ = self.dataModel.communicator!.updateUserDataAndTransmit(newUserData: self.dataModel.audioAPIData)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    }
    
    
    @IBAction func muteMicSwitchValueChanged(_ sender: Any) {
        if (self.dataModel.communicator == nil) {
            self.dataModel.isMuted = false
            self.muteMicSwitch.isOn = false
            return
        }
        self.dataModel.communicator!.setInputAudioMuted(isMuted: muteMicSwitch.isOn)
        self.dataModel.isMuted = self.muteMicSwitch.isOn
    }
    
    
    @IBAction func deviceOrientationSwitchValueChanged(_ sender: Any) {
        if (deviceOrientationSwitch.isOn) {
            self.dataModel.enableDeviceMotion()
        } else {
            self.dataModel.disableDeviceMotion()
        }
    }
    
    func clamp(value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return fmin(fmax(value, min), max);
    }
    
    func linearScale(factor: CGFloat, minInput: CGFloat, maxInput: CGFloat, minOutput: CGFloat, maxOutput: CGFloat, clampInput: Bool = false) -> CGFloat {
        var fac = factor
        if (clampInput) {
            fac = self.clamp(value: factor, min: minInput, max: maxInput)
        }
        
        return minOutput + (maxOutput - minOutput) * (fac - minInput) / (maxInput - minInput)
    }
    
    func hexColorFromString(string: String) -> String {
        var hash: UInt32 = 0
        
        let utfString = string.utf8
        for character in Array(utfString) {
            hash = UInt32(character) &+ ((hash &<< 5) &- hash);
        }
        
        let color = (hash & 0x00FFFFFF)
        let colorString = String(format: "%02X", color)
        let returnString = "#" + colorString.padLeft(totalWidth: 6, with: "0")
        return returnString
    }
    
    func drawAvatar(context: CGContext, position: CGVector, orientationRadians: CGFloat, avatarSizeM: CGFloat, color: CGColor) {
        context.translateBy(x: position.dx, y: position.dy)
        let rotationRadians = orientationRadians
        
        var avatarRect = CGRect(
            x: -(avatarSizeM / 2) * pxPerM,
            y: -(avatarSizeM / 2) * pxPerM,
            width: avatarSizeM * pxPerM,
            height: avatarSizeM * pxPerM
        )
        context.setFillColor(color)
        context.setLineWidth(0.02 * pxPerM)
        context.setStrokeColor(UIColor.white.cgColor)
        context.addEllipse(in: avatarRect)
        context.drawPath(using: .fillStroke)
        
        avatarRect = CGRect(
            x: -(AVATAR_SIZE_MIN_M / 2) * pxPerM,
            y: -(AVATAR_SIZE_MIN_M / 2) * pxPerM,
            width: AVATAR_SIZE_MIN_M * pxPerM,
            height: AVATAR_SIZE_MIN_M * pxPerM
        )
        context.rotate(by: CGFloat(self.dataModel.myAvatarOrientationRadians))
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(genericAvatarImageCG!, in: avatarRect)
        context.scaleBy(x: 1.0, y: -1.0)
        context.rotate(by: CGFloat(-self.dataModel.myAvatarOrientationRadians))
        
        // START Draw direction circle
        context.rotate(by: rotationRadians)
        context.translateBy(x: CGFloat(0.0) * pxPerM, y: CGFloat(-avatarSizeM / 2) * pxPerM)
        avatarRect = CGRect(
            x: -(AVATAR_DIRECTION_CIRCLE_SIZE_M / 2) * pxPerM,
            y: -(AVATAR_DIRECTION_CIRCLE_SIZE_M / 2) * pxPerM,
            width: AVATAR_DIRECTION_CIRCLE_SIZE_M * pxPerM,
            height: AVATAR_DIRECTION_CIRCLE_SIZE_M * pxPerM
        )
        context.setFillColor(UIColor.white.cgColor)
        context.addEllipse(in: avatarRect)
        context.drawPath(using: .fill)
        context.translateBy(x: CGFloat(0.0) * pxPerM, y: CGFloat(avatarSizeM / 2) * pxPerM)
        // END Draw direction circle
        
        context.rotate(by: -rotationRadians)
        context.translateBy(x: -position.dx, y: -position.dy)
    }
    
    func drawMap() {
        // Draw the map image
        let mapImageRect = CGRect(
            x: 0,
            y: 0,
            width: SPACE_DIMENSION_MAX_M * pxPerM,
            height: SPACE_DIMENSION_MAX_M * pxPerM
        )
        context!.translateBy(x: 0, y: mapImageRect.height)
        context!.scaleBy(x: 1.0, y: -1.0)
        context!.draw(mapImageCG!, in: mapImageRect)
        context!.scaleBy(x: 1.0, y: -1.0)
        context!.translateBy(x: 0, y: -mapImageRect.height)
    }
    
    func drawOtherAvatars() {
        for (hashedVisitID, avatarData) in self.dataModel.otherAvatarData {
            self.drawAvatar(
                context: context!,
                position: CGVector(
                    dx: CGFloat(avatarData.position.x) * pxPerM,
                    dy: CGFloat(avatarData.position.z) * pxPerM),
                orientationRadians: CGFloat(Float(-avatarData.orientationEuler.yawDegrees) * Float.pi / 180),
                avatarSizeM: self.linearScale(
                    factor: CGFloat(avatarData.volumeDecibels),
                    minInput: -96,
                    maxInput: 0,
                    minOutput: AVATAR_SIZE_MIN_M, maxOutput: AVATAR_SIZE_MAX_M,
                    clampInput: true
                ),
                color: UIColor(hex: self.hexColorFromString(string: hashedVisitID)).cgColor
            )
        }
    }
    
    func drawMyAvatar() {
        self.drawAvatar(
            context: context!,
            position: CGVector(
                dx: CGFloat(self.dataModel.myAvatarPosition.x) * pxPerM,
                dy: CGFloat(self.dataModel.myAvatarPosition.y) * pxPerM),
            orientationRadians: CGFloat(self.dataModel.myAvatarOrientationRadians),
            avatarSizeM: self.linearScale(
                factor: CGFloat(self.dataModel.myAvatarVolumeDecibels),
                minInput: -96,
                maxInput: 0,
                minOutput: AVATAR_SIZE_MIN_M, maxOutput: AVATAR_SIZE_MAX_M,
                clampInput: true
            ),
            color: UIColor(hex: self.hexColorFromString(string: self.dataModel.myHashedVisitID ?? "")).cgColor
        )
    }
    
    func drawBackground(imageViewRect: CGRect) {
        // Draw the background color
        context!.addRect(imageViewRect)
        context!.setFillColor(UIColor(hex: "#272B72").cgColor)
        context!.drawPath(using: .fillStroke)
    }
    
    func setupContext(imageViewRect: CGRect, cameraPositionNoOffsetM: CGVector, canvasOffsetPX: CGVector) {
        context!.translateBy(x: canvasOffsetPX.dx, y: canvasOffsetPX.dy)
        context!.translateBy(x: cameraPositionNoOffsetM.dx * pxPerM, y: cameraPositionNoOffsetM.dy * pxPerM)
        context!.rotate(by: CGFloat(-self.dataModel.myAvatarOrientationRadians))
        context!.translateBy(x: -cameraPositionNoOffsetM.dx * pxPerM, y: -cameraPositionNoOffsetM.dy * pxPerM)
    }
    
    func unsetupContext(imageViewRect: CGRect, cameraPositionNoOffsetM: CGVector, canvasOffsetPX: CGVector) {
        context!.translateBy(x: cameraPositionNoOffsetM.dx * pxPerM, y: cameraPositionNoOffsetM.dy * pxPerM)
        context!.rotate(by: CGFloat(self.dataModel.myAvatarOrientationRadians))
        context!.translateBy(x: -cameraPositionNoOffsetM.dx * pxPerM, y: -cameraPositionNoOffsetM.dy * pxPerM)
        context!.translateBy(x: -canvasOffsetPX.dx, y: -canvasOffsetPX.dy)
    }
    
    func blit() {
        let outputImage = UIGraphicsGetImageFromCurrentImageContext()
        //UIGraphicsEndImageContext()
        imageView.image = outputImage
    }
    
    func drawAll() {
        if (self.context == nil) {
            let imageViewSize = imageView.frame.size
            let opaque = true
            let scale: CGFloat = 0
            UIGraphicsBeginImageContextWithOptions(imageViewSize, opaque, scale)
            self.context = UIGraphicsGetCurrentContext()
        }
        
        let imageViewRect = CGRect(
            x: imageView.frame.minX,
            y: imageView.frame.minY,
            width: imageView.frame.size.width,
            height: imageView.frame.size.height
        )
        
        if (context == nil) {
            return
        }
        
        let cameraOffsetYPX: CGFloat = imageViewRect.height / 2 - imageViewRect.height / 5
        
        let cameraPositionNoOffsetM = CGVector(
            dx: CGFloat(self.dataModel.myAvatarPosition.x),
            dy: CGFloat(self.dataModel.myAvatarPosition.y)
        )
        let canvasOffsetPX = CGVector(
            dx: imageViewRect.width / CGFloat(2.0) - CGFloat(cameraPositionNoOffsetM.dx) * pxPerM,
            dy: imageViewRect.height / CGFloat(2.0) - CGFloat(cameraPositionNoOffsetM.dy) * pxPerM + cameraOffsetYPX
        )
        
        drawBackground(imageViewRect: imageViewRect)
        
        setupContext(imageViewRect: imageViewRect, cameraPositionNoOffsetM: cameraPositionNoOffsetM, canvasOffsetPX: canvasOffsetPX)
        
        drawMap()
        drawOtherAvatars()
        drawMyAvatar()
        
        unsetupContext(imageViewRect: imageViewRect, cameraPositionNoOffsetM: cameraPositionNoOffsetM, canvasOffsetPX: canvasOffsetPX)
        
        blit()
    }
}


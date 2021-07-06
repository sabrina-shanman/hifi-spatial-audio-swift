//
//  ViewController.swift
//
//  Created by Zach Fox on 2021-05-26.
//  Copyright 2021 High Fidelity, Inc.
//

import UIKit
import CoreLocation
import CoreMotion
import HiFiSpatialAudio
import Promises
import JWTKit
import MapKit

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

func clamp(value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
    return fmin(fmax(value, min), max);
}

func linearScale(factor: CGFloat, minInput: CGFloat, maxInput: CGFloat, minOutput: CGFloat, maxOutput: CGFloat, clampInput: Bool = false) -> CGFloat {
    var fac = factor
    if (clampInput) {
        fac = clamp(value: factor, min: minInput, max: maxInput)
    }
    
    return minOutput + (maxOutput - minOutput) * (fac - minInput) / (maxInput - minInput)
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

private extension MKMapView {
    func centerToLocation(
        _ location: CLLocation,
        regionRadius: CLLocationDistance = 1000
    ) {
        let coordinateRegion = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: regionRadius,
            longitudinalMeters: regionRadius)
        setRegion(coordinateRegion, animated: true)
    }
}

let unionSquareCenter = CLLocation(latitude: 37.78791580632116, longitude: -122.40751566482355)

class HiFiUserAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    var hashedVisitID: String
    var audioLevelDecibels: CGFloat
    var orientationRadians: CGFloat
    
    init(
        coordinate: CLLocationCoordinate2D,
        title: String,
        audioLevelDecibels: CGFloat,
        orientationRadians: CGFloat,
        hashedVisitID: String
    ) {
        self.coordinate = coordinate
        self.title = title
        self.audioLevelDecibels = audioLevelDecibels
        self.orientationRadians = orientationRadians
        self.hashedVisitID = hashedVisitID
    }
}

let pxPerM: CGFloat = 50
let AVATAR_SIZE_MIN_M: CGFloat = 0.2 * 3
let AVATAR_SIZE_MAX_M: CGFloat = 0.35 * 3
let AVATAR_DIRECTION_CIRCLE_SIZE_M: CGFloat = 0.05 * 3
class HiFiUsersAnnotationView: MKAnnotationView {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        self.isOpaque = false
        self.frame = CGRect(x: 0, y: 0, width: (AVATAR_SIZE_MAX_M + AVATAR_DIRECTION_CIRCLE_SIZE_M) * pxPerM, height: (AVATAR_SIZE_MAX_M + AVATAR_DIRECTION_CIRCLE_SIZE_M) * pxPerM)
    }
    
    override func draw(_ rect: CGRect) {
        let hiFiUserAnnotation = self.annotation as! HiFiUserAnnotation
        
        let genericAvatarImage: UIImage = UIImage(named: "generic_avatar_image")!
        
        let avatarSizeM = linearScale(
            factor: hiFiUserAnnotation.audioLevelDecibels,
            minInput: -96,
            maxInput: 0,
            minOutput: AVATAR_SIZE_MIN_M, maxOutput: AVATAR_SIZE_MAX_M,
            clampInput: true
        )
        
        let opaque = false
        let scale: CGFloat = 0
        UIGraphicsBeginImageContextWithOptions(self.frame.size, opaque, scale)
        let context = UIGraphicsGetCurrentContext()
        
        context!.translateBy(x: self.frame.width / 2, y: self.frame.height / 2)
        
        var avatarRect = CGRect(
            x: -(avatarSizeM * pxPerM / 2),
            y: -(avatarSizeM * pxPerM / 2),
            width: avatarSizeM * pxPerM,
            height: avatarSizeM * pxPerM
        )
        let color = UIColor(hex: hexColorFromString(string: String(hiFiUserAnnotation.hashedVisitID))).cgColor
        context!.setFillColor(color)
        context!.addEllipse(in: avatarRect)
        context!.drawPath(using: .fill)
        
        avatarRect = CGRect(
            x: -(AVATAR_SIZE_MIN_M / 2) * pxPerM,
            y: -(AVATAR_SIZE_MIN_M / 2) * pxPerM,
            width: AVATAR_SIZE_MIN_M * pxPerM,
            height: AVATAR_SIZE_MIN_M * pxPerM
        )
        
        context!.setLineWidth(AVATAR_DIRECTION_CIRCLE_SIZE_M / 4 * pxPerM)
        context!.setStrokeColor(UIColor.white.cgColor)
        context!.addEllipse(in: avatarRect)
        context!.drawPath(using: .stroke)
        
        context!.scaleBy(x: 1.0, y: -1.0)
        context!.draw(genericAvatarImage.cgImage!, in: avatarRect)
        context!.scaleBy(x: 1.0, y: -1.0)
        
        // START Draw direction circle
        context!.rotate(by: hiFiUserAnnotation.orientationRadians - myAvatarOrientationRadians)
        context!.translateBy(x: 0, y: -(AVATAR_SIZE_MIN_M * pxPerM / 2))
        avatarRect = CGRect(
            x: -(AVATAR_DIRECTION_CIRCLE_SIZE_M / 2) * pxPerM,
            y: -(AVATAR_DIRECTION_CIRCLE_SIZE_M / 2) * pxPerM,
            width: AVATAR_DIRECTION_CIRCLE_SIZE_M * pxPerM,
            height: AVATAR_DIRECTION_CIRCLE_SIZE_M * pxPerM
        )
        context!.setFillColor(UIColor.white.cgColor)
        context!.addEllipse(in: avatarRect)
        context!.drawPath(using: .fill)
        context!.translateBy(x: 0, y: (AVATAR_SIZE_MIN_M * pxPerM / 2))
        context!.rotate(by: -(hiFiUserAnnotation.orientationRadians - myAvatarOrientationRadians))
        // END Draw direction circle
        
        context!.translateBy(x: -self.frame.width / 2, y: -self.frame.height / 2)
        
        image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }
}

class HiFiUsersOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    
    override init() {
        coordinate = unionSquareCenter.coordinate
        boundingMapRect = MKMapRect(origin: MKMapPoint(unionSquareCenter.coordinate), size: MKMapSize(width: 1000.0, height: 1000.0))
        super.init()
    }
}

class HiFiUsersOverlayView: MKOverlayRenderer {
    let overlayImage: UIImage
    
    init(overlay: MKOverlay, overlayImage: UIImage) {
        self.overlayImage = overlayImage
        super.init(overlay: overlay)
    }
    
    override func draw(
        _ mapRect: MKMapRect,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) {
        guard let imageReference = overlayImage.cgImage else { return }
        
        let rect = self.rect(for: overlay.boundingMapRect)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: 0.0, y: -rect.size.height)
        context.draw(imageReference, in: rect)
    }
}

var myAvatarOrientationRadians: CGFloat = 0.0
var myAvatarVolumeDecibels: Float = -96.0
var myHashedVisitID: String? = nil
class DataModel : NSObject, ObservableObject {
    @Published var hostURL: String = "api.highfidelity.com"
    @Published var appID: String = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    @Published var appSecret: String = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    @Published var spaceName: String = "ABCDEFGHI"
    
    var audioAPIData = HiFiAudioAPIData()
    @Published var isMuted: Bool = false
    
    var communicator: HiFiCommunicator? = nil
    var otherAvatarData: [String : AvatarData] = [:]
    
    override init() {
        print("Initializing `DataModel`...")
        
        super.init()
        
        self.audioAPIData = HiFiAudioAPIData(position: Point3D(), orientationEuler: OrientationEuler3D())
        
        HiFiLogger.setHiFiLogLevel(newLogLevel: HiFiLogLevel.debug)
    }
}

let EARTH_RADIUS_M: Double = 6370000 // ~radius of Earth at Union Square latitude
let AUDIO_ENVIRONMENT_SCALE_FACTOR = 0.75
let MIN_IRL_MOVEMENT_FOR_HEADING_UPDATE_METERS = 0.05
class ViewController: UIViewController, CLLocationManagerDelegate, CMHeadphoneMotionManagerDelegate, MKMapViewDelegate {
    var dataModel: DataModel = DataModel()
    private var drawTimer: Timer? = nil
    @IBOutlet weak var mainMapView: MKMapView!
    @IBOutlet weak var muteMicSwitchLabel: UILabel!
    @IBOutlet weak var muteMicSwitch: UISwitch!
    @IBOutlet weak var proxSensorSwitchLabel: UILabel!
    @IBOutlet weak var proxSensorSwitch: UISwitch!
    var startingRotationGestureYawRadians: CGFloat? = nil
    let AVATAR_SIZE_MIN_M: CGFloat = 0.2
    let AVATAR_SIZE_MAX_M: CGFloat = 0.35
    let AVATAR_DIRECTION_CIRCLE_SIZE_M: CGFloat = 0.08
    var context: CGContext?
    
    let locationManager = CLLocationManager()
    let headphoneMotionManager = CMHeadphoneMotionManager()
    
    var lastRecordedLocation: CLLocation? = nil
    var startingRealWorldLocation: CLLocation? = nil
    
    var originalDistance: CLLocationDistance? = nil
    var lastDeviceYawRadians: Double? = nil
    var lastHeadphonesYawRadians: Double? = nil
    
    var emulatingProxSensorCovered = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        locationManager.delegate = self
        headphoneMotionManager.delegate = self
        
        if (CLLocationManager.headingAvailable()) {
            self.locationManager.headingFilter = kCLHeadingFilterNone
            self.locationManager.startUpdatingHeading()
        }
        
        self.locationManager.requestAlwaysAuthorization()
        self.locationManager.requestLocation()
        if (CLLocationManager.locationServicesEnabled()) {
            self.locationManager.startUpdatingLocation()
        }
        
        self.initHeadphoneMotion()
        self.enableProximitySensor()
        
        self.setupLabelTaps()
        self.setupMapPinchHandler()
        
        mainMapView.centerToLocation(unionSquareCenter)
        let zoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 0.0001, maxCenterCoordinateDistance: 10000)
        mainMapView.setCameraZoomRange(zoomRange, animated: true)
        mainMapView.mapType = .satelliteFlyover
        // Don't move the map view with the user's real-world location so that we can map
        // the user's location to the location around Union Square.
        mainMapView.setUserTrackingMode(.none, animated: false)
        
        let overlay = HiFiUsersOverlay()
        mainMapView.addOverlay(overlay)
        mainMapView.delegate = self
        
        self.connect()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    func connect() {
        if (self.dataModel.appSecret.count == 0) {
            HiFiLogger.error("Couldn't create HiFi JWT: App Secret was blank!")
            return
        }
        
        let signers = JWTSigners()
        signers.use(.hs256(key: self.dataModel.appSecret))
        
        let payload = HiFiJWT(
            user_id: "iOS Test",
            app_id: self.dataModel.appID,
            space_name: self.dataModel.spaceName
        )
        
        let hifiJWT: String
        do {
            hifiJWT = try signers.sign(payload)
        } catch {
            HiFiLogger.error("Couldn't create HiFi JWT:\n\(error)")
            return
        }
        
        self.dataModel.communicator = HiFiCommunicator(initialHiFiAudioAPIData: self.dataModel.audioAPIData)
        
        print("Connecting to HiFi Audio API server...")
        
        self.dataModel.communicator!.connectToHiFiAudioAPIServer(hifiAuthJWT: hifiJWT, hostURL: self.dataModel.hostURL).then { response in
            print("Successfully connected! Response:\n\(response)")
            
            if (response.success) {
                myHashedVisitID = response.responseData!.visit_id_hash
                
                self.dataModel.communicator?.addUserDataSubscription(newSubscription: UserDataSubscription(providedUserID: nil, components: [.VolumeDecibels, .Position, .OrientationEuler], callback: { allReceivedData in
                    DispatchQueue.main.async {
                        for receivedData in allReceivedData {
                            if (receivedData.hashedVisitID == myHashedVisitID) {
                                if (receivedData.volumeDecibels != nil) {
                                    myAvatarVolumeDecibels = receivedData.volumeDecibels!
                                    self.refreshMyAvatarAnnotation()
                                }
                            } else if (receivedData.hashedVisitID != nil) {
                                var annotationToModify: MKAnnotation? = nil
                                var hiFiAnnotationToModify: HiFiUserAnnotation? = nil
                                var annotationCoordinates: CLLocationCoordinate2D = unionSquareCenter.coordinate
                                
                                for annotation in self.mainMapView.annotations {
                                    let hiFiAnnotation = annotation as! HiFiUserAnnotation
                                    if (hiFiAnnotation.hashedVisitID == receivedData.hashedVisitID) {
                                        annotationToModify = annotation
                                        hiFiAnnotationToModify = hiFiAnnotation
                                    }
                                }
                                
                                if (self.dataModel.otherAvatarData[receivedData.hashedVisitID!] == nil) {
                                    self.dataModel.otherAvatarData[receivedData.hashedVisitID!] = AvatarData(position: Point3D(), orientationEuler: OrientationEuler3D(), volumeDecibels: -96.0)
                                }
                                
                                if (receivedData.volumeDecibels != nil) {
                                    self.dataModel.otherAvatarData[receivedData.hashedVisitID!]!.volumeDecibels = receivedData.volumeDecibels!
                                    if (hiFiAnnotationToModify != nil) {
                                        hiFiAnnotationToModify!.audioLevelDecibels = CGFloat(self.dataModel.otherAvatarData[receivedData.hashedVisitID!]!.volumeDecibels)
                                    }
                                }
                                if (receivedData.position != nil) {
                                    self.dataModel.otherAvatarData[receivedData.hashedVisitID!]!.position = receivedData.position!
                                }
                                if (receivedData.orientationEuler != nil) {
                                    self.dataModel.otherAvatarData[receivedData.hashedVisitID!]!.orientationEuler = receivedData.orientationEuler!
                                    if (hiFiAnnotationToModify != nil) {
                                        hiFiAnnotationToModify!.orientationRadians = CGFloat(self.dataModel.otherAvatarData[receivedData.hashedVisitID!]!.orientationEuler.yawDegrees * -1 * Double.pi / 180)
                                        
                                        // Other users' relative Lat/Long coordinates are packed into pitchDegrees and rollDegrees :)
                                        annotationCoordinates.latitude = unionSquareCenter.coordinate.latitude - self.dataModel.otherAvatarData[receivedData.hashedVisitID!]!.orientationEuler.pitchDegrees
                                        annotationCoordinates.longitude = unionSquareCenter.coordinate.longitude - self.dataModel.otherAvatarData[receivedData.hashedVisitID!]!.orientationEuler.rollDegrees
                                        hiFiAnnotationToModify!.coordinate = annotationCoordinates
                                    }
                                }
                                
                                if (hiFiAnnotationToModify != nil) {
                                    self.mainMapView.view(for: annotationToModify!)?.setNeedsDisplay()
                                } else {
                                    let annotation = HiFiUserAnnotation(
                                        coordinate: annotationCoordinates,
                                        title: receivedData.hashedVisitID!,
                                        audioLevelDecibels: CGFloat(receivedData.volumeDecibels ?? -96.0),
                                        orientationRadians: CGFloat((receivedData.orientationEuler?.yawDegrees ?? 0.0) * Double.pi / 180),
                                        hashedVisitID: receivedData.hashedVisitID!
                                    )
                                    self.mainMapView.addAnnotation(annotation)
                                }
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
        self.dataModel.communicator!.disconnectFromHiFiAudioAPIServer().then { disconnectedResult in
            print("Disconnect status: \(disconnectedResult)")
        }.catch { error in
            print("Failed to disconnect! Error:\n\(error)")
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let annotationView = HiFiUsersAnnotationView(annotation: annotation, reuseIdentifier: "HiFiUser")
        annotationView.canShowCallout = true
        return annotationView
    }
    
    func refreshMyAvatarAnnotation() {
        DispatchQueue.main.async {
            for annotation in self.mainMapView.annotations {
                let hiFiAnnotation = annotation as! HiFiUserAnnotation
                if (hiFiAnnotation.hashedVisitID == myHashedVisitID || hiFiAnnotation.hashedVisitID == "") {
                    hiFiAnnotation.coordinate = self.mainMapView.camera.centerCoordinate
                    hiFiAnnotation.audioLevelDecibels = CGFloat(myAvatarVolumeDecibels)
                    hiFiAnnotation.orientationRadians = myAvatarOrientationRadians
                    hiFiAnnotation.hashedVisitID = myHashedVisitID ?? ""
                    self.mainMapView.view(for: annotation)?.setNeedsDisplay()
                    return
                }
            }
            
            let annotation = HiFiUserAnnotation(
                coordinate: self.mainMapView.camera.centerCoordinate,
                title: "You",
                audioLevelDecibels: CGFloat(myAvatarVolumeDecibels),
                orientationRadians: myAvatarOrientationRadians,
                hashedVisitID: myHashedVisitID ?? ""
            )
            self.mainMapView.addAnnotation(annotation)
        }
    }
    
    func initHeadphoneMotion() {
        if (self.headphoneMotionManager.isDeviceMotionAvailable) {
            print("Starting headphone motion updates...")
            self.headphoneMotionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (motion, error) in
                // If the user's phone IS in their pocket, we'll use the user's headphone motion
                // relative to the user's GPS heading to drive the user's avatar's orientation.
                // If the user's phone is out of their pocket, don't use the headphone motion.
                // Instead, we will use the absolute compass orientation to drive avatar orientation.
                if (self.emulatingProxSensorCovered || UIDevice.current.proximityState) {
                    let radiansDelta = ((motion?.attitude.yaw)! - (self.lastHeadphonesYawRadians ?? 0))
                    
                    var newRadians = Double(myAvatarOrientationRadians) - radiansDelta
                    newRadians = newRadians.truncatingRemainder(dividingBy: (2 * Double.pi))
                    if (newRadians < 0.0) {
                        newRadians += 2 * Double.pi
                    }
                    
                    myAvatarOrientationRadians = CGFloat(newRadians)
                    let degrees = newRadians * 180.0 / Double.pi
                    
                    self.refreshMyAvatarAnnotation()
                    
                    self.mainMapView.camera.heading = degrees
                    
                    self.dataModel.audioAPIData.orientationEuler!.yawDegrees = -1 * degrees
                    _ = self.dataModel.communicator!.updateUserDataAndTransmit(newUserData: self.dataModel.audioAPIData)
                    
                    self.lastHeadphonesYawRadians = (motion?.attitude.yaw)!
                }
            }
        }
    }
    
    func enableProximitySensor() {
        UIDevice.current.isProximityMonitoringEnabled = true
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        // If the user's phone is NOT in their pocket, use the compass' heading to drive the user's avatar's orientation.
        if (!self.emulatingProxSensorCovered && !UIDevice.current.proximityState) {
            let currentHeadingRadians = heading.magneticHeading * Double.pi / 180
            myAvatarOrientationRadians = CGFloat(currentHeadingRadians)
            self.mainMapView.camera.heading = heading.magneticHeading
            self.dataModel.audioAPIData.orientationEuler!.yawDegrees = -1 * heading.magneticHeading
            _ = self.dataModel.communicator!.updateUserDataAndTransmit(newUserData: self.dataModel.audioAPIData)
            self.refreshMyAvatarAnnotation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if (locations.last == nil) {
            return
        }
        
        if (locations.last!.horizontalAccuracy > 20) {
            return
        }
        
        if (self.startingRealWorldLocation == nil) {
            self.startingRealWorldLocation = locations.last
        }
        
        let movementFromStartingRealWorldLocation = CLLocationCoordinate2D(
            latitude: self.startingRealWorldLocation!.coordinate.latitude - locations.last!.coordinate.latitude,
            longitude: self.startingRealWorldLocation!.coordinate.longitude - locations.last!.coordinate.longitude
        )
        
        let dx = (EARTH_RADIUS_M * locations.last!.coordinate.longitude * .pi / 180 * cos(self.startingRealWorldLocation!.coordinate.latitude * .pi / 180)) - (EARTH_RADIUS_M * self.startingRealWorldLocation!.coordinate.longitude * .pi / 180 * cos(self.startingRealWorldLocation!.coordinate.latitude * .pi / 180))
        let dy = (EARTH_RADIUS_M * locations.last!.coordinate.latitude * .pi / 180) - (EARTH_RADIUS_M * self.startingRealWorldLocation!.coordinate.latitude * .pi / 180)
        
        // We multiply by a scale factor here to make the virtual audio environment smaller than the visual environment.
        // This is for user comfort. I noticed during testing that people sounded very far away even if they looked close on the map.
        // Without using the scale factor, the audio environment will sound more realistic.
        // We may not want to keep the scale factor.
        self.dataModel.audioAPIData.position!.x = dx * AUDIO_ENVIRONMENT_SCALE_FACTOR
        self.dataModel.audioAPIData.position!.z = -dy * AUDIO_ENVIRONMENT_SCALE_FACTOR
        
        // Our relative Lat/Long coordinates are packed into pitchDegrees and rollDegrees :)
        self.dataModel.audioAPIData.orientationEuler!.pitchDegrees = movementFromStartingRealWorldLocation.latitude
        self.dataModel.audioAPIData.orientationEuler!.rollDegrees = movementFromStartingRealWorldLocation.longitude
        
        let newCoordinate = CLLocationCoordinate2D(
            latitude: unionSquareCenter.coordinate.latitude - movementFromStartingRealWorldLocation.latitude,
            longitude: unionSquareCenter.coordinate.longitude - movementFromStartingRealWorldLocation.longitude
        )
        
        // If the phone is in the user's pocket, AND EITHER this is our first recorded location OR the GPS reports we've moved more than X meters,
        // use the GPS course to determine the avatar's orientation.
        if ((self.emulatingProxSensorCovered || UIDevice.current.proximityState) && (self.lastRecordedLocation == nil || abs(self.lastRecordedLocation!.distance(from: locations.last!)) > MIN_IRL_MOVEMENT_FOR_HEADING_UPDATE_METERS)) {
            let currentHeadingRadians = locations.last!.course * Double.pi / 180
            myAvatarOrientationRadians = CGFloat(currentHeadingRadians)
            self.mainMapView.camera.heading = locations.last!.course
            self.dataModel.audioAPIData.orientationEuler!.yawDegrees = -1 * locations.last!.course
        }
        
        _ = self.dataModel.communicator!.updateUserDataAndTransmit(newUserData: self.dataModel.audioAPIData)
        self.refreshMyAvatarAnnotation()
        
        let newCamera = self.mainMapView.camera.copy() as! MKMapCamera
        newCamera.centerCoordinate = newCoordinate
        self.mainMapView.setCamera(newCamera, animated: true)
        
        self.lastRecordedLocation = locations.last!
    }
    
    @IBAction func resetStartingRealWorldLocation(_ sender: Any) {
        self.startingRealWorldLocation = nil
        self.mainMapView.camera.centerCoordinate = unionSquareCenter.coordinate
        self.refreshMyAvatarAnnotation()
    }
    
    
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphone motion manager connected!")
        self.initHeadphoneMotion()
    }
    
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphone motion manager disconnected!")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error: Location manager failed with error:\n\(error)")
    }
    
    @objc func muteMicSwitchLabelTapped(_ sender: UITapGestureRecognizer) {
        if (self.dataModel.communicator == nil) {
            self.dataModel.isMuted = false
            self.muteMicSwitch.isOn = false
            return
        }
        
        self.muteMicSwitch.isOn = !self.dataModel.isMuted
        self.dataModel.communicator!.setInputAudioMuted(isMuted: muteMicSwitch.isOn)
        self.dataModel.isMuted = self.muteMicSwitch.isOn
    }
    
    @objc func proxSensorSwitchLabelTapped(_ sender: UITapGestureRecognizer) {
        self.proxSensorSwitch.isOn = !self.emulatingProxSensorCovered
    }
    
    func setupLabelTaps() {
        let muteMicSwitchLabelTap = UITapGestureRecognizer(target: self, action: #selector(self.muteMicSwitchLabelTapped(_:)))
        self.muteMicSwitchLabel.isUserInteractionEnabled = true
        self.muteMicSwitchLabel.addGestureRecognizer(muteMicSwitchLabelTap)
        
        let proxSensorSwitchLabelTap = UITapGestureRecognizer(target: self, action: #selector(self.proxSensorSwitchLabelTapped(_:)))
        self.proxSensorSwitchLabel.isUserInteractionEnabled = true
        self.proxSensorSwitchLabel.addGestureRecognizer(proxSensorSwitchLabelTap)
    }
    
    @objc func onImageViewRotation(_ gestureRecognizer: UIRotationGestureRecognizer) {
        guard gestureRecognizer.view != nil else { return }
        
        if (gestureRecognizer.state == .began) {
            self.startingRotationGestureYawRadians = gestureRecognizer.rotation
        } else if (gestureRecognizer.state == .changed) {
            myAvatarOrientationRadians -= CGFloat(gestureRecognizer.rotation - (self.startingRotationGestureYawRadians ?? 0.0))
            self.startingRotationGestureYawRadians = gestureRecognizer.rotation
            
            if (self.dataModel.communicator != nil) {
                self.dataModel.audioAPIData.orientationEuler!.yawDegrees = -1 * Double(myAvatarOrientationRadians) * 180.0 / Double.pi
                _ = self.dataModel.communicator!.updateUserDataAndTransmit(newUserData: self.dataModel.audioAPIData)
            }
        }
    }
    
    func setupMapPinchHandler() {
        let recognizer = UIPinchGestureRecognizer(target: self, action:#selector(self.onMapViewPinch(recognizer:)))
        self.mainMapView.addGestureRecognizer(recognizer)
    }
    
    @objc func onMapViewPinch(recognizer: UIPinchGestureRecognizer) {
        if (recognizer.state == .began) {
            originalDistance = mainMapView.camera.centerCoordinateDistance;
        }
        
        // Max/min zoomscale is handled by `mainMapView.setCameraZoomRange()`.
        mainMapView.camera.centerCoordinateDistance = originalDistance! / Double(recognizer.scale)
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
    
    
    @IBAction func proxSensorSwitchValueChanged(_ sender: Any) {
        self.emulatingProxSensorCovered = self.proxSensorSwitch.isOn
    }
}


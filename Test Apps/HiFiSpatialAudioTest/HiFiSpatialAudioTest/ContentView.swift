//
//  ContentView.swift
//  HiFiSpatialAudioTest
//
//  Created by zach on 2/25/21.
//

import SwiftUI
import HiFiSpatialAudio
import Promises
import JWTKit
import CoreLocation
import CoreMotion

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

struct defaultsKeys {
    static let hostURL = "hostURL"
    static let appID = "appID"
    static let appSecret = "appSecret"
    static let spaceName = "spaceName"
}

class SpatialAudioTestModel : NSObject, CLLocationManagerDelegate, CMHeadphoneMotionManagerDelegate, ObservableObject {
    @Published var hostURL: String = ""
    @Published var appID: String = ""
    @Published var appSecret: String = ""
    @Published var spaceName: String = ""
    
    @Published var spatialAudioTestIsConnected: Bool = false
    @Published var spatialAudioTestOperationPending: Bool = false
    
    @Published var myHashedVisitID: String? = nil
    
    @Published var serverYaw: Double = 0.0
    @Published var serverPosition = Point3D()
    @Published var serverInputVolume: Float = 0.0
    
    @Published var isMuted: Bool = false
    
    let defaults = UserDefaults.standard
    
    var communicator: HiFiCommunicator? = nil
    var audioAPIData: HiFiAudioAPIData
    
    var startingYawDegrees: Double? = nil
    
    let locationManager = CLLocationManager()
    let headphoneMotionManager = CMHeadphoneMotionManager()
    var usingHeadphoneMotion = false
    
    override init() {
        hostURL = defaults.string(forKey: defaultsKeys.hostURL) ?? "api.highfidelity.com"
        appID = defaults.string(forKey: defaultsKeys.appID) ?? ""
        appSecret = defaults.string(forKey: defaultsKeys.appSecret) ?? ""
        spaceName = defaults.string(forKey: defaultsKeys.spaceName) ?? "test"
        
        self.audioAPIData = HiFiAudioAPIData(position: Point3D(), orientationEuler: OrientationEuler3D())
        
        HiFiLogger.setHiFiLogLevel(newLogLevel: HiFiLogLevel.debug)
        
        super.init()
        
        locationManager.delegate = self
        headphoneMotionManager.delegate = self
    }
    
    func connect() {
        self.spatialAudioTestIsConnected = false
        self.spatialAudioTestOperationPending = true
        
        if (self.appSecret.count == 0) {
            HiFiLogger.error("Couldn't create HiFi JWT: App Secret was blank!")
            self.spatialAudioTestOperationPending = false
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
            self.spatialAudioTestOperationPending = false
            return
        }
        
        defaults.set(self.hostURL, forKey: defaultsKeys.hostURL)
        defaults.set(self.appID, forKey: defaultsKeys.appID)
        defaults.set(self.appSecret, forKey: defaultsKeys.appSecret)
        defaults.set(self.spaceName, forKey: defaultsKeys.spaceName)
        
        self.communicator = HiFiCommunicator(initialHiFiAudioAPIData: self.audioAPIData)
        
        print("Connecting to HiFi Audio API server...")
        
        self.communicator!.connectToHiFiAudioAPIServer(hifiAuthJWT: hifiJWT, signalingHostURL: self.hostURL).then { response in
            print("Successfully connected! Response:\n\(response)")
            
            if (response.success) {
                self.spatialAudioTestIsConnected = true
                self.spatialAudioTestOperationPending = false
                self.myHashedVisitID = response.responseData!.visit_id_hash
                
                self.communicator?.addUserDataSubscription(newSubscription: UserDataSubscription(providedUserID: nil, components: [.VolumeDecibels], callback: { allReceivedData in
                    for receivedData in allReceivedData {
                        if (receivedData.hashedVisitID == self.myHashedVisitID && receivedData.volumeDecibels != nil) {
                            DispatchQueue.main.async {
                                self.serverInputVolume = receivedData.volumeDecibels!
                            }
                        }
                    }
                }))
                
                self.startUsingDeviceHeading()
                self.startUsingHeadphoneMotion()
            } else {
                self.spatialAudioTestIsConnected = false
                self.spatialAudioTestOperationPending = false
                print("Failed to connect!")
            }
        }.catch { error in
            self.spatialAudioTestIsConnected = false
            self.spatialAudioTestOperationPending = false
            print("Failed to connect! Error:\n\(error)")
        }
    }
    
    func disconnect() {
        self.spatialAudioTestOperationPending = true
        
        self.communicator!.disconnectFromHiFiAudioAPIServer().then { disconnectedResult in
            print("Disconnect status: \(disconnectedResult)")
            self.spatialAudioTestIsConnected = false
            self.spatialAudioTestOperationPending = false
        }.catch { error in
            print("Failed to disconnect! Error:\n\(error)")
            self.spatialAudioTestIsConnected = false
            self.spatialAudioTestOperationPending = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        if (!self.usingHeadphoneMotion) {
            self.audioAPIData.orientationEuler!.yawDegrees = heading.magneticHeading
            
            if (self.startingYawDegrees == nil) {
                self.startingYawDegrees = self.audioAPIData.orientationEuler!.yawDegrees
            }
            
            self.audioAPIData.orientationEuler!.yawDegrees -= self.startingYawDegrees!
            
            self.updateServer()
        }
    }
    
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphone motion manager connected!")
        if (manager.isDeviceMotionAvailable) {
            print("Headphone motion is available!")
            self.startUsingHeadphoneMotion()
        } else {
            print("Headphone motion is not available.")
            self.startUsingDeviceHeading()
        }
    }
    
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphone motion manager disconnected!")
        self.startUsingDeviceHeading()
    }
    
    func startUsingDeviceHeading() {
        if (CLLocationManager.headingAvailable()) {
            print("Using device motion to drive avatar orientation.")
            self.usingHeadphoneMotion = false
            locationManager.headingFilter = kCLHeadingFilterNone
            locationManager.startUpdatingHeading()
        }
    }
    
    func startUsingHeadphoneMotion() {
        if (self.headphoneMotionManager.isDeviceMotionAvailable) {
            print("Headphone motion is available!")
            self.headphoneMotionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (motion, error) in
                if (!self.usingHeadphoneMotion) {
                    self.usingHeadphoneMotion = true
                    self.locationManager.stopUpdatingHeading()
                }
                let headphonePitchDegrees = (motion?.attitude.pitch)! * 180 / Double.pi
                self.audioAPIData.orientationEuler!.yawDegrees = headphonePitchDegrees
                
                if (self.startingYawDegrees == nil) {
                    self.startingYawDegrees = self.audioAPIData.orientationEuler!.yawDegrees
                }
                
                self.audioAPIData.orientationEuler!.yawDegrees -= self.startingYawDegrees!
                
                self.updateServer()
            }
        } else {
            print("Headphone motion is not available.")
            self.startUsingDeviceHeading()
        }
    }
    
    func updateServer() {
        if (self.communicator == nil || self.communicator!.getHiFiConnectionState() != .connected) {
            return
        }
        
        let updateStatus = self.communicator!.updateUserDataAndTransmit(newUserData: self.audioAPIData)
        if (updateStatus.success) {
            self.serverYaw = self.audioAPIData.orientationEuler!.yawDegrees
            self.serverPosition.x = self.audioAPIData.position!.x
            self.serverPosition.z = self.audioAPIData.position!.z
        }
    }
    
    func toggleMute() {
        if (self.communicator == nil || self.communicator!.getHiFiConnectionState() != .connected) {
            return
        }
        
        let wasMutedChanged = self.communicator!.setInputAudioMuted(isMuted: !self.isMuted)
        if (wasMutedChanged) {
            self.isMuted = !self.isMuted
        }
    }
}

struct ContentView: View {
    @ObservedObject var spatialAudioTestModel: SpatialAudioTestModel
    @State private var possibleHostURLs = ["api-staging.highfidelity.com", "api.highfidelity.com", "api-pro.highfidelity.com"]
    
    init() {
        spatialAudioTestModel = SpatialAudioTestModel()
    }
    
    var body: some View {
        Text("HiFi Spatial Audio API Test")
            .font(.title)
            .padding(.all)
        
        VStack {
            if spatialAudioTestModel.spatialAudioTestOperationPending {
                Button("Wait...") { }.padding(.all)
            } else if spatialAudioTestModel.spatialAudioTestIsConnected {
                Form {
                    Section(header: Text("CONTROLS")) {
                        Button("x += 0.25") {
                            spatialAudioTestModel.audioAPIData.position!.x += 0.25
                            spatialAudioTestModel.updateServer()
                        }
                        
                        Button("x -= 0.25") {
                            spatialAudioTestModel.audioAPIData.position!.x -= 0.25
                            spatialAudioTestModel.updateServer()
                        }
                        
                        Button("z += 0.25") {
                            spatialAudioTestModel.audioAPIData.position!.z += 0.25
                            spatialAudioTestModel.updateServer()
                        }
                        
                        Button("z -= 0.25") {
                            spatialAudioTestModel.audioAPIData.position!.z -= 0.25
                            spatialAudioTestModel.updateServer()
                        }
                        
                        Text("Position: (\(String(format: "%.2f", spatialAudioTestModel.serverPosition.x)), \(String(format: "%.2f", spatialAudioTestModel.serverPosition.z)))")
                        
                        Text("Yaw: \(String(format: "%.2f", spatialAudioTestModel.serverYaw))")
                        
                        GeometryReader { metrics in
                            VStack(alignment: .leading) {
                                Text("Input Volume: \(String(format: "%.2f", self.spatialAudioTestModel.serverInputVolume))")
                                
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: HiFiUtilities.linearScale(factor: CGFloat(self.spatialAudioTestModel.serverInputVolume), minInput: -96, maxInput: 0, minOutput: 0, maxOutput: metrics.size.width), height: 2)
                            }
                        }
                        
                        Button("Toggle Input Mute (Currently \(self.spatialAudioTestModel.isMuted ? "Muted" : "Unmuted"))") {
                            spatialAudioTestModel.toggleMute()
                        }
                        
                        Button("Disconnect") {
                            spatialAudioTestModel.disconnect()
                        }
                    }
                }
            } else {
                Form {
                    Section(header: Text("CONNECTION INFORMATION")) {
                        Picker("Host URL", selection: $spatialAudioTestModel.hostURL) {
                            ForEach(possibleHostURLs, id: \.self) {
                                Text($0)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: self.spatialAudioTestModel.hostURL, perform: { value in
                            print("User set Host URL to `\(self.spatialAudioTestModel.hostURL)`")
                            self.spatialAudioTestModel.defaults.set(self.spatialAudioTestModel.hostURL, forKey: defaultsKeys.hostURL)
                        })
                        
                        HStack {
                            Text("App ID")
                            TextField(
                                "App ID",
                                text: $spatialAudioTestModel.appID,
                                onEditingChanged: { isEditing in
                                    if (!isEditing) {
                                        print("User set App ID to `\(self.spatialAudioTestModel.appID)`")
                                        self.spatialAudioTestModel.defaults.set(self.spatialAudioTestModel.appID, forKey: defaultsKeys.appID)
                                    }
                                }
                            )
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .border(Color(UIColor.systemRed), width: spatialAudioTestModel.appID.count == 0 ? 1 : 0)
                        }
                        
                        HStack {
                            Text("App Secret")
                            TextField(
                                "App Secret",
                                text: $spatialAudioTestModel.appSecret,
                                onEditingChanged: { isEditing in
                                    if (!isEditing) {
                                        print("User set App Secret to `\(self.spatialAudioTestModel.appSecret)`")
                                        self.spatialAudioTestModel.defaults.set(self.spatialAudioTestModel.appSecret, forKey: defaultsKeys.appSecret)
                                    }
                                }
                            )
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .border(Color(UIColor.systemRed), width: spatialAudioTestModel.appSecret.count == 0 ? 1 : 0)
                        }
                        
                        HStack {
                            Text("Space Name")
                            TextField(
                                "Space Name",
                                text: $spatialAudioTestModel.spaceName,
                                onEditingChanged: { isEditing in
                                    if (!isEditing) {
                                        print("User set Space Name to `\(self.spatialAudioTestModel.spaceName)`")
                                        self.spatialAudioTestModel.defaults.set(self.spatialAudioTestModel.spaceName, forKey: defaultsKeys.spaceName)
                                    }
                                }
                            )
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .border(Color(UIColor.systemRed), width: spatialAudioTestModel.spaceName.count == 0 ? 1 : 0)
                        }
                        
                        Button("Connect") {
                            spatialAudioTestModel.connect()
                        }
                    }
                }
                
                Text("Recommendation: Use the same credentials here and with Space Inspector so you can interact with this app from a browser.").padding(.all)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

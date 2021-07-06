//
//  HiFiMixerSession.swift
//  
//
//  Created by zach on 3/4/21.
//

import Foundation
import WebRTC
import Promises
import Gzip

let DEFAULT_TURN_SERVER_URI = "turn:turn.highfidelity.com:3478"
let LEGACY_TURN_USERNAME = "clouduser"
let LEGACY_TURN_CREDENTIAL = "chariot-travesty-hook"

/// Contains various pieces of information about the High Fidelity Audio API Server to which the client is connected.
public struct HiFiMixerInfo {
    var connected: Bool = false
    var buildNumber: String?
    var buildType: String?
    var buildVersion: String?
    var visitIDHash: String?
}

/// Contains additional information about the High Fidelity Audio API Server when the client calls `HiFiCommunicator.connectToHiFiAudioAPIServer`.
public struct AudionetInitResponseData : Codable {
    public let build_number: String
    public let build_type: String
    public let build_version: String
    public let visit_id_hash: String
}

/// Contains information about the High Fidelity Audio API Server when the client calls `HiFiCommunicator.connectToHiFiAudioAPIServer`.
public struct AudionetInitResponse : Encodable {
    public var success: Bool
    public var error: String?
    public var responseData: AudionetInitResponseData?
    
    public var dictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] }
    }
}

/// Used internally when formatting user data for the High Fidelity Audio API Server.
public struct HiFiAudioAPIDataForMixer : Codable {
    public var x: Double? = nil
    public var y: Double? = nil
    public var z: Double? = nil
    
    public var W: Double? = nil
    public var X: Double? = nil
    public var Y: Double? = nil
    public var Z: Double? = nil
    
    public var T: Float? = nil
    public var g: Float? = nil
    public var a: Float? = nil
    public var r: Float? = nil
    
    public var stringified: String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Used for viewing the status of a `HiFiCommunicator.updateUserDataAndTransmit` call. (Other calls also return this data structure.)
public struct TransmitHiFiAudioAPIDataStatus {
    public var success: Bool
    public var error: String?
    public var transmitted: HiFiAudioAPIDataForMixer?
}

/// Used internally for decoding data sent from the mixer.
internal struct RAVISessionPeerData : Decodable {
    let J: String?
    // `e` is the `hashedVisitID`, which is a hashed version of the random UUID that a connecting client
    // sends as the `session` key inside the argument to the `audionet.init` command.
    // It is used to identify a given client across a cloud of mixers.
    let e: String?
    
    // Point3D position
    let x: Double?
    let y: Double?
    let z: Double?
    
    // OrientationQuat3D orientation
    var W: Double?
    var X: Double?
    var Y: Double?
    var Z: Double?
    
    // `ReceivedHiFiAudioAPIData.volumeDecibels`
    let v: Float?
    // `ReceivedHiFiAudioAPIData.isStereo`
    let s: Bool?
}

/// Used internally for decoding data sent from the mixer.
internal struct RAVISessionBinaryData : Decodable {
    let deleted_visit_ids: [String]?
    let peers: [String : RAVISessionPeerData]?
}

/**
    Instantiations of this class contain data about a connection between a client and a mixer.
    Client library users shouldn't have to care at all about the variables and methods contained in this class.
*/
internal class HiFiMixerSession {
    /**
        The RAVI Signaling Connection associated with this Mixer Session.
     */
    private var _raviSignalingConnection: RaviSignalingConnection
    /**
        The RAVI Session associated with this Mixer Session.
     */
    private var _raviSession: RaviSession
    
    /**
        Stores the current HiFi Connection State, which is an abstraction separate from the RAVI Session State and RAVI Signaling State.
     */
    public var currentHiFiConnectionState: HiFiConnectionStates
    
    /**
        When we receive peer data from the server, it's in a format like this:

        ```
        {
            318: {c: "#5df1f5", d: "Howard", e: "873c4d43-ccd9-4ce4-9ac7-d5fade4def929a", i: "{f0ce22bb-8b67-4044-a8c5-65aefbce4060}", o: 0, …}
            341: {e: "9c5af44b-7e3f-8f65-5421-374b43bebc4a", i: "{be38a256-850a-4c8d-bddd-cfe80aaddfe9}", o: 0, p: true, v: -120, …}
        }
        ```

        The peer data does not always contain all possible key/value pairs associated with each key in this Object. In fact, most of the time, it contains
        only a fraction of the data. For example, we might receive `{ 341: {v: -40} }` from the server.
        When the HiFi Audio Library user sets up a User Data Subscription, they can optionally associate the Subscription with a "Provided User ID".
        Since the server doesn't always send the "Provided User ID" in these peer updates, we have to keep track of the (presumably stable) key in `jsonData.peers`
        associated with that "Provided User ID" in order to forward that "Provided User ID" to the Subscription handler and thus to the Library user.
        Thus, the Library user should never have to care about the `_mixerPeerKeyToProvidedUserIDDict`.
        Similarly, we keep a `_mixerPeerKeyToHashedVisitIDDict`.
     */
    private var _mixerPeerKeyToCachedDataDict: [String : ReceivedHiFiAudioAPIData]
    
    /**
        We will track whether or not the input stream is stereo, so that
        we can advise the server to mix it appropriately
     */
    private var _inputAudioMediaStreamIsStereo: Bool
    
    /**
        See `HiFiUserDataStreamingScopes`.
     */
    public var userDataStreamingScope: HiFiUserDataStreamingScopes
    
    /**
        The WebRTC Address to which we want to connect as a part of this Session. This WebRTC Address is obtained from the Mixer Discovery Address during
        the `HiFiCommunicator.connectToHiFiAudioAPIServer()` call.
     */
    public var webRTCAddress: String?
    /**
        This function is called when Peer data is returned from the Server.
     */
    public var onUserDataUpdated: (([ReceivedHiFiAudioAPIData]) -> Void)
    /**
        This function is called when a Peer disconnects from the Server.
     */
    public var onUsersDisconnected: (([ReceivedHiFiAudioAPIData]) -> Void)
    /**
        This function is called when the "connection state" changes.
        Right now, this is called when the the RAVI session state changes to
        `RaviSessionStates.CONNECTED`, `RaviSessionStates.DISCONNECTED`, and `RaviSessionStates.FAILED`.
     */
    public var onConnectionStateChanged: ((HiFiConnectionStates) -> Void)?
    
    /**
        Contains information about the mixer to which we are currently connected.
     */
    public var mixerInfo: HiFiMixerInfo
    
    /**
        - Parameter userDataStreamingScope: See `HiFiUserDataStreamingScopes`.
        - Parameter onUserDataUpdated: The function to call when the server sends user data to the client. Irrelevant if `userDataStreamingScope` is `HiFiUserDataStreamingScopes.None`.
        - Parameter onUsersDisconnected: The function to call when the server sends user data about peers who just disconnected to the client.
     */
    init(
        userDataStreamingScope: HiFiUserDataStreamingScopes?,
        onUserDataUpdated: @escaping (([ReceivedHiFiAudioAPIData]) -> Void),
        onUsersDisconnected: @escaping (([ReceivedHiFiAudioAPIData]) -> Void),
        onConnectionStateChanged: ((HiFiConnectionStates) -> Void)?
    ) {
        self.webRTCAddress = nil
        self.currentHiFiConnectionState = .disconnected
        self.userDataStreamingScope = userDataStreamingScope ?? .all
        self.onUserDataUpdated = onUserDataUpdated
        self.onUsersDisconnected = onUsersDisconnected
        self._mixerPeerKeyToCachedDataDict = [:]
        
        //RaviUtils.setDebug(false)
        
        self._raviSignalingConnection = RaviSignalingConnection()
        
        self._raviSession = RaviSession()
        
        self.onConnectionStateChanged = onConnectionStateChanged ?? nil
        
        self.mixerInfo = HiFiMixerInfo(connected: false, buildNumber: nil, buildType: nil, buildVersion: nil, visitIDHash: nil)
        self._inputAudioMediaStreamIsStereo = false
        
        self._raviSignalingConnection.addSignalingStateChangeHandler(changeHandlerID: "MixerSessionSignalingStateChanged", changeHandler: self.onRAVISignalingStateChanged)
        self._raviSession.addRAVISessionStateChangeHandler(changeHandlerID: "MixerSessionSessionStateChanged", changeHandler: self.onRAVISessionStateChanged)
    }
    
    /**
        Sends the command `audionet.init` to the mixer.
     */
    public func promiseToRunAudioInit() -> Promise<AudionetInitResponse> {
        return Promise<AudionetInitResponse> { fulfill, reject in
            let commandController = self._raviSession.getCommandController()
            // TODO: Re-implement this init timeout later.
            //            let INIT_TIMEOUT_MS = 5000;
            //            let initTimeout = setTimeout(() => {
            //                this.disconnect();
            //                return Promise.reject({
            //                    success: false,
            //                    error: `Couldn't connect to mixer: Call to \`init\` timed out!`
            //                });
            //            }, INIT_TIMEOUT_MS);
            
            let audionetInitParams = [
                "primary": true,
                "visit_id": self._raviSession.getUUID(), // The mixer will hash this randomly-generated UUID, then disseminate it to all clients via `peerData.e`.
                "session": self._raviSession.getUUID(), // Still required for old mixers. Will eventually go away.
                "streaming_scope": self.userDataStreamingScope.rawValue,
                "is_input_stream_stereo": self._inputAudioMediaStreamIsStereo
            ] as [String : Any]
            let initCommandHandler = RaviCommandHandler(commandName: "audionet.init") { response in
                do {
                    if (response == nil) {
                        return
                    }
                    let decoder = JSONDecoder()
                    let responseData = try decoder.decode(AudionetInitResponseData.self, from: response!.data(using: .utf8)!)
                    self.mixerInfo.connected = true
                    self.mixerInfo.buildNumber = responseData.build_number
                    self.mixerInfo.buildType = responseData.build_type
                    self.mixerInfo.buildVersion = responseData.build_version
                    self.mixerInfo.visitIDHash = responseData.visit_id_hash
                    
                    let response = AudionetInitResponse(success: true, error: nil, responseData: responseData)
                    
                    fulfill(response)
                } catch {
                    let response = AudionetInitResponse(success: false, error: "Couldn't parse init response!", responseData: nil)
                    reject(NSError(domain: "", code: 1, userInfo: response.dictionary))
                }
            }
            let initCommand = RaviCommand(commandName: "audionet.init", params: audionetInitParams, commandHandler: initCommandHandler)
            _ = commandController.sendCommand(raviCommand: initCommand)
        }
    }
    
    /**
        `mixer` and `peer` data is sent from the Mixer to all connected clients when necessary.
        - Parameter data: The `gzipped` data from the Mixer.
     */
    public func handleRAVISessionBinaryData(data: Data?) {
        if (data == nil) {
            return
        }
        
        let decompressedData: Data
        if data!.isGzipped {
            decompressedData = try! data!.gunzipped()
        } else {
            decompressedData = data!
        }
        
        let decoder = JSONDecoder()
        
        var jsonData: RAVISessionBinaryData?
        do {
            jsonData = try decoder.decode(RAVISessionBinaryData.self, from: decompressedData)
        } catch {
            return
        }
        
        if (jsonData?.deleted_visit_ids != nil) {
            var allDeletedUserData: [ReceivedHiFiAudioAPIData] = [ReceivedHiFiAudioAPIData]()
            
            let deletedVisitIDs = jsonData?.deleted_visit_ids
            for deletedVisitID in deletedVisitIDs! {
                for (mixerPeerKey, cachedData) in self._mixerPeerKeyToCachedDataDict {
                    if (self._mixerPeerKeyToCachedDataDict[mixerPeerKey]?.hashedVisitID == deletedVisitID) {
                        allDeletedUserData.append(cachedData)
                        self._mixerPeerKeyToCachedDataDict.removeValue(forKey: mixerPeerKey)
                        break
                    }
                }
            }
            
            if (allDeletedUserData.count > 0) {
                self.onUsersDisconnected(allDeletedUserData)
            }
        }
        
        if (jsonData?.peers != nil) {
            var allNewUserData: Array<ReceivedHiFiAudioAPIData> = []
            
            for (peerKey, peerDataFromMixer) in jsonData!.peers! {
                var userDataCache: ReceivedHiFiAudioAPIData?
                
                if (self._mixerPeerKeyToCachedDataDict[peerKey] == nil) {
                    self._mixerPeerKeyToCachedDataDict[peerKey] = ReceivedHiFiAudioAPIData(providedUserID: nil, hashedVisitID: nil, volumeDecibels: nil, position: nil, orientationQuat: nil, isStereo: nil)
                }
                
                userDataCache = self._mixerPeerKeyToCachedDataDict[peerKey]
                
                let newUserData = ReceivedHiFiAudioAPIData(providedUserID: nil, hashedVisitID: nil, volumeDecibels: nil, position: nil, orientationQuat: nil, isStereo: nil)
                
                if (userDataCache!.providedUserID != nil) {
                    newUserData.providedUserID = userDataCache!.providedUserID
                } else if (peerDataFromMixer.J != nil) {
                    userDataCache!.providedUserID = peerDataFromMixer.J
                    newUserData.providedUserID = peerDataFromMixer.J
                }
                
                if (userDataCache!.hashedVisitID != nil) {
                    newUserData.hashedVisitID = userDataCache!.hashedVisitID
                } else if (peerDataFromMixer.e != nil) {
                    userDataCache!.hashedVisitID = peerDataFromMixer.e
                    newUserData.hashedVisitID = peerDataFromMixer.e
                }
                
                var serverSentNewUserData = false
                
                var serverSentNewPosition = false
                // `ReceivedHiFiAudioAPIData.position.x`
                if (peerDataFromMixer.x != nil) {
                    if (userDataCache!.position == nil) {
                        userDataCache!.position = Point3D()
                    }
                    // Mixer sends position data in millimeters
                    userDataCache!.position!.x = peerDataFromMixer.x! / 1000
                    serverSentNewPosition = true
                }
                // `ReceivedHiFiAudioAPIData.position.y`
                if (peerDataFromMixer.y != nil) {
                    if (userDataCache!.position == nil) {
                        userDataCache!.position = Point3D()
                    }
                    // Mixer sends position data in millimeters
                    userDataCache!.position!.y = peerDataFromMixer.y! / 1000
                    serverSentNewPosition = true
                }
                // `ReceivedHiFiAudioAPIData.position.z`
                if (peerDataFromMixer.z != nil) {
                    if (userDataCache!.position == nil) {
                        userDataCache!.position = Point3D()
                    }
                    // Mixer sends position data in millimeters
                    userDataCache!.position!.z = peerDataFromMixer.z! / 1000
                    serverSentNewPosition = true
                }
                if (serverSentNewPosition == true) {
                    newUserData.position = HiFiAxisConfiguration.translatePoint3DFromMixerSpace(axisConfiguration: ourHiFiAxisConfiguration, mixerPoint3D: userDataCache!.position!)
                    serverSentNewUserData = true
                }
                
                var serverSentNewOrientation = false
                if (peerDataFromMixer.W != nil) {
                    if (userDataCache!.orientationQuat == nil) {
                        userDataCache!.orientationQuat = OrientationQuat3D()
                    }
                    userDataCache!.orientationQuat!.w = peerDataFromMixer.W! / 1000
                    serverSentNewOrientation = true
                }
                if (peerDataFromMixer.X != nil) {
                    if (userDataCache!.orientationQuat == nil) {
                        userDataCache!.orientationQuat = OrientationQuat3D()
                    }
                    userDataCache!.orientationQuat!.x = peerDataFromMixer.X! / 1000
                    serverSentNewOrientation = true
                }
                if (peerDataFromMixer.Y != nil) {
                    if (userDataCache!.orientationQuat == nil) {
                        userDataCache!.orientationQuat = OrientationQuat3D()
                    }
                    userDataCache!.orientationQuat!.y = peerDataFromMixer.Y! / 1000
                    serverSentNewOrientation = true
                }
                if (peerDataFromMixer.Z != nil) {
                    if (userDataCache!.orientationQuat == nil) {
                        userDataCache!.orientationQuat = OrientationQuat3D()
                    }
                    userDataCache!.orientationQuat!.z = peerDataFromMixer.Z! / 1000
                    serverSentNewOrientation = true
                }
                if (serverSentNewOrientation == true) {
                    newUserData.orientationQuat = HiFiAxisConfiguration.translateOrientationQuat3DFromMixerSpace(axisConfiguration: ourHiFiAxisConfiguration, mixerOrientationQuat3D: userDataCache!.orientationQuat!)
                    serverSentNewUserData = true
                }
                
                // `ReceivedHiFiAudioAPIData.volumeDecibels`
                if (peerDataFromMixer.v != nil) {
                    userDataCache!.volumeDecibels = peerDataFromMixer.v
                    newUserData.volumeDecibels = peerDataFromMixer.v
                    serverSentNewUserData = true
                }
                
                // `ReceivedHiFiAudioAPIData.isStereo`
                if (peerDataFromMixer.s != nil) {
                    userDataCache!.isStereo = peerDataFromMixer.s
                    newUserData.isStereo = peerDataFromMixer.s
                    serverSentNewUserData = true
                }
                
                if (serverSentNewUserData) {
                    allNewUserData.append(newUserData)
                }
            }
            
            if (allNewUserData.count > 0) {
                self.onUserDataUpdated(allNewUserData)
            }
        }
    }
    
    /**
        Connect to the Mixer given some parameters.

        - Returns: A Promise that resolves upon connection success, and rejects upon connection failure.
     */
    public func connect(webRTCSessionParams: WebRTCSessionParams?, customSTUNAndTURNConfig: CustomSTUNAndTURNConfig?) -> Promise<AudionetInitResponse> {
        return Promise<AudionetInitResponse> { fulfill, reject in
            if (self.webRTCAddress == nil) {
                _ = self.disconnect()
                let response = AudionetInitResponse(success: false, error: "Couldn't connect: `this.webRTCAddress` is `nil`!", responseData: nil)
                return reject(NSError(domain: "", code: 1, userInfo: response.dictionary))
            }
            
            self.currentHiFiConnectionState = .disconnected
            
            self._raviSignalingConnection.open(url: self.webRTCAddress!).then { newSignalingState -> Promise<RaviSessionStates> in
                HiFiLogger.log("HiFiMixerSession: RAVI Signaling Connection successfully opened! New signaling state: \(newSignalingState). Opening RAVI session...")
                return self._raviSession.open(signalingConnection: self._raviSignalingConnection, params: webRTCSessionParams, customSTUNAndTURN: customSTUNAndTURNConfig)
            }.catch { error in
                HiFiLogger.error("HiFiMixerSession: RAVI Signaling Connection did not successfully open! Error:\n\(error)")
                _ = self.disconnect()
                return reject(error)
            }.then { newRaviSessionState -> Promise<AudionetInitResponse> in
                HiFiLogger.log("HiFiMixerSession: RAVI Session successfully opened! New RAVI Session state: \(newRaviSessionState) Sending `audionet.init`...")
                return self.promiseToRunAudioInit()
            }.catch { error in
                HiFiLogger.error("HiFiMixerSession: RAVI Session did not successfully open! Error:\n\(error)")
                _ = self.disconnect()
                return reject(error)
            }.then { audionetInitResponse in
                HiFiLogger.log("HiFiMixerSession: Sending `audionet.init` resulted in success!")
                let binaryDataHandler = RaviBinaryDataHandler(commandName: "handleRAVISessionBinaryData", binaryHandlerFunction: self.handleRAVISessionBinaryData, onlyFireOnce: false)
                self._raviSession.getCommandController().addBinaryDataHandler(commandName: "_BINARY", binaryDataHandler: binaryDataHandler)
                fulfill(audionetInitResponse)
            }.catch { error in
                HiFiLogger.error("HiFiMixerSession: Sending `audionet.init` resulted in an error! Error:\n\(error)")
                _ = self.disconnect()
                return reject(error)
            }
        }
    }
    
    /**
        Disconnects from the Mixer. Closes the RAVI Signaling Connection and the RAVI Session.

        - Returns: A Promise that _always_ Resolves with a "success" status string.
     */
    public func disconnect() -> Promise<Bool> {
        HiFiLogger.log("HiFiMixerSession: Disconnecting...")
        
        return Promise<Bool> { fulfill, reject in
            self._resetMixerInfo()
            
            self._raviSignalingConnection.close().then { _ -> Promise<RaviSessionStates> in
                return self._raviSession.close()
            }.then { newSessionState in
                return fulfill(true)
            }.catch { error in
                return reject(error)
            }
        }
    }
    
    /**
        Sets the input audio stream to "muted" by disabling all of the tracks on it
        (or to "unmuted" by enabling the tracks on it).

        - Returns: `true` if the stream was successfully muted/unmuted, `false` if it was not.
     */
    public func setInputAudioMuted(newMutedValue: Bool) -> Bool {
        let streamController = self._raviSession.getStreamController()
        let raviAudioStream = streamController._inputAudioTrack
        
        if (raviAudioStream != nil) {
            raviAudioStream?.isEnabled = !newMutedValue
            _ = HiFiLogger.log("HiFiMixerSession: Successfully set mute state to \(newMutedValue) on `_raviSession.streamController._inputAudioStream`")
            return true
        } else {
            HiFiLogger.warn("HiFiMixerSession: Couldn't set mute state: No `_inputAudioStream` on `_raviSession.streamController`.")
            return false
        }
    }
    
    /**
        Gets the output `MediaStream` from the Mixer. This is the final, mixed, spatialized audio stream containing
        all sources sent to the Mixer.

        - Returns: The mixed, spatialized `RTCMediaStream` from the Mixer. Returns `nil` if it's not possible to obtain that `RTCMediaStream`.
     */
    public func getOutputAudioMediaStream() -> RTCMediaStream? {
        let streamController = self._raviSession.getStreamController()
        return streamController.getOutputAudioStream()
    }
    
    /**
        Fires when the RAVI Signaling State chantges.
     */
    public func onRAVISignalingStateChanged(newSignalingState: SignalingStates) -> Void {
        _ = HiFiLogger.log("HiFiMixerSession: New RAVI signaling state: \(newSignalingState)")
        switch (newSignalingState) {
        case .unavailable:
            self.currentHiFiConnectionState = .unavailable
            if (self.onConnectionStateChanged != nil) {
                self.onConnectionStateChanged!(self.currentHiFiConnectionState)
            }
            _ = self.disconnect()
            break
        case .connecting:
            break
        case .open:
            break
        case .error:
            break
        case .closing:
            break
        case .closed:
            if (self._raviSession.state != .ready) {
                HiFiLogger.warn("HiFiMixerSession: RAVI Session was not in 'ready' state, and RAVI signaling state changed to '.closed'. Disconnecting...")
                _ = self.disconnect()
            }
            break
        }
    }
    
    /**
        Fires when the RAVI Session State changes.
    */
    public func onRAVISessionStateChanged(newSessionState: RaviSessionStates) -> Void {
        switch (newSessionState) {
        case .connected:
            self._mixerPeerKeyToCachedDataDict = [:]
            
            self.currentHiFiConnectionState = .connected
            
            if (self.onConnectionStateChanged != nil) {
                self.onConnectionStateChanged!(self.currentHiFiConnectionState)
            }
            break
        case .disconnected:
            if (self.currentHiFiConnectionState == .unavailable) {
                break
            }
            
            self.currentHiFiConnectionState = .disconnected
            
            if (self.onConnectionStateChanged != nil) {
                self.onConnectionStateChanged!(self.currentHiFiConnectionState)
            }
            break
        case .failed:
            if (self.currentHiFiConnectionState == .unavailable) {
                break
            }
            
            self.currentHiFiConnectionState = .failed
            
            if (self.onConnectionStateChanged != nil) {
                self.onConnectionStateChanged!(self.currentHiFiConnectionState)
            }
            break
        case .ready:
            break
        case .new:
            break
        case .connecting:
            break
        case .completed:
            break
        case .closed:
            break
        }
    }
    
    /**
        - Returns: A `TransmitHiFiAudioAPIDataStatus` object containing data about the data transfer.
     */
    func _transmitHiFiAudioAPIDataToServer(currentHiFiAudioAPIData: HiFiAudioAPIData, previousHiFiAudioAPIData: HiFiAudioAPIData?) -> TransmitHiFiAudioAPIDataStatus {
        if (!self.mixerInfo.connected) {
            return TransmitHiFiAudioAPIDataStatus(success: false, error: "Can't transmit data to mixer; not connected to mixer.", transmitted: nil)
        }
        
        var dataForMixer = HiFiAudioAPIDataForMixer()
        var dataModified: Bool = false
        
        if (currentHiFiAudioAPIData.position != nil) {
            var changedComponents = ["x": false, "y": false, "z": false, "changed": false]
            if (previousHiFiAudioAPIData != nil && previousHiFiAudioAPIData!.position != nil) {
                if (currentHiFiAudioAPIData.position!.x != previousHiFiAudioAPIData!.position!.x) {
                    changedComponents["x"] = true
                    changedComponents["changed"] = true
                }
                if (currentHiFiAudioAPIData.position!.y != previousHiFiAudioAPIData!.position!.y) {
                    changedComponents["y"] = true
                    changedComponents["changed"] = true
                }
                if (currentHiFiAudioAPIData.position!.z != previousHiFiAudioAPIData!.position!.z) {
                    changedComponents["z"] = true
                    changedComponents["changed"] = true
                }
            } else {
                changedComponents["x"] = true
                changedComponents["y"] = true
                changedComponents["z"] = true
                changedComponents["changed"] = true
            }
            
            if (changedComponents["changed"] == true) {
                let translatedPosition = HiFiAxisConfiguration.translatePoint3DToMixerSpace(axisConfiguration: ourHiFiAxisConfiguration, inputPoint3D: currentHiFiAudioAPIData.position!)
                
                if (changedComponents["x"] == true) {
                    dataForMixer.x = round(translatedPosition.x * 1000)
                    dataModified = true
                }
                if (changedComponents["y"] == true) {
                    dataForMixer.y = round(translatedPosition.y * 1000)
                    dataModified = true
                }
                if (changedComponents["z"] == true) {
                    dataForMixer.z = round(translatedPosition.z * 1000)
                    dataModified = true
                }
            }
        }
        
        if (currentHiFiAudioAPIData.orientationQuat != nil) {
            var changedComponents = ["w":false, "x": false, "y": false, "z": false, "changed": false]
            if (previousHiFiAudioAPIData != nil && previousHiFiAudioAPIData!.orientationQuat != nil) {
                if (currentHiFiAudioAPIData.orientationQuat!.w != previousHiFiAudioAPIData?.orientationQuat!.w) {
                    changedComponents["w"] = true
                    changedComponents["changed"] = true
                }
                if (currentHiFiAudioAPIData.orientationQuat!.x != previousHiFiAudioAPIData?.orientationQuat!.x) {
                    changedComponents["x"] = true
                    changedComponents["changed"] = true
                }
                if (currentHiFiAudioAPIData.orientationQuat!.y != previousHiFiAudioAPIData?.orientationQuat!.y) {
                    changedComponents["y"] = true
                    changedComponents["changed"] = true
                }
                if (currentHiFiAudioAPIData.orientationQuat!.z != previousHiFiAudioAPIData?.orientationQuat!.z) {
                    changedComponents["z"] = true
                    changedComponents["changed"] = true
                }
            } else {
                changedComponents["w"] = true
                changedComponents["x"] = true
                changedComponents["y"] = true
                changedComponents["z"] = true
                changedComponents["changed"] = true
            }
            
            if (changedComponents["changed"] == true) {
                let translatedOrientation = HiFiAxisConfiguration.translateOrientationQuat3DToMixerSpace(axisConfiguration: ourHiFiAxisConfiguration, inputOrientationQuat3D: currentHiFiAudioAPIData.orientationQuat!)
                
                if (changedComponents["w"] == true) {
                    dataForMixer.W = translatedOrientation.w * 1000
                    dataModified = true
                }
                if (changedComponents["x"] == true) {
                    dataForMixer.X = translatedOrientation.x * 1000
                    dataModified = true
                }
                if (changedComponents["y"] == true) {
                    dataForMixer.Y = translatedOrientation.y * 1000
                    dataModified = true
                }
                if (changedComponents["z"] == true) {
                    dataForMixer.Z = translatedOrientation.z * 1000
                    dataModified = true
                }
            }
        }
        
        if (currentHiFiAudioAPIData.volumeThreshold != nil) {
            dataForMixer.T = currentHiFiAudioAPIData.volumeThreshold!
            dataModified = true
        }
        
        if (currentHiFiAudioAPIData.hiFiGain != nil) {
            dataForMixer.g = currentHiFiAudioAPIData.hiFiGain!
            dataModified = true
        }
        
        if (currentHiFiAudioAPIData.userAttenuation != nil) {
            dataForMixer.a = currentHiFiAudioAPIData.userAttenuation!
            dataModified = true
        }
        
        if (currentHiFiAudioAPIData.userRolloff != nil) {
            dataForMixer.r = max(0, currentHiFiAudioAPIData.userRolloff!)
            dataModified = true
        }
        
        if (dataModified == false) {
            // We call this a "success" even though we didn't send anything to the mixer.
            return TransmitHiFiAudioAPIDataStatus(success: true, error: nil, transmitted: dataForMixer)
        } else {
            let stringifiedData = dataForMixer.stringified
            if (stringifiedData != nil) {
                _ = self._raviSession.getCommandController().sendInput(inputEvent: stringifiedData!)
                return TransmitHiFiAudioAPIDataStatus(success: true, error: nil, transmitted: dataForMixer)
            } else {
                return TransmitHiFiAudioAPIDataStatus(success: false, error: "Can't transmit data to mixer; data couldn't be stringified!", transmitted: nil)
            }
        }
    }
    
    /**
        Resets our "Mixer Info". Happens upon instantiation and when disconnecting from the mixer.
     */
    private func _resetMixerInfo() -> Void {
        self.mixerInfo = HiFiMixerInfo(connected: false, buildNumber: nil, buildType: nil, buildVersion: nil, visitIDHash: nil)
    }
}


//
//  RaviSession.swift
//  
//
//  Created by zach on 2/24/21.
//

import Foundation
import WebRTC
import Promises

public struct WebRTCSessionParams : Codable {
    public let audioMinJitterBufferDuration: Int?
    public let audioMaxJitterBufferDuration: Int?
}

public struct CustomSTUNAndTURNConfig : Codable {
    public let stunUrls: Array<String>
    public let turnUrls: Array<String>
    public let turnUsername: String
    public let turnCredential: String
}

public struct TURNConfig : Codable {
    public let urls: Array<String>
    public let username: String
    public let credential: String
}

public enum RaviSessionStates {
    case new, ready, connecting, connected, completed, disconnected, failed, closed
}

internal class RaviSession {
    public var raviSessionStateChangeHandlers: [String : (RaviSessionStates) -> Void]
    public var uuid: String
    public var commandController: RaviCommandController
    public var streamController: RaviStreamController
    public var state: RaviSessionStates
    public var raviWebRTCImplementation: RaviWebRTCImplementation?
    public var stunURLs: [String]?
    public var turnUrls: [String]?
    public var turnUsername: String?
    public var turnCredential: String?
    
    public init() {
        self.raviSessionStateChangeHandlers = [:]
        self.uuid = RaviUtils.createUUID()
        
        self.commandController = RaviCommandController()
        self.streamController = RaviStreamController(raviCommandController: self.commandController)
        
        self.state = RaviSessionStates.closed
        
        self.raviWebRTCImplementation = nil
        
        self.raviWebRTCImplementation = RaviWebRTCImplementation(raviSession: self)
    }
    
    public func getState() -> RaviSessionStates {
        return self.state
    }
    
    public func getUUID() -> String {
        return self.uuid
    }
    
    public func getCommandController() -> RaviCommandController {
        return self.commandController
    }
    
    public func getStreamController() -> RaviStreamController {
        return self.streamController
    }
    
    public func getAVAudioSession() -> AVAudioSession? {
        return self.raviWebRTCImplementation!.avAudioSession
    }
    
    public func addRAVISessionStateChangeHandler(changeHandlerID: String, changeHandler: @escaping (RaviSessionStates) -> Void) {
        if (self.raviSessionStateChangeHandlers[changeHandlerID] != nil) {
            HiFiLogger.warn("RaviSession: Warning: Replacing existing state change handler with ID '\(changeHandlerID)' ")
        } else {
            HiFiLogger.log("RaviSession: Adding state change handler with ID '\(changeHandlerID)'")
        }
        self.raviSessionStateChangeHandlers[changeHandlerID] = changeHandler
    }
    
    public func removeRAVISessionStateChangeHandler(changeHandlerID: String) {
        HiFiLogger.log("RaviSession: Removing state change handler with ID '\(changeHandlerID)'")
        self.raviSessionStateChangeHandlers.removeValue(forKey: changeHandlerID)
    }
    
    public func open(signalingConnection: RaviSignalingConnection, timeout: Int = 5000, params: WebRTCSessionParams?, customSTUNAndTURN: CustomSTUNAndTURNConfig?) -> Promise<RaviSessionStates> {
        self.raviWebRTCImplementation!._assignSignalingConnection(signalingConnection: signalingConnection)
        
        return Promise<RaviSessionStates> { fulfill, reject in
            if (signalingConnection.getState() == .closed) {
                HiFiLogger.log("RaviSession: The state of the signaling connection assoiciated with this RAVI Session is 'closed'. Rejecting promise...")
                reject(NSError(domain: "", code: 1, userInfo: ["state": RaviSessionStates.closed]))
                return
            }
            
            HiFiLogger.log("RaviSession: Opening RAVI Session...")
            
            // TODO: Implement RAVI Session timeout logic
            
            func openRAVISessionStateHandler(newState: RaviSessionStates) -> Void {
                HiFiLogger.log("RaviSession: RAVI Session State is now \(newState)...")
                
                if (newState == RaviSessionStates.ready) {
                    HiFiLogger.log("RaviSession: RAVI Session opened correctly and is now ready for use!")
                    self.removeRAVISessionStateChangeHandler(changeHandlerID: "openRAVISessionStateHandler")
                    fulfill(newState)
                } else if (newState == RaviSessionStates.failed || newState == RaviSessionStates.disconnected) {
                    HiFiLogger.log("RaviSession: RAVI Session failed to open!")
                    self.removeRAVISessionStateChangeHandler(changeHandlerID: "openRAVISessionStateHandler")
                    self.raviWebRTCImplementation!._closeWebRTCConnection()
                    reject(NSError(domain: "", code: 1, userInfo: ["state": newState]))
                } else if (newState == RaviSessionStates.closed) {
                    HiFiLogger.log("RaviSession: RAVI Session failed to open!")
                    self.removeRAVISessionStateChangeHandler(changeHandlerID: "openRAVISessionStateHandler")
                    reject(NSError(domain: "", code: 1, userInfo: ["state": newState]))
                }
            }
            self.addRAVISessionStateChangeHandler(changeHandlerID: "openRAVISessionStateHandler", changeHandler: openRAVISessionStateHandler)
            self.raviWebRTCImplementation!._openWebRTCConnection(params: params, customSTUNAndTURN: customSTUNAndTURN)
        }
    }
    
    public func close() -> Promise<RaviSessionStates> {
        self.streamController._stop()
        
        return Promise<RaviSessionStates> { fulfill, reject in
            HiFiLogger.log("RaviSession: Closing RAVI Session...")
            self.raviWebRTCImplementation!._closeWebRTCConnection()
            
            if (self.state == .closed) {
                HiFiLogger.log("RaviSession: RAVI Session already closed. Calling 'openRAVISessionStateHandler' if it exists and fulfilling promise...")
                for (id, handler) in self.raviSessionStateChangeHandlers {
                    if (id == "openRAVISessionStateHandler") {
                        HiFiLogger.log("RaviSession: Calling raviSessionStateChangeHandler with ID: \(id)")
                        handler(.closed)
                    }
                }
                fulfill(.closed)
                return
            }
            
            func closeRAVISessionStateHandler(newState: RaviSessionStates) -> Void {
                if (newState == RaviSessionStates.disconnected) {
                    HiFiLogger.log("RaviSession: Closing RAVI Session...")
                } else if (newState == RaviSessionStates.closed) {
                    self.removeRAVISessionStateChangeHandler(changeHandlerID: "closeRAVISessionStateHandler")
                    fulfill(newState)
                } else {
                    self.removeRAVISessionStateChangeHandler(changeHandlerID: "closeRAVISessionStateHandler")
                    reject(NSError(domain: "", code: 1, userInfo: ["state": newState]))
                }
            }
            self.addRAVISessionStateChangeHandler(changeHandlerID: "closeRAVISessionStateHandler", changeHandler: closeRAVISessionStateHandler)
            
            self._handleRAVISessionStateChange(newState: RaviSessionStates.disconnected)
        }
    }
    
    func _handleRAVISessionStateChange(newState: RaviSessionStates) {
        if (self.state == newState) {
            return
        }
        
        HiFiLogger.log("RaviSession: New RAVI Session state: \(newState)")
        self.state = newState
        
        for (id, handler) in self.raviSessionStateChangeHandlers {
            HiFiLogger.log("RaviSession: Calling raviSessionStateChangeHandler with ID: \(id)")
            handler(newState)
        }
    }
    
} // End of the RaviSession class

internal class RaviWebRTCImplementation : NSObject, RTCPeerConnectionDelegate, RTCAudioSessionDelegate {
    var _raviSession: RaviSession
    var _signalingConnection: RaviSignalingConnection?
    var _raviAudioSender: RTCRtpSender?
    var _rtcConnection: RTCPeerConnection?
    var _audioInputMuted: Bool = false
    var _customSTUNAndTURNConfig: CustomSTUNAndTURNConfig?
    public var avAudioSession: AVAudioSession
    
    public static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()
    
    init(raviSession: RaviSession) {
        self._raviSession = raviSession
        self._signalingConnection = nil
        self._raviAudioSender = nil
        self.avAudioSession = AVAudioSession.sharedInstance()

        super.init()
    }
    
    public func initRTCConnection() {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: [DEFAULT_TURN_SERVER_URI], username: LEGACY_TURN_USERNAME, credential: LEGACY_TURN_CREDENTIAL),
        ]
        
        if (self._raviSession.turnUrls != nil && self._raviSession.turnUsername != nil && self._raviSession.turnCredential != nil) {
            config.iceServers.append(RTCIceServer(urlStrings: self._raviSession.turnUrls!, username: self._raviSession.turnUsername!, credential: self._raviSession.turnCredential!))
        }
        
        if (self._raviSession.stunURLs != nil) {
            config.iceServers.append(RTCIceServer(urlStrings: self._raviSession.stunURLs!))
        }
        
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.disableIPV6 = true
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        self._rtcConnection = RaviWebRTCImplementation.factory.peerConnection(with: config, constraints: constraints, delegate: self)
        
        self._raviSession.streamController.setInputAudioTrackChangeHandler(onInputAudioTrackChanged: self._replaceAudioInputTrack)
        self._raviSession.streamController.setInputAudioTrack(inputAudioTrack: self._raviSession.streamController.createAudioInputTrack())
    }
    
    func _assignSignalingConnection(signalingConnection: RaviSignalingConnection) {
        self._signalingConnection = signalingConnection
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        HiFiLogger.log("RaviWebRTCImplementation: WebRTC Signaling State changed to \(stateChanged.rawValue)")
        if (self._signalingConnection != nil && stateChanged == .closed) {
            self._signalingConnection?._handleSignalingStateChange(newState: .closed)
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        HiFiLogger.log("RaviWebRTCImplementation: Adding remote RTCMediaStream to local Stream Controller...")
        self._raviSession.streamController._setOutputAudioStream(outputAudioStream: stream)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        HiFiLogger.log("RaviWebRTCImplementation: WebRTC Peer Connection State changed to \(newState.rawValue)")
        switch newState {
        case .closed:
            self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.closed)
            break
        case .connecting:
            self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.connecting)
            break
        case .connected:
            if (self._raviSession.getCommandController()._commandDataChannel?.rtcDataChannel.readyState == .open &&
                    self._raviSession.getCommandController()._inputDataChannel?.rtcDataChannel.readyState == .open) {
                self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.ready)
            } else {
                self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.connected)
            }
            break
        case .disconnected:
            self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.disconnected)
            break
        case .failed:
            self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.failed)
            break
        case .new:
            self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.new)
            break
        default:
            break
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        HiFiLogger.log("RaviWebRTCImplementation: WebRTC ICE Connection State changed to \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        HiFiLogger.log("RaviWebRTCImplementation: WebRTC ICE Gathering State changed to \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        HiFiLogger.log("RaviWebRTCImplementation: RTC Peer Connection generated a new RTC ICE Candidate! Creating candidate string to send to Signaling Server...")
        // The server expects a specific type of string here, built using the candidate information.
        var sdpString = ""
        if (candidate.sdp.count > 0) {
            sdpString = "{\"candidate\":\"\(candidate.sdp)\",\"sdpMid\":\"\(candidate.sdpMid ?? "audio")\",\"sdpMLineIndex\":\(String(describing: candidate.sdpMLineIndex))}"
        } else {
            HiFiLogger.error("RaviWebRTCImplementation: ICE Candidate SDP string was empty!")
            return
        }
        
        if (sdpString.count > 0) {
            let candidateString = "{\"ice\":\(sdpString),\"uuid\":\"\(self._raviSession.getUUID())\"}"
            
            self._signalingConnection!.send(message: candidateString, messageDescriptionForDebug: "Specially-formatted ICE Candidate 'Candidate String'")
        } else {
            HiFiLogger.error("RaviWebRTCImplementation: Didn't send local ICE candidate information over signaling connection because Candidate String was empty.")
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        HiFiLogger.log("RaviWebRTCImplementation: RTC Peer Connection removed ICE candidates: \(candidates)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        HiFiLogger.log("RaviWebRTCImplementation: RTC Peer Connection opened new RTCDataChannel with label \(dataChannel.label)")
        switch (dataChannel.label) {
        case "ravi.input":
            self._raviSession.commandController._setInputDataChannel(inputDataChannel: dataChannel)
            break
        case "ravi.command":
            self._raviSession.commandController._setCommandDataChannel(commandDataChannel: dataChannel)
            break
        default:
            HiFiLogger.warn("RaviWebRTCImplementation: Received data via unknown channel named \(dataChannel.label)")
            break
        }
        
        if (self._raviSession.getState() == .connected &&
                self._raviSession.commandController._inputDataChannel?.rtcDataChannel.readyState == .open &&
                self._raviSession.commandController._commandDataChannel?.rtcDataChannel.readyState == .open) {
            self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.ready)
        } else if (self._raviSession.getState() == .connected &&
                    self._raviSession.commandController._inputDataChannel != nil &&
                    self._raviSession.commandController._inputDataChannel != nil) {
            HiFiLogger.log("RaviWebRTCImplementation: The RAVI session is connected, but one or both of the Input or Command data channels are not yet ready!\nInput Data Channel Ready State: \(self._raviSession.commandController._inputDataChannel!.rtcDataChannel.readyState.rawValue)\nCommand Data Channel Ready State: \(self._raviSession.commandController._commandDataChannel!.rtcDataChannel.readyState.rawValue)")
            
            // TODO: Don't say we're ready til the data channels are both open and ready!
            HiFiLogger.log("We're going to move forward anyway. This is risky. TODO: Don't say we're ready til the data channels are both open and ready!")
            self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.ready)
        }
    }
    
    // When a negotiationneeeded is triggered from this peer, signal the server side to initiate an offer
    // In Ravi, the webrtc negotiation is always initiated from the server side
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        HiFiLogger.log("RaviWebRTCImplementation: Need renegotiation...")
        let dict = [
            "renegotiate": "please",
            "uuid": self._raviSession.getUUID()
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            let msgString = String(data: data, encoding: String.Encoding.utf8) ?? nil
            // Negotiation needed but only if we are not already currently negotiating
            if (self._signalingConnection != nil && self._rtcConnection != nil && self._rtcConnection!.signalingState == .stable) {
                self._signalingConnection!.send(message: msgString!, messageDescriptionForDebug: "Renegotiation message")
            }
        } catch { }
    }
    
    func _replaceAudioInputTrack(audioInputTrack: RTCAudioTrack?) {
        if (audioInputTrack != nil) {
            HiFiLogger.log("RaviWebRTCImplementation: Replacing Audio Input Track...")
            let streamId = "stream"
            if (self._raviAudioSender != nil) {
                self._rtcConnection!.removeTrack(self._raviAudioSender!)
            }
            self._raviAudioSender = self._rtcConnection!.add(audioInputTrack!, streamIds: [streamId])
            // We expect the 'negotiationneeded' event to fire.
        } else {
            // The stream assigned is null meaning we want to kill any current input audio stream.
            HiFiLogger.log("RaviWebRTCImplementation: Removing all audio senders...")
            if (self._raviAudioSender != nil) {
                self._rtcConnection!.removeTrack(self._raviAudioSender!)
            }
            self._raviAudioSender = nil
        }
    }
    
    func _openWebRTCConnection(params: WebRTCSessionParams?, customSTUNAndTURN: CustomSTUNAndTURNConfig?) {
        if (customSTUNAndTURN != nil) {
            self._customSTUNAndTURNConfig = customSTUNAndTURN!
        }
        
        HiFiLogger.log("RaviWebRTCImplementation: Attempting to open WebRTC connection...")
        
        if (self._rtcConnection != nil && (self._rtcConnection!.connectionState == .connecting || self._rtcConnection!.connectionState == .connected)) {
            HiFiLogger.log("RaviWebRTCImplementation: We already have a WebRTC connection in progress. Aborting...")
            if (self._rtcConnection!.connectionState == .connecting) {
                self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.connecting)
            } else if (self._rtcConnection!.connectionState == .connected) {
                self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.connected)
            }
            return
        }
        
        if (self._signalingConnection != nil) {
            // Add a handler for state change events onto the provided
            // signaling connection. This should listen for the appropriate
            // "ready to negotiate connection" message from the signaling connection.
            self._signalingConnection!.addSignalingMessageHandler(messageHandlerID: "negotiator", messageHandler: self._negotiator)
            
            // Build the message string manually because the format of the message doesn't conform to a standard, and thus we can't use a `Codable`.
            var msgString: String
            if (params != nil) {
                msgString = "{\"request\":{\"audioMinJitterBufferDuration\":\(params!.audioMinJitterBufferDuration ?? 0),\"audioMinJitterBufferDuration\":\(params!.audioMaxJitterBufferDuration ?? 1),\"sessionID\":\"\(self._raviSession.getUUID())\"}}"
            } else {
                msgString = "{\"request\":\"\(self._raviSession.getUUID())\"}"
            }
            self._signalingConnection!.send(message: msgString, messageDescriptionForDebug: "Request Message")
        } else {
            HiFiLogger.warn("RaviWebRTCImplementation: Warning: While opening the WebRTC connection, our signaling connection wasn't set up!")
        }
    }
    
    func _closeWebRTCConnection() {
        self._signalingConnection?.removeSignalingMessageHandler(messageHandlerID: "negotiator")
        
        if (self._rtcConnection == nil) {
            return
        }
        
        HiFiLogger.log("RaviWebRTCImplementation: Closing WebRTC connection...")
        self._rtcConnection!.close()
        
//        RTCAudioSession.sharedInstance().isAudioEnabled = false
//        do {
//            try self.avAudioSession.setActive(false)
//        } catch let error {
//            HiFiLogger.warn("When closing RAVI Session, couldn't call `avAudioSession.setActive(false)`! Error\n\(error)")
//        }
//        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(self.avAudioSession)
        
        self._raviSession._handleRAVISessionStateChange(newState: RaviSessionStates.closed)
    }
    
    func _forceBitrateUp(sdp: String) -> String {
        // Need to format the SDP differently if the input is stereo, so
        // reach up into our owner's stream controller to find out.
        let localAudioIsStereo = self._raviSession.streamController.isInputAudioStereo()
        // Use 128kbps for stereo upstream audio, 64kbps for mono
        let bitrate = localAudioIsStereo ? 128000 : 64000
        
        // SDP munging: use 128kbps for stereo upstream audio, 64kbps for mono
        let regex = try! NSRegularExpression(pattern: "\\ba=fmtp:111 \\b", options: .caseInsensitive)
        let newSdp = regex.stringByReplacingMatches(in: sdp, options: [], range: NSRange(0..<sdp.utf16.count), withTemplate: "a=fmtp:111 maxaveragebitrate=\(bitrate);")
        return newSdp
    }
    
    func _forceStereoDown(sdp: String) -> String {
        // munge the SDP answer: request 128kbps stereo for downstream audio
        let regex = try! NSRegularExpression(pattern: "\\ba=fmtp:111 \\b", options: .caseInsensitive)
        let newSdp = regex.stringByReplacingMatches(in: sdp, options: [], range: NSRange(0..<sdp.utf16.count), withTemplate: "a=fmtp:111 maxaveragebitrate=128000;sprop-stereo=1;stereo=1;")
        return newSdp
    }
    
    func _negotiator(message: SignalingWebSocketMessageForUUID) {
        // Just in case, make sure we have everything we need
        if (self._signalingConnection == nil) {
            HiFiLogger.error("RaviWebRTCImplementation: Missing _signalingConnection! Can't set up connection.")
            return
        }
        
        if (message.forUuid != self._raviSession.getUUID()) {
            return
        }
        
        if (message.sdp != nil) {
            HiFiLogger.log("RaviWebRTCImplementation: Negotiating! Got an SDP from the Signaling Server...")
            
            if (self._customSTUNAndTURNConfig != nil) {
                self._raviSession.stunURLs = self._customSTUNAndTURNConfig!.stunUrls
                self._raviSession.turnUrls = self._customSTUNAndTURNConfig!.turnUrls
                self._raviSession.turnUsername = self._customSTUNAndTURNConfig!.turnUsername
                self._raviSession.turnCredential = self._customSTUNAndTURNConfig!.turnCredential
            } else if (message.turn != nil) {
                self._raviSession.turnUrls = message.turn!.urls
                self._raviSession.turnUsername = message.turn!.username
                self._raviSession.turnCredential = message.turn!.credential
            }
            
            if (self._rtcConnection == nil) {
                self.initRTCConnection()
            }
            
            // Force our desired bitrate by munging the SDP, and create a session description for it
            let sdpString = self._forceBitrateUp(sdp: message.sdp!)
            if (message.type! != "offer") {
                HiFiLogger.warn("RaviWebRTCImplementation: Got SDP whose type is not 'offer'. Aborting...")
                return
            }
            
            HiFiLogger.log("RaviWebRTCImplementation: Setting new remote RTC Session Description Offer with modified (specific bitrate) SDP...")
            let newSessionDescription = RTCSessionDescription(type: .offer, sdp: sdpString)
            
            self._rtcConnection!.setRemoteDescription(newSessionDescription, completionHandler: { (error: Error?) in
                if (error != nil) {
                    HiFiLogger.error("RaviWebRTCImplementation: Error when setting Remote Description: \(error!)")
                    return
                }
                
                HiFiLogger.log("RaviWebRTCImplementation: Successfully set remote description! Creating answer...")
                
                self._rtcConnection!.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), completionHandler: { (answerDesc: RTCSessionDescription?, error: Error?) in
                    if (error != nil) {
                        HiFiLogger.error("RaviWebRTCImplementation: Error when creating RTC Connection answer: \(error!)")
                        return
                    }
                    
                    let newSdp = self._forceStereoDown(sdp: answerDesc!.sdp)
                    let newLocalSessionDescription = RTCSessionDescription(type: .answer, sdp: newSdp)
                    HiFiLogger.log("RaviWebRTCImplementation: Successfully created answer with forced stereo down! Setting local description...")
                    self._rtcConnection!.setLocalDescription(newLocalSessionDescription, completionHandler: { (error: Error?) in
                        if (error != nil) {
                            HiFiLogger.error("RaviWebRTCImplementation: Error when setting Local Description: \(error!)")
                            return
                        }
                        
                        HiFiLogger.log("Successfully set local description! Crafting answer string to send to Signaling Server...")
                        
                        let sdpString = self._rtcConnection!.localDescription!.sdp.replacingOccurrences(of: "\r\n", with: "\\r\\n")
                        
                        let answerString = "{\"sdp\":{\"type\":\"answer\",\"sdp\":\"\(sdpString)\"},\"type\":\"answer\",\"uuid\":\"\(self._raviSession.getUUID())\"}"
                        
                        self._signalingConnection!.send(message: answerString, messageDescriptionForDebug: "Specially-formatted RTC Connection answer string")
                    })
                })
            })
        }
        
        if (message.ice != nil) {
            HiFiLogger.log("RaviWebRTCImplementation: Negotiating! Received ICE candidate from the Signaling Server...")
            
            let newCandidate = RTCIceCandidate(
                sdp: message.ice!.candidate,
                sdpMLineIndex: message.ice!.sdpMLineIndex,
                sdpMid: message.ice!.sdpMid
            )
            
            if (self._rtcConnection != nil) {
                HiFiLogger.log("RaviWebRTCImplementation: Adding new ICE candidate to local RTC Connection...")
                self._rtcConnection!.add(newCandidate) { error in
                    if (error != nil) {
                        HiFiLogger.error("RaviWebRTCImplementation: Error adding ICE candidate to local RTC connection! Error:\n\(error!)")
                    } else {
                        HiFiLogger.log("RaviWebRTCImplementation: Added new ICE candidate!")
                    }
                }
            } else {
                HiFiLogger.log("Ignoring ICE candidate until `self._rtcConnection` is set up.")
            }
        }
    }
}

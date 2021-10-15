//
//  HiFiCommunicator.swift
//  
//
//  Created by zach on 3/5/21.
//

import Foundation
import WebRTC
import Promises

/**
    When the state of the connection to the High Fidelity Audio Server changes, the new state will be one of these values.
*/
public enum HiFiConnectionStates {
    case connected
    case disconnected
    case failed
    /// The `HiFiConnectionState` will be `"Unavailable"` when the API Server is at capacity.
    case unavailable
}

/**
 *
*/
public enum HiFiUserDataStreamingScopes : String {
    /**
        Passing this value to the `HiFiCommunicator` constructor means that the Server will not send any
        User Data updates to the client, meaning User Data Subscriptions will not function. This Streaming Scope
        saves bandwidth and, marginally, processing time.
    */
    case none = "none"
    /**
        Passing this value to the `HiFiCommunicator` constructor means that the Server will only send
        _peer data_ to the Client; the Server will not send User Data pertaining to the connecting Client when
        this Data Streaming Scope is selected.
    */
    case peers = "peers"
    /**
        "all" is the default value when the `HiFiCommunicator` constructor is called. All User Data
        will be streamed from the Server to the Client.
    */
    case all = "all"
}

/// Contains information about the client pertaining to the `HiFiSpatialAudio` client library.
public struct HiFiCommunicatorClientInfo {
    /// `true` if there's an input audio stream set on the `HiFiCommunicator` object; `false` otherwise.
    var inputAudioStreamSet: Bool = false
    /// The `HiFiSpatialAudio` Swift client library version. TODO: Automatically populate this value.
    var clientVersion: String = "v0.1.0"
}

/// Contains information about the client and server pertaining to the `HiFiSpatialAudio` client library.
public struct HiFiCommunicatorInfo {
    var clientInfo: HiFiCommunicatorClientInfo
    var serverInfo: HiFiMixerInfo
}

/**
    This class exposes properties and methods useful for communicating from the High Fidelity Audio API Client to
    the High Fidelity Audio API Server. 
*/
public class HiFiCommunicator {
    /// "Prevents" users of our client-side API from slamming their mixer with requests.
    /// Of course, because this particular rate limit is clientside, savvy developers could work around it.
    public var transmitRateLimitTimeoutMS: Int
    private var _transmitRateLimitTimeout: Timer? = nil
    private var _wantedToTransmitHiFiAudioAPIData: Bool = false
    
    /// This is usually the `RTCAudioTrack` associated with a user's audio input device,
    /// but it could be any `RTCAudioTrack`.
    private var _inputAudioTrack: RTCAudioTrack? = nil
    
    /// Used to keep track of what data to send to the mixer. The client only sends data that the mixer doesn't already know about.
    private var _currentHiFiAudioAPIData: HiFiAudioAPIData
    /// Used to keep track of what data to send to the mixer. The client only sends data that the mixer doesn't already know about.
    private var _lastTransmittedHiFiAudioAPIData: HiFiAudioAPIData
    
    /// Library users can make use of "User Data Subscriptions" to cause something to happen
    /// when the server reports that a component of user's data - such as their  position, orientation, or volume - has been modified.
    private var _userDataSubscriptions: [UserDataSubscription]
    
    /// A custom STUN server and TURN server configuration.
    private var _customSTUNAndTURNConfig: CustomSTUNAndTURNConfig?
    // Custom `WebRTCSessionParams` applied to the WebRTC connection.
    private var _webRTCSessionParams: WebRTCSessionParams?
    
    /**
        Provide an `onUsersDisconnected()` callback function when instantiating the `HiFiCommunicator` object, or by setting
        `HiFiCommunicator.onUsersDisconnected` after instantiation.

        This function will be called when a user disconnects from the High Fidelity Audio API Server.
    */
    public var onUsersDisconnected: (([ReceivedHiFiAudioAPIData]) -> Void)? = nil
    
    // This contains data dealing with the mixer session, such as the RAVI session, WebRTC address, etc. Developers need not think about the `_mixerSession`.
    private var _mixerSession: HiFiMixerSession?
    
    /**
        Constructor for the HiFiCommunicator object.
        - Parameter initialHiFiAudioAPIData: The initial position, orientation, etc of the user.
        - Parameter onConnectionStateChanged: A function that will be called when the connection state to the High Fidelity Audio API Server changes. See `HiFiConnectionStates`.
        - Parameter onUsersDisconnected: A function that will be called when a peer disconnects from the Space.
        - Parameter transmitRateLimitTimeoutMS: User Data updates will not be sent to the server any more frequently than this number in milliseconds.
        - Parameter userDataStreamingScope: Cannot be set later. See `HiFiUserDataStreamingScopes`.
        - Parameter hiFiAxisConfiguration: Cannot be set later. The 3D axis configuration. See `ourHiFiAxisConfiguration` for defaults.
        - Parameter echoCancellingVoiceProcessingInMono: Cannot be set later.
                                                       
                                                       - If `true`, the default RTC implementation is used, in which there is one output channel, connected to the echo-cancelling voice audio unit with hardware automatic gain control, and allowing "hands-free" bluetooth devices (including peripheral microphones).
                                                       - If `false` (the default), stereo Bluetooth is picked up, output is in stereo when possible, input is from the phone microphone, and there is no hardware echo-cancellation or automatic gain control.
    */
    public init(
        initialHiFiAudioAPIData: HiFiAudioAPIData? = nil,
        onConnectionStateChanged: ((HiFiConnectionStates) -> Void)? = nil,
        onUsersDisconnected: (([ReceivedHiFiAudioAPIData]) -> Void)? = nil,
        transmitRateLimitTimeoutMS: Int = HiFiConstants.DEFAULT_TRANSMIT_RATE_LIMIT_TIMEOUT_MS,
        userDataStreamingScope: HiFiUserDataStreamingScopes = .all,
        echoCancellingVoiceProcessingInMono: Bool = false,
        hiFiAxisConfiguration: HiFiAxisConfiguration? = nil,
        webRTCSessionParams: WebRTCSessionParams? = nil,
        customSTUNAndTURNConfig: CustomSTUNAndTURNConfig? = nil
    ) {
        // Make minimum 10ms
        var rateLimitTimeoutMS = transmitRateLimitTimeoutMS
        RTCPeerConnectionFactory.bypassVoiceModule = !echoCancellingVoiceProcessingInMono // Must be set before instantiating the factory!
        if (rateLimitTimeoutMS < HiFiConstants.MIN_TRANSMIT_RATE_LIMIT_TIMEOUT_MS) {
            HiFiLogger.warn("\(transmitRateLimitTimeoutMS) must be >= \(HiFiConstants.MIN_TRANSMIT_RATE_LIMIT_TIMEOUT_MS)ms! Setting to \(HiFiConstants.MIN_TRANSMIT_RATE_LIMIT_TIMEOUT_MS)ms...")
            rateLimitTimeoutMS = HiFiConstants.MIN_TRANSMIT_RATE_LIMIT_TIMEOUT_MS
        }
        self.transmitRateLimitTimeoutMS = rateLimitTimeoutMS
        
        if (onUsersDisconnected != nil) {
            self.onUsersDisconnected = onUsersDisconnected!
        }
        
        self._currentHiFiAudioAPIData = HiFiAudioAPIData()
        self._lastTransmittedHiFiAudioAPIData = HiFiAudioAPIData()
        
        self._userDataSubscriptions = [UserDataSubscription]()
        
        self._customSTUNAndTURNConfig = customSTUNAndTURNConfig
        self._webRTCSessionParams = webRTCSessionParams
        
        if (hiFiAxisConfiguration != nil) {
            if (HiFiAxisConfiguration.verify(axisConfiguration: hiFiAxisConfiguration!)) {
                ourHiFiAxisConfiguration.rightAxis = hiFiAxisConfiguration!.rightAxis
                ourHiFiAxisConfiguration.leftAxis = hiFiAxisConfiguration!.leftAxis
                ourHiFiAxisConfiguration.intoScreenAxis = hiFiAxisConfiguration!.intoScreenAxis
                ourHiFiAxisConfiguration.outOfScreenAxis = hiFiAxisConfiguration!.outOfScreenAxis
                ourHiFiAxisConfiguration.upAxis = hiFiAxisConfiguration!.upAxis
                ourHiFiAxisConfiguration.downAxis = hiFiAxisConfiguration!.downAxis
                ourHiFiAxisConfiguration.handedness = hiFiAxisConfiguration!.handedness
                ourHiFiAxisConfiguration.eulerOrder = hiFiAxisConfiguration!.eulerOrder
            } else {
                HiFiLogger.error("There is an error with the passed `HiFiAxisConfiguration`, so the new axis configuration was not set. There are more error details in the logs above.")
            }
        }
        
        self._mixerSession = HiFiMixerSession(
            userDataStreamingScope: userDataStreamingScope,
            onUserDataUpdated: self._handleUserDataUpdates,
            onUsersDisconnected: self._onUsersDisconnected,
            onConnectionStateChanged: onConnectionStateChanged
        )
        
        if (initialHiFiAudioAPIData != nil) {
            // Initialize the current Audio API Data with the given data by using the 'updateUserData()' call for sanity.
            self._updateUserData(newUserData: initialHiFiAudioAPIData!)
        }
    }
    
    /**
        Connects to the High Fidelity Audio API server and transmits the initial user data to the server.
        
        - Parameter hifiAuthJWT: This JSON Web Token (JWT) is used by callers to associate a user with a specific High Fidelity Spatial Audio API Server.
        
        JWTs are an industry-standard method for securely representing claims between two applications.
        
        ## Important information about JWTs

        - **Do not expose JWTs to users!** Anyone with access to one of your JWTs will be able to connect to your High Fidelity Spatial Audio API Server.
        - In your application's production environment, each client running your app code should connect to the High Fidelity Spatial Audio Server with a unique JWT.
        
        To generate a JWT for use with the High Fidelity Audio API:

        1. Head to https://jwt.io/ to find the appropriate library for your langauge. For Swift applications, we recommend [JWTKit](https://github.com/vapor/jwt-kit).
        2. Using the [High Fidelity Audio API Developer Console](https://account.highfidelity.com/dev/account)
        obtain your App ID, Space ID, and App Secret.
        3. Create your user's JWT using the appropriate library, passing your App ID, Space ID, and App Secret. Please reference our ["Get a JWT" guide](https://www.highfidelity.com/api/guides/misc/getAJWT) for additional context.
        4. Pass the created JWT to `connectToHiFiAudioAPIServer()`.
        
        - Parameter signalingHostURL: A URL that will be used to create a valid WebRTC signaling address at High Fidelity. The passed `signalingHostURL` parameter should not contain the protocol
        or port - e.g. `api.highfidelity.com` - and it will be used to construct a signaling address of the form: `wss://${signalingHostURL}:${signalingPort}/?token=`
        If the developer does not pass a `signalingHostURL` parameter, a default URL will be used instead. See: `HiFiConstants.DEFAULT_SIGNALING_HOST_URL`.
        
        - Parameter signalingPort: The port to use for making WebSocket connections to the High Fidelity servers.
        If the developer does not pass a `signalingPort` parameter, the default (443) will be used instead. See: `HiFiConstants.DEFAULT_SIGNALING_PORT`
        
        - Returns: If this operation is successful, the Promise will resolve. If unsuccessful, the Promise will reject.
    */
    @discardableResult public func connectToHiFiAudioAPIServer(
        hifiAuthJWT: String,
        signalingHostURL: String = HiFiConstants.DEFAULT_SIGNALING_HOST_URL,
        signalingPort: Int = HiFiConstants.DEFAULT_SIGNALING_PORT) -> Promise<AudionetInitResponse> {
        return Promise<AudionetInitResponse> { fulfill, reject in
            var webRTCSignalingAddress: String
            
            let url = URL(string: signalingHostURL)
            if (url != nil && url!.host != nil) {
                webRTCSignalingAddress = "wss://\(String(describing: url!.host)):\(String(describing: url!.port != nil ? url!.port : signalingPort))"
            } else {
                webRTCSignalingAddress = "wss://\(signalingHostURL):\(signalingPort)"
            }
            self._mixerSession!.webRTCAddress = "\(webRTCSignalingAddress)?token=\(hifiAuthJWT)"
            HiFiLogger.log("Using WebRTC Signaling Address: \(webRTCSignalingAddress)?token=<token redacted>")
            
            self._mixerSession!.connect(webRTCSessionParams: self._webRTCSessionParams, customSTUNAndTURNConfig: self._customSTUNAndTURNConfig).then { mixerConnectionResponse in
                HiFiLogger.log("HiFiCommunicator: Transmitting initial Audio API data to server...")
                _ = self._transmitHiFiAudioAPIDataToServer(forceTransmit: true)
                return fulfill(mixerConnectionResponse)
            }.catch { error in
                return reject(error)
            }
        }
    }
    
    /**
        Disconnects from the High Fidelity Audio API. After this call, user data will no longer be transmitted to High Fidelity, the audio input stream will not be transmitted to High Fidelity, and the user will no longer be able to hear the audio stream from High Fidelity.
    */
    @discardableResult public func disconnectFromHiFiAudioAPIServer() -> Promise<Bool> {
        self._inputAudioTrack = nil
        self.onUsersDisconnected = nil
        self._userDataSubscriptions = [UserDataSubscription]()
        // When this HiFiCommunicator reconnects to a server, the server knows nothing about the client.
        // Therefore, clear the history of data sent by the client to the server below, so that
        // HiFiCommunicator re-sends this data to the server as appropriate.
        // Do not clear _currentHiFiAudioAPIData, as the client is likely reconnecting to the same server.
        // Combined with the clearing of history of data sent, this ensures that the client's
        // current data (position, orientation, etc.) is re-sent to the server upon reconnect.
        self._lastTransmittedHiFiAudioAPIData = HiFiAudioAPIData()
        
        return self._mixerSession!.disconnect()
    }

    /**
        Adjusts the gain of another user for this communicator's current connection only. This is a single user version of `HiFiCommunicator.setOtherUserGainsForThisConnection`.
        This can be used to provide a more comfortable listening experience for the client. If you need to perform moderation actions which apply server side, use the [Administrative REST API](https://docs.highfidelity.com/rest/latest/index.html).
        
        To use this command, the communicator must currently be connected to a space. You can connect to a space using `HiFiCommunicator.connectToHiFiAudioAPIServer`.
        
        - Parameter hashedVisitId: The hashed visit ID of the user whose gain will be adjusted.
        Use `addUserDataSubscription` `HiFiCommunicator.onUsersDisconnected` to keep track of the hashed visit IDs of currently connected users.
        When you subscribe to user data, you will get a list of `ReceivedHiFiAudioAPIData` objects, which each contain, at minimum, `ReceivedHifiAudioAPIData.hashedVisitID`s and `ReceivedHifiAudioAPIData.providedUserID`s for each user in the space. By inspecting each of these objects, you can associate a user with their hashed visit ID, if you know their provided user ID.
        
        - Parameter gain: The relative gain to apply to the other user. By default, this is `1.0`. The gain can be any value in the range `0.0` to `10.0`, inclusive.
        For example: a gain of `2.0` will double the loudness of the user, while a gain of `0.5` will halve the user's loudness. A gain of `0.0` will effectively mute the user.
        
        - Returns: A `TransmitHiFiAudioAPIDataStatus` object.
    */
    @discardableResult public func setOtherUserGainForThisConnection(visitIdHash: String, gain: Float) -> TransmitHiFiAudioAPIDataStatus {
        return self.setOtherUserGainsForThisConnection(map: [visitIdHash : gain])
    }
    
    /**
        This function provides the ability to set _multiple_ user gains simultaneously. See `setOtherUserGainForThisConnection`.

        - Parameter map: A map of `hashedVisitId`s to `gain`s.
    */
    @discardableResult public func setOtherUserGainsForThisConnection(map: [String : Float]) -> TransmitHiFiAudioAPIDataStatus {
        let MIN_GAIN: Float = 0.0
        let MAX_GAIN: Float = 10.0
        for (id, gain) in map {
            self._currentHiFiAudioAPIData._otherUserGainQueue![id] = min(MAX_GAIN, max(MIN_GAIN, Float(gain)))
        }
        
        return self._transmitHiFiAudioAPIDataToServer()
    }
    
    /**
        - Returns: The final mixed audio `RTCMediaStream` coming from the High Fidelity Audio Server.
    */
    public func getOutputAudioMediaStream() -> RTCMediaStream? {
        return self._mixerSession!.getOutputAudioMediaStream()
    }
    
    /**
        Use this function to set whether the input audio stream will be muted or not. If the user's input audio stream is muted, the user will be inaudible to all other users.
        
        An alterative to calling this function is to set the user's `volumeThreshold` to `0`, which smoothly gates off the user's input.

        - Parameter isMuted: `true` to mute the user's input audio stream; `false` to unmute.

        - Returns: `true` if the stream was successfully muted/unmuted, `false` if it was not. (The user should assume that if this returns `false`, no change was made to the mute (track enabled) state of the stream.)
    */
    @discardableResult public func setInputAudioMuted(isMuted: Bool) -> Bool {
        HiFiLogger.debug("Setting input mute state to: \(isMuted)...")
        return self._mixerSession!.setInputAudioMuted(newMutedValue: isMuted)
    }
    
    /**
        - Returns: A bunch of info about this `HiFiCommunicator` instantiation, including Server Version.
    */
    public func getCommunicatorInfo() -> HiFiCommunicatorInfo {
        let clientInfo = HiFiCommunicatorClientInfo(inputAudioStreamSet: self._inputAudioTrack != nil)
        return HiFiCommunicatorInfo(clientInfo: clientInfo, serverInfo: self._mixerSession!.mixerInfo)
    }
    
    private func _updateUserData(newUserData: HiFiAudioAPIData) -> Void {
        let position = newUserData.position
        if (position != nil) {
            if (self._currentHiFiAudioAPIData.position == nil) {
                self._currentHiFiAudioAPIData.position = Point3D()
            }
            
            self._currentHiFiAudioAPIData.position!.x = position!.x
            self._currentHiFiAudioAPIData.position!.y = position!.y
            self._currentHiFiAudioAPIData.position!.z = position!.z
        }
        
        let orientationQuat = newUserData.orientationQuat
        let orientationEuler = newUserData.orientationEuler
        if (orientationQuat != nil) {
            if (self._currentHiFiAudioAPIData.orientationQuat == nil) {
                self._currentHiFiAudioAPIData.orientationQuat = OrientationQuat3D()
            }
            
            self._currentHiFiAudioAPIData.orientationQuat!.w = orientationQuat!.w
            self._currentHiFiAudioAPIData.orientationQuat!.x = orientationQuat!.x
            self._currentHiFiAudioAPIData.orientationQuat!.y = orientationQuat!.y
            self._currentHiFiAudioAPIData.orientationQuat!.z = orientationQuat!.z
        } else if (orientationEuler != nil) {
            self._currentHiFiAudioAPIData.orientationQuat = HiFiUtilities.eulerToQuaternion(euler: orientationEuler!, order: ourHiFiAxisConfiguration.eulerOrder)
        }
        
        let volumeThreshold = newUserData.volumeThreshold
        if (volumeThreshold != nil) {
            self._currentHiFiAudioAPIData.volumeThreshold = volumeThreshold!
        }
        
        let hiFiGain = newUserData.hiFiGain
        if (hiFiGain != nil) {
            self._currentHiFiAudioAPIData.hiFiGain = hiFiGain!
        }
        
        let userAttenuation = newUserData.userAttenuation
        if (userAttenuation != nil) {
            self._currentHiFiAudioAPIData.userAttenuation = userAttenuation!
        }
        
        let userRolloff = newUserData.userRolloff
        if (userRolloff != nil) {
            self._currentHiFiAudioAPIData.userRolloff = userRolloff!
        }
    }
    
    /**
        Clears the clientside rate limit timeout used to prevent user data from being sent to the High Fidelity Audio API server too often.
    */
    private func _maybeClearRateLimitTimeout() -> Void {
        if (self._transmitRateLimitTimeout != nil) {
            self._transmitRateLimitTimeout!.invalidate()
        }
        self._transmitRateLimitTimeout = nil
    }
    
    /**
        We keep a clientside copy of the data that we last transmitted to the High Fidelity Audio API server. We use this data to
        ensure that we only send to the server the minimum set of data necessary - i.e. the difference between the data contained on the server
        about the user and the new data that the client has locally. We use this function here to update the clientside copy of the data
        that we last transmitted.
        
        - Parameter dataJustTransmitted: The data that we just transmitted to the High Fidelity Audio API server.
    */
    private func _updateLastTransmittedHiFiAudioAPIData(dataJustTransmitted: HiFiAudioAPIData) -> Void {
        if (dataJustTransmitted.position != nil) {
            if (self._lastTransmittedHiFiAudioAPIData.position == nil) {
                self._lastTransmittedHiFiAudioAPIData.position = Point3D()
            }
            
            self._lastTransmittedHiFiAudioAPIData.position!.x = dataJustTransmitted.position!.x
            self._lastTransmittedHiFiAudioAPIData.position!.y = dataJustTransmitted.position!.y
            self._lastTransmittedHiFiAudioAPIData.position!.z = dataJustTransmitted.position!.z
        }
        if (dataJustTransmitted._transformedPosition != nil) {
            if (self._lastTransmittedHiFiAudioAPIData._transformedPosition == nil) {
                self._lastTransmittedHiFiAudioAPIData._transformedPosition = Point3D()
            }
            
            self._lastTransmittedHiFiAudioAPIData._transformedPosition!.x = dataJustTransmitted._transformedPosition!.x
            self._lastTransmittedHiFiAudioAPIData._transformedPosition!.y = dataJustTransmitted._transformedPosition!.y
            self._lastTransmittedHiFiAudioAPIData._transformedPosition!.z = dataJustTransmitted._transformedPosition!.z
        }
        
        if (dataJustTransmitted.orientationQuat != nil) {
            if (self._lastTransmittedHiFiAudioAPIData.orientationQuat == nil) {
                self._lastTransmittedHiFiAudioAPIData.orientationQuat = OrientationQuat3D()
            }
            
            self._lastTransmittedHiFiAudioAPIData.orientationQuat!.w = dataJustTransmitted.orientationQuat!.w
            self._lastTransmittedHiFiAudioAPIData.orientationQuat!.x = dataJustTransmitted.orientationQuat!.x
            self._lastTransmittedHiFiAudioAPIData.orientationQuat!.y = dataJustTransmitted.orientationQuat!.y
            self._lastTransmittedHiFiAudioAPIData.orientationQuat!.z = dataJustTransmitted.orientationQuat!.z
        }
        if (dataJustTransmitted._transformedOrientationQuat != nil) {
            if (self._lastTransmittedHiFiAudioAPIData._transformedOrientationQuat == nil) {
                self._lastTransmittedHiFiAudioAPIData._transformedOrientationQuat = OrientationQuat3D()
            }
            
            self._lastTransmittedHiFiAudioAPIData._transformedOrientationQuat!.w = dataJustTransmitted._transformedOrientationQuat!.w
            self._lastTransmittedHiFiAudioAPIData._transformedOrientationQuat!.x = dataJustTransmitted._transformedOrientationQuat!.x
            self._lastTransmittedHiFiAudioAPIData._transformedOrientationQuat!.y = dataJustTransmitted._transformedOrientationQuat!.y
            self._lastTransmittedHiFiAudioAPIData._transformedOrientationQuat!.z = dataJustTransmitted._transformedOrientationQuat!.z
        }
        
        if (dataJustTransmitted.volumeThreshold != nil) {
            self._lastTransmittedHiFiAudioAPIData.volumeThreshold = dataJustTransmitted.volumeThreshold!
        }
        if (dataJustTransmitted.hiFiGain != nil) {
            self._lastTransmittedHiFiAudioAPIData.hiFiGain = dataJustTransmitted.hiFiGain!
        }
        if (dataJustTransmitted.userAttenuation != nil) {
            self._lastTransmittedHiFiAudioAPIData.userAttenuation = dataJustTransmitted.userAttenuation!
        }
        if (dataJustTransmitted.userRolloff != nil) {
            self._lastTransmittedHiFiAudioAPIData.userRolloff = dataJustTransmitted.userRolloff!
        }
        if (dataJustTransmitted._otherUserGainQueue != nil) {
            for (id, gain) in dataJustTransmitted._otherUserGainQueue! {
                self._lastTransmittedHiFiAudioAPIData._otherUserGainQueue![id] = gain
            }
        }
    }
    
    private func _cleanUpHiFiAudioAPIDataHistory() {
        self._currentHiFiAudioAPIData._otherUserGainQueue = [:]
        
        let maxCachedOtherUserGains = 1000
        if (self._lastTransmittedHiFiAudioAPIData._otherUserGainQueue!.count > maxCachedOtherUserGains) {
            self._lastTransmittedHiFiAudioAPIData._otherUserGainQueue = [:]
            HiFiLogger.warn("HiFiCommunicator: `_lastTransmittedHiFiAudioAPIData._otherUserGainQueue` contained >\(maxCachedOtherUserGains) entries and was cleared to save space.")
        }
    }
    
    /**
        Formats the local user data properly, then sends that user data to the High Fidelity Audio API server. This transfer is rate limited.
        
        There is no reason a library user would need to call this function without also simultaneously updating User Data, so this function is `private`.
        
        - Parameter forceTransmit: `true` if we should ignore the clientside rate limiter and send the data regardless of its status; `false` otherwise.
        
        - Returns: A `TransmitHiFiAudioAPIDataStatus` object.
    */
    private func _transmitHiFiAudioAPIDataToServer(forceTransmit: Bool = false) -> TransmitHiFiAudioAPIDataStatus {
        // Make sure that a caller can't transmit data for another `this.transmitRateLimitTimeoutMS` milliseconds.
        if (self._transmitRateLimitTimeout == nil || forceTransmit == true) {
            self._wantedToTransmitHiFiAudioAPIData = false
            self._maybeClearRateLimitTimeout()
            if (!forceTransmit) {
                if #available(iOS 10.0, *) {
                    DispatchQueue.main.async {
                        self._transmitRateLimitTimeout = Timer.scheduledTimer(
                            withTimeInterval: Double(self.transmitRateLimitTimeoutMS) / 1000.0,
                            repeats: false
                        ) { (timer) in
                            self._maybeClearRateLimitTimeout()
                            
                            if (self._wantedToTransmitHiFiAudioAPIData) {
                                _ = self._transmitHiFiAudioAPIDataToServer(forceTransmit: true)
                            }
                        }
                    }
                } else {
                    _ = self._transmitHiFiAudioAPIDataToServer(forceTransmit: true)
                }
            }
            // Get the data to transmit, which is the difference between the last data we transmitted
            // and the current data we have stored.
            // This function will translate the new `HiFiAudioAPIData` object from above into stringified JSON data in the proper format,
            // then send that data to the mixer.
            // The function will return the raw data that it sent to the mixer.
            let transmitRetval = self._mixerSession!._transmitHiFiAudioAPIDataToServer(currentHiFiAudioAPIData: self._currentHiFiAudioAPIData, previousHiFiAudioAPIData: self._lastTransmittedHiFiAudioAPIData)
            if (transmitRetval.success) {
                // Now we have to update our "last transmitted" `HiFiAudioAPIData` object
                // to contain the data that we just transmitted.
                self._updateLastTransmittedHiFiAudioAPIData(dataJustTransmitted: self._currentHiFiAudioAPIData)
                // In some cases, clean up some of the transmitted data history
                // (particularly, `_otherUserGainQueue`)
                self._cleanUpHiFiAudioAPIDataHistory()
                
                return TransmitHiFiAudioAPIDataStatus(success: true, error: nil, transmitted: transmitRetval.transmitted)
            } else {
                return TransmitHiFiAudioAPIDataStatus(success: false, error: transmitRetval.error, transmitted: nil)
            }
        } else if (self._transmitRateLimitTimeout != nil && !forceTransmit) {
            self._wantedToTransmitHiFiAudioAPIData = true
            return TransmitHiFiAudioAPIDataStatus(success: true, error: "Transfer is rate-limited. Transfer will occur shortly automatically.", transmitted: nil)
        } else {
            return TransmitHiFiAudioAPIDataStatus(success: false, error: "Unhandled case inside `_transmitHiFiAudioAPIDataToServer()`!", transmitted: nil)
        }
    }
    
    /**
        Updates the user's data (position, orientation, etc) in internal data stores, then transmits the most up-to-date version of the user's data to the High Fidelity Audio API Server.

        Developers can call this function as often as they want. No matter how often developers call this function, the internal data store transmission is rate-limited
        and will only be sent to the server once every `transmitRateLimitTimeoutMS` milliseconds. When the internal data store is transmitted,
        the most up-to-date data will be transmitted.
        
        - Parameter newUserData: The new user data that we want to send to the High Fidelity Audio API server.

        - Returns: A `TransmitHiFiAudioAPIDataStatus` object.
    */
    public func updateUserDataAndTransmit(newUserData: HiFiAudioAPIData) -> TransmitHiFiAudioAPIDataStatus {
        self._updateUserData(newUserData: newUserData)
        return self._transmitHiFiAudioAPIDataToServer()
    }
    
    /**
        Ingests user data updates from the server and, if relevant, calls the relevant callback functions associated with the
        User Data Subscriptions. See `addUserDataSubscription`.
        
        - Parameter newUserDataFromServer: Contains all of the new user data most recently received from the server.
    */
    private func _handleUserDataUpdates(newUserDataFromServer: [ReceivedHiFiAudioAPIData]) -> Void {
        if (self._userDataSubscriptions.count == 0) {
            return
        }
        
        for subscription in self._userDataSubscriptions {
            var currentSubscriptionCallbackData = [ReceivedHiFiAudioAPIData]()
            
            for newUserData in newUserDataFromServer {
                if (subscription.providedUserID != nil && newUserData.providedUserID != subscription.providedUserID) {
                    continue
                }
                
                let newCallbackData = ReceivedHiFiAudioAPIData(providedUserID: nil, hashedVisitID: nil, volumeDecibels: nil, position: nil, orientationQuat: nil, isStereo: nil)
                
                if (newUserData.providedUserID != nil) {
                    newCallbackData.providedUserID = newUserData.providedUserID
                }
                
                if (newUserData.hashedVisitID != nil) {
                    newCallbackData.hashedVisitID = newUserData.hashedVisitID
                }
                
                var shouldPushNewCallbackData = false
                
                for subscriptionComponent in subscription.components {
                    switch (subscriptionComponent) {
                    case .Position:
                        if (newUserData.position != nil) {
                            newCallbackData.position = newUserData.position!
                            shouldPushNewCallbackData = true
                        }
                        break
                    
                    case .OrientationQuat:
                        if (newUserData.orientationQuat != nil) {
                            newCallbackData.orientationQuat = newUserData.orientationQuat!
                            shouldPushNewCallbackData = true
                        }
                        break
                        
                    case .OrientationEuler:
                        if (newUserData.orientationQuat != nil) {
                            newCallbackData.orientationEuler = HiFiUtilities.eulerFromQuaternion(quat: newUserData.orientationQuat!, order: ourHiFiAxisConfiguration.eulerOrder)
                            shouldPushNewCallbackData = true
                        }
                        break
                        
                    case .VolumeDecibels:
                        if (newUserData.volumeDecibels != nil) {
                            newCallbackData.volumeDecibels = newUserData.volumeDecibels!
                            shouldPushNewCallbackData = true
                        }
                        break
                        
                    case .IsStereo:
                        if (newUserData.isStereo != nil) {
                            newCallbackData.isStereo = newUserData.isStereo!
                            shouldPushNewCallbackData = true
                        }
                        break
                    }
                    
                    if (shouldPushNewCallbackData) {
                        currentSubscriptionCallbackData.append(newCallbackData)
                    }
                }
                
                if (currentSubscriptionCallbackData.count > 0) {
                    subscription.callback(currentSubscriptionCallbackData)
                }
            }
        }
    }
            
    
    /**
        A simple wrapper function called by our instantiation of `HiFiMixerSession` that calls the user-provided `onUsersDisconnected()`
        function if one exists.

        Library users can provide an `onUsersDisconnected()` callback function when instantiating the `HiFiCommunicator` object, or by setting
        `HiFiCommunicator.onUsersDisconnected` after instantiation.

        - Parameter usersDisconnected: An Array of `ReceivedHiFiAudioAPIData` regarding the users who disconnected.
    */
    private func _onUsersDisconnected(usersDisconnected: [ReceivedHiFiAudioAPIData]) -> Void {
        if (self.onUsersDisconnected != nil) {
            self.onUsersDisconnected!(usersDisconnected)
        }
    }
    
    /**
        Adds a new User Data Subscription to the list of clientside Subscriptions. User Data Subscriptions are used to obtain User Data about other Users.
        
        Examples:
        
        - If you set up a User Data Subscription for `volumeDecibel` data, the client can perform certain actions when the Server sends data about other users' microphone volumes to your client.
        - If you set up a User Data Subscription for your own User Data, you can use that subscription
        to ensure that the data on the High Fidelity Audio API Server is the same as the data you are sending
        to it from the client.
        
        - Parameter newSubscription: The new `UserDataSubscription` configuration object.
    */
    public func addUserDataSubscription(newSubscription: UserDataSubscription) -> Void {
        if (self._mixerSession!.userDataStreamingScope == .none) {
            HiFiLogger.error("During `HiFiCommunicator` construction, the server was set up to **not** send user data! Data subscription not added.")
            return
        }
        
        HiFiLogger.log("Adding new User Data Subscription:\n\(newSubscription)")
        self._userDataSubscriptions.append(newSubscription)
    }
    
    /// Retrieves the current `HiFiConnectionStates` state.
    public func getHiFiConnectionState() -> HiFiConnectionStates {
        if (self._mixerSession == nil) {
            return .disconnected
        }
        
        return self._mixerSession!.currentHiFiConnectionState
    }
}

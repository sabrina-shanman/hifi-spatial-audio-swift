//
//  RaviSignalingConnection.swift
//  
//
//  Created by zach on 2/24/21.
//

import Foundation
import WebRTC
import Promises
import Starscream

internal enum SignalingStates {
    case connecting, open, error, closing, closed, unavailable
}

internal struct IceResult : Decodable {
    let candidate: String
    let sdpMLineIndex: Int32
    let sdpMid: String
}

internal struct DataResult : Decodable {
    let error: String?
}

internal struct SignalingWebSocketMessageForUUID : Decodable {
    var forUuid: String?
    var sdp: String?
    var ice: IceResult?
    var type: String?
    var turn: TURNConfig?
}

internal class RaviSignalingConnection {
    public var signalingStateChangeHandlers: [String : (SignalingStates) -> Void]
    public var signalingConnectionMessageHandlers: [String : (SignalingWebSocketMessageForUUID) -> Void]
    public var signalingState: SignalingStates
    public var signalingImplementation: RaviSignalingWebSocketImplementation!
    
    public init() {
        self.signalingStateChangeHandlers = [:]
        self.signalingConnectionMessageHandlers = [:]
        
        self.signalingState = SignalingStates.closed
        
        self.signalingImplementation = RaviSignalingWebSocketImplementation(raviSignalingConnection: self)
    }
    
    public func getState() -> SignalingStates {
        return self.signalingState
    }
    
    public func addSignalingStateChangeHandler(changeHandlerID: String, changeHandler:@escaping (SignalingStates) -> Void) -> Void {
        if (self.signalingStateChangeHandlers[changeHandlerID] != nil) {
            HiFiLogger.warn("RaviSignalingConnection: Warning: Replacing existing signaling state change handler with ID '\(changeHandlerID)'")
        } else {
            HiFiLogger.log("RaviSignalingConnection: Adding new signaling state change handler with ID '\(changeHandlerID)'")
        }
        self.signalingStateChangeHandlers[changeHandlerID] = changeHandler
    }
    
    public func removeSignalingStateChangeHandler(changeHandlerID: String) {
        HiFiLogger.log("RaviSignalingConnection: Removing signaling state change handler with ID '\(changeHandlerID)'")
        self.signalingStateChangeHandlers.removeValue(forKey: changeHandlerID)
    }
    
    public func addSignalingMessageHandler(messageHandlerID: String, messageHandler:@escaping (SignalingWebSocketMessageForUUID) -> Void) -> Void {
        if (self.signalingConnectionMessageHandlers[messageHandlerID] != nil) {
            HiFiLogger.warn("RaviSignalingConnection: Warning: Replacing existing message handler with ID '\(messageHandlerID)'")
        } else {
            HiFiLogger.log("RaviSignalingConnection: Adding new message handler with ID '\(messageHandlerID)'")
        }
        self.signalingConnectionMessageHandlers[messageHandlerID] = messageHandler
    }
    
    public func removeSignalingMessageHandler(messageHandlerID: String) -> Void {
        self.signalingConnectionMessageHandlers.removeValue(forKey: messageHandlerID)
    }
    
    public func open(url: String) -> Promise<SignalingStates> {
        return Promise<SignalingStates> { fulfill, reject in
            HiFiLogger.log("RaviSignalingConnection: Opening signaling connection to <URL Redacted>...")
            
            func openStateHandler(newState: SignalingStates) -> Void {
                if (newState == SignalingStates.connecting) {
                    HiFiLogger.log("RaviSignalingConnection: Connecting...")
                } else if (newState == SignalingStates.open) {
                    self.removeSignalingStateChangeHandler(changeHandlerID: "openStateHandler")
                    fulfill(newState)
                } else {
                    self.removeSignalingStateChangeHandler(changeHandlerID: "openStateHandler")
                    reject(NSError(domain: "", code: 1, userInfo: ["state": newState]))
                }
            }
            self.addSignalingStateChangeHandler(changeHandlerID: "openStateHandler", changeHandler: openStateHandler)
            self._handleSignalingStateChange(newState: SignalingStates.connecting)
            self.signalingImplementation._open(socketAddress: url)
        }
    }
    
    public func send(message: String, messageDescriptionForDebug: String?) -> Void {
        self.signalingImplementation._send(message: message, messageDescriptionForDebug: messageDescriptionForDebug)
    }
    
    public func close() -> Promise<SignalingStates> {
        return Promise<SignalingStates> { fulfill, reject in
            HiFiLogger.log("RaviSignalingConnection: Closing signaling connection...")
            self.signalingImplementation._close()
            
            if (self.getState() == .closed) {
                HiFiLogger.log("RaviSignalingConnection: Signaling connection already closed. Fulfilling promise...")
                fulfill(.closed)
                return
            }
            
            func closeStateHandler(newState: SignalingStates) -> Void {
                if (newState == SignalingStates.closing) {
                    HiFiLogger.log("RaviSignalingConnection: Closing...")
                } else if (newState == SignalingStates.closed) {
                    self.removeSignalingStateChangeHandler(changeHandlerID: "closeStateHandler")
                    fulfill(newState)
                } else {
                    self.removeSignalingStateChangeHandler(changeHandlerID: "closeStateHandler")
                    reject(NSError(domain: "", code: 1, userInfo: ["state": newState]))
                }
            }
            self.addSignalingStateChangeHandler(changeHandlerID: "closeStateHandler", changeHandler: closeStateHandler)
            
            self._handleSignalingStateChange(newState: SignalingStates.closing)
        }
    }
    
    func _handleSignalingStateChange(newState: SignalingStates) -> Void {
        if (self.signalingState == newState) {
            return
        }
        
        HiFiLogger.log("RaviSignalingConnection: Signaling state changed to \(newState)")
        self.signalingState = newState
        
        for (id, handler) in self.signalingStateChangeHandlers {
            HiFiLogger.log("RaviSignalingConnection: Calling signalingStateChangeHandler with ID: \(id)")
            handler(newState)
        }
    }
    
    func _handleMessage(message: String) -> Void {
        do {
            if let messageJSON = try JSONSerialization.jsonObject(with: message.data(using: .utf8)!, options: .allowFragments) as? [String : String] {
                if (messageJSON["data"] != nil) {
                    if let messageDataJSON = try JSONSerialization.jsonObject(with: messageJSON["data"]!.data(using: .utf8)!, options: .allowFragments) as? [String : Any] {
                        if (String(describing: messageDataJSON["error"]) == "service-unavailable") {
                            HiFiLogger.error("RaviSignalingConnection: Service unavailable!")
                            self._handleSignalingStateChange(newState: (SignalingStates.unavailable))
                        }
                    }
                }
            }
        } catch { }
        
        let decoder = JSONDecoder()
        do {
            let startOfMessage = message.index(message.startIndex, offsetBy: 40)
            let endOfMessage = message.index(message.endIndex, offsetBy: -1)
            let messageRange = startOfMessage..<endOfMessage
            let truncatedMessage = message[messageRange]
            var decodedTextMessage = try decoder.decode(SignalingWebSocketMessageForUUID.self, from: truncatedMessage.data(using: .utf8)!)
            
            let startOfUUID = message.index(message.startIndex, offsetBy: 2)
            let endOfUUID = message.index(message.startIndex, offsetBy: 38)
            let uuidRange = startOfUUID..<endOfUUID
            decodedTextMessage.forUuid = String(message[uuidRange])
            
            for (_, handler) in self.signalingConnectionMessageHandlers {
                handler(decodedTextMessage)
            }
        } catch {
            HiFiLogger.error("RaviSignalingConnection: Couldn't parse text message transmitted over WebSocket! Message:\n\(message)")
        }
    }
} // End of RaviSignalingConnection

/**
 * A WebSocket implementation for the RaviSignaling class
 * @private
 */
internal class RaviSignalingWebSocketImplementation {
    var _raviSignalingConnection: RaviSignalingConnection
    var _webSocket: WebSocket?
    
    init(raviSignalingConnection: RaviSignalingConnection) {
        self._raviSignalingConnection = raviSignalingConnection
        self._webSocket = nil
    }
    
    func _open(socketAddress: String) {
        var request = URLRequest(url: URL(string: socketAddress)!)
        request.timeoutInterval = 5
        self._webSocket = WebSocket(request: request)
        
        self._webSocket!.onEvent = { event in
            switch event {
            case .connected(_):
                self._raviSignalingConnection._handleSignalingStateChange(newState: SignalingStates.open)
                break
            case .disconnected(_, _):
                self._raviSignalingConnection._handleSignalingStateChange(newState: SignalingStates.closed)
                break
            case .cancelled:
                self._raviSignalingConnection._handleSignalingStateChange(newState: SignalingStates.closed)
                break
            case .error:
                self._raviSignalingConnection._handleSignalingStateChange(newState: SignalingStates.error)
                break
            case .text(let string):
                self._raviSignalingConnection._handleMessage(message: string)
            case .binary(_):
                HiFiLogger.warn("RaviSignalingWebSocketImplementation: Received binary data over WebSocket. No binary data handlers are set up.")
                break
            case .pong(_):
                break
            case .ping(_):
                break
            case .viabilityChanged(_):
                break
            case .reconnectSuggested(_):
                break
            }
        }
        
        self._webSocket!.connect()
    }
    
    func _send(message: String, messageDescriptionForDebug: String?) -> Void {
        if (self._webSocket == nil) {
            return
        }
        
        if (messageDescriptionForDebug != nil) {
            HiFiLogger.log("RaviSignalingWebSocketImplementation: Sending message to signaling server: \(messageDescriptionForDebug!)")
        } else {
            HiFiLogger.log("RaviSignalingWebSocketImplementation: Sending message to signaling server...")
        }
        
        self._webSocket!.write(string: message) {
            if (messageDescriptionForDebug != nil) {
                HiFiLogger.log("RaviSignalingWebSocketImplementation: Sent message to signaling server: \(messageDescriptionForDebug!)")
            } else {
                HiFiLogger.log("RaviSignalingWebSocketImplementation: Sent message to signaling server!")
            }
        }
    }
    
    func _close() -> Void {
        if (self._webSocket == nil) {
            return
        }
        
        self._webSocket!.disconnect()
        self._webSocket = nil
        self._raviSignalingConnection._handleSignalingStateChange(newState: SignalingStates.closed)
    }
}

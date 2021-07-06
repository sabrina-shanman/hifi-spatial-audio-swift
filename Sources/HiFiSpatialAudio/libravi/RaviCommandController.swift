//
//  RaviCommandController.swift
//  
//
//  Created by zach on 2/23/21.
//

import Foundation
import WebRTC

let BINARY_COMMAND_KEY = "_BINARY"

internal struct NonBinaryCommandMessage : Decodable {
    let c: String
    let p: String?
}

internal struct BinaryCommandMessage : Decodable {
    let command: String
    let payload: Data?
}

internal struct RaviCommand {
    public var commandName: String
    public var params: [String : Any]?
    public var commandHandler: RaviCommandHandler?
    
    public init(commandName: String, params: [String : Any]?, commandHandler: RaviCommandHandler?) {
        self.commandName = commandName
        self.params = params
        self.commandHandler = commandHandler
    }
}

internal struct RaviCommandHandler {
    public var commandName: String
    public var handlerFunction: (String?) -> Void
    public var onlyFireOnce: Bool
    
    public init(commandName: String, handlerFunction:@escaping (String?) -> Void, onlyFireOnce: Bool = false) {
        self.commandName = commandName
        self.handlerFunction = handlerFunction
        self.onlyFireOnce = onlyFireOnce
    }
}

internal struct RaviBinaryCommand {
    public var commandName: String
    public var params: [String : Any]?
    public var binaryDataHandler: RaviBinaryDataHandler?
    
    public init(commandName: String, params: [String : Any]?, binaryDataHandler: RaviBinaryDataHandler?) {
        self.commandName = commandName
        self.params = params
        self.binaryDataHandler = binaryDataHandler
    }
}

internal struct RaviBinaryDataHandler {
    public var commandName: String
    public var binaryHandlerFunction: (Data?) -> Void
    public var onlyFireOnce: Bool
    
    public init(commandName: String, binaryHandlerFunction:@escaping (Data?) -> Void, onlyFireOnce: Bool = false) {
        self.commandName = commandName
        self.binaryHandlerFunction = binaryHandlerFunction
        self.onlyFireOnce = onlyFireOnce
    }
}

class RaviRTCDataChannel : NSObject, RTCDataChannelDelegate {
    var rtcDataChannel: RTCDataChannel
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onMessage: ((String) -> Void)?
    var onBinaryMessage: ((Data) -> Void)?
    
    init(
        rtcDataChannel: RTCDataChannel,
        onOpen: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onBinaryMessage: @escaping (Data) -> Void
    ) {
        self.rtcDataChannel = rtcDataChannel
        self.onOpen = onOpen
        self.onClose = onClose
        self.onMessage = onMessage
        self.onBinaryMessage = onBinaryMessage
        super.init()
        self.rtcDataChannel.delegate = self
    }
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        switch dataChannel.readyState {
        case .closed:
            self.onClose!()
            break
        case .closing:
            break
        case .connecting:
            break
        case .open:
            self.onOpen!()
            break
        @unknown default:
            break
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if buffer.isBinary {
            self.onBinaryMessage!(buffer.data)
        } else {
            self.onMessage!(String(data: buffer.data, encoding: String.Encoding.utf8)!)
        }
    }
}

internal class RaviCommandController {
    var _inputDataChannel: RaviRTCDataChannel?
    var _commandDataChannel: RaviRTCDataChannel?
    var commandHandlers: [String : RaviCommandHandler]
    var binaryDataHandlers: [String : RaviBinaryDataHandler]
    
    public init() {
        self._inputDataChannel = nil
        self._commandDataChannel = nil
        self.commandHandlers = [:]
        self.binaryDataHandlers = [:]
    }
    
    public func addCommandHandler(commandName: String, commandHandler: RaviCommandHandler) {
        if (self.commandHandlers[commandName] != nil) {
            HiFiLogger.warn("RaviCommandController: Warning: Replacing existing Command Handler with ID '\(commandName)'")
        } else {
            HiFiLogger.log("RaviCommandController: Adding new Command Handler with ID '\(commandName)'")
        }
        self.commandHandlers[commandName] = commandHandler
    }
    
    public func removeCommandHandler(commandName: String) {
        self.commandHandlers.removeValue(forKey: commandName)
    }
    
    public func addBinaryDataHandler(commandName: String, binaryDataHandler: RaviBinaryDataHandler) {
        if (self.binaryDataHandlers[commandName] != nil) {
            HiFiLogger.warn("RaviCommandController: Warning: Replacing existing Binary Command Handler with ID '\(commandName)'")
        } else {
            HiFiLogger.log("RaviCommandController: Adding new Binary Command Handler with ID '\(commandName)'")
        }
        self.binaryDataHandlers[commandName] = binaryDataHandler
    }
    
    public func removeBinaryCommandHandler(commandName: String) {
        self.binaryDataHandlers.removeValue(forKey: commandName)
    }
    
    public func sendCommand(raviCommand: RaviCommand) -> Bool {
        if (self._commandDataChannel == nil) {
            HiFiLogger.warn("RaviCommandController: Couldn't `sendCommand()`; `_commandDataChannel` is `nil`!\nAttempted to send command:\n\(raviCommand.commandName)")
            return false
        }
        
        let commandChannelReadyState = self._commandDataChannel!.rtcDataChannel.readyState
        if (commandChannelReadyState != .open) {
            HiFiLogger.error("RaviCommandController: Can't send command; Command Channel ready state is \(commandChannelReadyState)")
            return false
        }
        
        let message = _serializeJsonCommandMessageToSend(command: raviCommand.commandName, payload: raviCommand.params ?? nil)
        if (message != nil) {
            if (raviCommand.commandHandler != nil) {
                addCommandHandler(commandName: raviCommand.commandName, commandHandler: raviCommand.commandHandler!)
            }
            
            HiFiLogger.log("RaviCommandController: Sending string command \(message!)...")
            let dataBuffer = RTCDataBuffer(data: Data(message!.utf8), isBinary: false)
            let sendStatus = self._commandDataChannel!.rtcDataChannel.sendData(dataBuffer)
            
            if (sendStatus == true) {
                HiFiLogger.log("RaviCommandController: Sent string command!")
            } else {
                HiFiLogger.error("RaviCommandController: Couldn't send string command!")
            }
            
            return sendStatus
        } else {
            HiFiLogger.error("RaviCommandController: Couldn't serialize JSON command with name \(raviCommand.commandName)!")
        }
        return false
    }
    
    public func sendInput(inputEvent: String) -> Bool {
        if (self._inputDataChannel == nil) {
            HiFiLogger.warn("RaviCommandController: Couldn't `sendInput()`; `_inputDataChannel` is `nil`!")
            return false
        }
        
        let inputChannelReadyState = self._inputDataChannel!.rtcDataChannel.readyState
        if (inputChannelReadyState != .open) {
            HiFiLogger.error("RaviCommandController: Can't send input; Input Channel ready state is \(inputChannelReadyState)")
            return false
        }
        
        // This gets just WAY too noisy too quickly,
        // but uncomment if needed:
        // HiFiLogger.log("RaviCommandController: Sending input:\n\(inputEvent)")
        let dataBuffer = RTCDataBuffer(data: Data(inputEvent.utf8), isBinary: false)
        
        let sendStatus = self._inputDataChannel!.rtcDataChannel.sendData(dataBuffer)
        
        if (sendStatus != true) {
            HiFiLogger.error("RaviCommandController: Couldn't send input data!")
        }
        
        return sendStatus
    }
    
    func _serializeJsonCommandMessageToSend(command: String, payload: [String : Any]?) -> String? {
        var dict = ["c": command] as [String : Any]
        if (payload != nil) {
            dict["p"] = payload
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return String(data: data, encoding: String.Encoding.utf8) ?? nil
        } catch {
            return nil
        }
    }
    
    func _processNonBinaryCommand(fromServerNonBinaryMessage: String) -> Void {
        HiFiLogger.log("RaviCommandController: Processing non-binary command:\n\(fromServerNonBinaryMessage)")
        
        var commandMessage: NonBinaryCommandMessage?
        do {
            let decoder = JSONDecoder()
            commandMessage = try decoder.decode(NonBinaryCommandMessage.self, from: fromServerNonBinaryMessage.data(using: .utf8)!)
            
            let commandString = commandMessage!.c
            if let commandHandler = self.commandHandlers[commandString] {
                let payload = commandMessage!.p
                commandHandler.handlerFunction(payload)
                
                if (commandHandler.onlyFireOnce) {
                    HiFiLogger.log("RaviCommandController: Removing onlyFireOnce command handler...")
                    self.removeCommandHandler(commandName: commandString)
                }
            }
        } catch {
            HiFiLogger.error("RaviCommandController: Message cannot be decoded into a CommandMessage:\n\(fromServerNonBinaryMessage)")
        }
    }
    
    func _processReceivedBinaryData(fromServerBinaryMessage: Data) {
        // Super spammy.
        //HiFiLogger.log("RaviCommandController: Processing binary input data...")
        let inputMessage = BinaryCommandMessage(command: BINARY_COMMAND_KEY, payload: fromServerBinaryMessage)
        // NOTE: Currently, we don't natively include any sort of "command" associated
        // with binary messages -- when we get a binary message, the first binary
        // handler is called. We may decide to rethink this in the future.
        let commandString = inputMessage.command
        if let commandHandler = self.binaryDataHandlers[commandString] {
            let payload = inputMessage.payload
            commandHandler.binaryHandlerFunction(payload)
            
            if (commandHandler.onlyFireOnce) {
                HiFiLogger.log("RaviCommandController: Removing onlyFireOnce command handler...")
                self.removeCommandHandler(commandName: commandString)
            }
        }
    }
    
    func _setInputDataChannel(inputDataChannel: RTCDataChannel) {
        self._inputDataChannel = RaviRTCDataChannel(
            rtcDataChannel: inputDataChannel,
            onOpen: {
                HiFiLogger.log("RaviCommandController: Input Data Channel open. State is: \(self._inputDataChannel!.rtcDataChannel.readyState)")
                
            },
            onClose: {
                HiFiLogger.log("RaviCommandController: Input Data Channel closed. State is: \(self._inputDataChannel!.rtcDataChannel.readyState)")
            },
            onMessage: { (_) in
            },
            onBinaryMessage: { (_) in
            }
        )
        HiFiLogger.log("RaviCommandController: Set new Input Data Channel! ID: \(self._inputDataChannel!.rtcDataChannel.channelId) State: \(self._inputDataChannel!.rtcDataChannel.readyState.rawValue)")
    }
    
    func _setCommandDataChannel(commandDataChannel: RTCDataChannel) {
        self._commandDataChannel = RaviRTCDataChannel(
            rtcDataChannel: commandDataChannel,
            onOpen: {
                HiFiLogger.log("RaviCommandController: Command Data Channel open. State is: \(self._commandDataChannel!.rtcDataChannel.readyState)")
            },
            onClose: {
                HiFiLogger.log("RaviCommandController: Command Data Channel closed. State is: \(self._commandDataChannel!.rtcDataChannel.readyState)")
            },
            onMessage: { (message) in
                self._processNonBinaryCommand(fromServerNonBinaryMessage: message)
            },
            onBinaryMessage: { (binaryMessage) in
                self._processReceivedBinaryData(fromServerBinaryMessage: binaryMessage)
            }
        )
        HiFiLogger.log("RaviCommandController: Set new Command Data Channel! ID: \(self._commandDataChannel!.rtcDataChannel.channelId) State: \(self._commandDataChannel!.rtcDataChannel.readyState.rawValue)")
    }
} // End of the RaviCommandController class

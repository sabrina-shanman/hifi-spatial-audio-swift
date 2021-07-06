//
//  RaviStreamController.swift
//  
//
//  Created by zach on 2/24/21.
//

import Foundation
import WebRTC

internal class RaviStreamController {
    var _commandController: RaviCommandController
    public var audioOutputStream: RTCMediaStream?
    var _onInputAudioTrackChanged: ((RTCAudioTrack?) -> Void)?
    var _inputAudioTrack: RTCAudioTrack?
    var _isStereo: Bool
    
    init(raviCommandController: RaviCommandController) {
        self._commandController = raviCommandController
        self.audioOutputStream = nil
        self._onInputAudioTrackChanged = nil
        self._inputAudioTrack = nil
        self._isStereo = false
    }
    
    public func getOutputAudioStream() -> RTCMediaStream? {
        return self.audioOutputStream
    }
    
    func _setOutputAudioStream(outputAudioStream: RTCMediaStream) {
        self.audioOutputStream = outputAudioStream
    }
    
    public func createAudioInputTrack() -> RTCAudioTrack {
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = RaviWebRTCImplementation.factory.audioSource(with: audioConstraints)
        let audioTrack = RaviWebRTCImplementation.factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }
    
    public func setInputAudioTrack(inputAudioTrack: RTCAudioTrack?, newIsStereo: Bool = false) {
        HiFiLogger.log("RaviStreamController: Setting Input Audio Track...")
        self._inputAudioTrack = inputAudioTrack
        self._isStereo = newIsStereo
        self._onInputAudioTrackChanged!(self._inputAudioTrack)
    }
    
    func setInputAudioTrackChangeHandler(onInputAudioTrackChanged: ((RTCAudioTrack?) -> Void)?) {
        self._onInputAudioTrackChanged = onInputAudioTrackChanged
    }
    
    func isInputAudioStereo() -> Bool {
        return self._isStereo
    }
    
    func _stop() {
        if (self.audioOutputStream != nil) {
            let audioTracks = self.audioOutputStream?.audioTracks.compactMap { $0 as RTCAudioTrack }
            audioTracks!.forEach { $0.isEnabled = false }
            self.audioOutputStream = nil
        }
    }
}

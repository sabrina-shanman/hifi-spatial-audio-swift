//
//  HiFiUserDataSubscription.swift
//  
//
//  Created by zach on 3/10/21.
//

import Foundation

/**
    When adding a new User Data Subscription, a client must specify one of the "components" listed as a part of this `enum`.
    For example, subscribing to `Position` updates ensures that a Subscriber will receive all changes to that user's position.
*/
public enum AvailableUserDataSubscriptionComponents : String {
    case Position = "Position"
    case OrientationEuler = "Orientation (Euler)"
    case OrientationQuat = "Orientation (Quaternion)"
    case VolumeDecibels = "Volume (Decibels)"
    case IsStereo = "IsStereo"
}

/**
    User Data Subscriptions allow client code to perform actions when the client
    receives new User Data from the High Fidelity Audio API Server.
*/
public class UserDataSubscription {
    public var providedUserID: String?
    public var components: [AvailableUserDataSubscriptionComponents] = [AvailableUserDataSubscriptionComponents]()
    public var callback: (([ReceivedHiFiAudioAPIData]) -> Void)
    
    /**
        The `UserDataSubscription` constructor.

        - Parameter providedUserID: The `providedUserID` for the user associated with the Subscription. See `HiFiAudioAPIData`. Optional. If unset, the Subscription callback will be called for all users' data when any users' data changes.
        - Parameter components: The User Data components to which we want to subscribe, such as `Position`, `OrientationEuler`, or `VolumeDecibels`.
        - Parameter callback: The function to call when the client receives new User Data associated with the components or components from the server and the given `providedUserID`.
    */
    public init(providedUserID: String?, components: [AvailableUserDataSubscriptionComponents]?, callback: @escaping (([ReceivedHiFiAudioAPIData]) -> Void)) {
        self.providedUserID = providedUserID
        if (components != nil) {
            self.components = components!
        } else {
            self.components = [
                .OrientationEuler,
                .OrientationQuat,
                .Position,
                .VolumeDecibels,
                .IsStereo
            ]
        }
        self.callback = callback
    }
}

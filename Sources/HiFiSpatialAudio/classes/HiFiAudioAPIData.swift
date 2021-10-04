//
//  HiFiAudioAPIData.swift
//  
//
//  Created by zach on 3/5/21.
//

import Foundation

/// A class which defines a point in three-dimensional space.
public class Point3D {
    /// The `x` component of the point.
    public var x: Double
    /// The `y` component of the point.
    public var y: Double
    /// The `z` component of the point.
    public var z: Double

    /// Initializes a new `Point3D` associated with a certain point in 3D space.
    /// Omitted components will be set to `0`.
    public init(x: Double = 0, y: Double = 0, z: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// A class which defines an orientation in 3D space in Quaternion format.
/// If you'd prefer to use Euler angles, please see the `OrientationEuler3D` class.
public class OrientationQuat3D {
    /// The `w` component of the Quaternion.
    public var w: Double
    /// The `x` component of the Quaternion.
    public var x: Double
    /// The `y` component of the Quaternion.
    public var y: Double
    /// The `z` component of the Quaternion.
    public var z: Double

    /// Initializes a new `OrientationQuat3D` associated with a certain Quaternion orientation in 3D space.
    /// Omitted components will be set to `0`, except for `w`, which will be set to `1`.
    public init(w: Double = 1, x: Double = 0, y: Double = 0, z: Double = 0) {
        self.w = HiFiUtilities.clampNoNaN(v: w, min: -1, max: 1, ifNaN: 1)
        self.x = HiFiUtilities.clampNoNaN(v: w, min: -1, max: 1, ifNaN: 0)
        self.y = HiFiUtilities.clampNoNaN(v: w, min: -1, max: 1, ifNaN: 0)
        self.z = HiFiUtilities.clampNoNaN(v: w, min: -1, max: 1, ifNaN: 0)
    }
}

/// A class which defines an orientation in 3D space in Euler angles.
/// If you'd prefer to use Quaternions, please see the `OrientationQuat3D` class.
public class OrientationEuler3D {
    /// The pitch component of the rotation. Units are degrees.
    public var pitchDegrees: Double
    /// The yawe component of the rotation. Units are degrees.
    public var yawDegrees: Double
    /// The roll component of the rotation. Units are degrees.
    public var rollDegrees: Double
    
    /// Initializes a new `OrientationEuler3D` associated with a certain Euler orientation in 3D space.
    /// Omitted components will be set to `0`.
    public init(pitchDegrees: Double = 0, yawDegrees: Double = 0, rollDegrees: Double = 0) {
        self.pitchDegrees = HiFiUtilities.sanitizeAngleDegrees(v: pitchDegrees)
        self.yawDegrees = HiFiUtilities.sanitizeAngleDegrees(v: yawDegrees)
        self.rollDegrees = HiFiUtilities.sanitizeAngleDegrees(v: rollDegrees)
    }
}

/// Used when setting your application's `HiFiAxisConfiguration`. Defines the order in which Euler orientations are applied.
public enum OrientationEuler3DOrder : String {
    /// Pitch is applied first, then Yaw, then Roll.
    case PitchYawRoll = "PitchYawRoll"
    /// Yaw is applied first, then Pitch, then Roll.
    case YawPitchRoll = "YawPitchRoll"
    /// Roll is applied first, then Pitch, then Yaw.
    case RollPitchYaw = "RollPitchYaw"
    /// Roll is applied first, then Yaw, then Pitch.
    case RollYawPitch = "RollYawPitch"
    /// Yaw is applied first, then Roll, then Pitch.
    case YawRollPitch = "YawRollPitch"
    /// Pitch is applied first, then Roll, then Yaw.
    case PitchRollYaw = "PitchRollYaw"
}

/**
    Instantiations of this class contain all of the data that is possible to **send to *and* receive from** the High Fidelity Audio API Server.

    See `ReceivedHiFiAudioAPIData` for data that can only be received from the Server (i.e. `volumeDecibels`).
*/
public class HiFiAudioAPIData {
    /**
        The position of the user in 3D space.

        ✔ The client sends `position` data to the server when `_transmitHiFiAudioAPIDataToServer()` is called.

        ✔ The server sends `position` data to all clients connected to a server during "peer updates".
    */
    public var position: Point3D?
    /**
        The orientation of the user in Quaternion format.

        ✔ The client sends `orientationQuat` data to the server when `_transmitHiFiAudioAPIDataToServer()` is called.

        ✔ The server sends `orientationQuat` data to all clients connected to a server during "peer updates".
    */
    public var orientationQuat: OrientationQuat3D?
    /**
        The orientation of the user in Euler angles. Units for `OrientationEuler3D` class components are degrees.

        ✔ When using euler representation to update the client orientation, the equivalent Quaternion is evaluated in `_updateUserData()`.

        ✔ When requesting orientation Euler from server updates, the Euler representation is evaluated in `_handleUserDataUpdates()`.
    */
    public var orientationEuler: OrientationEuler3D?
    /**
        The volume threshold associated with a user. Units are decibels. The scale of this value is the same as that of `ReceivedHiFiAudioAPIData.volumeDecibels`.

        A volume level below this value is considered background noise and will be smoothly gated off.
        The floating point value is specified in dBFS (decibels relative to full scale) with values between -96 dB (indicating no gating) and 0 dB (effectively muting the input from this user).
    */
    public var volumeThreshold: Float?
    /**
        This value affects how loud User A will sound to User B at a given distance in 3D space.
        This value also affects the distance at which User A can be heard in 3D space.
        Higher values for User A means that User A will sound louder to other users around User A, and it also means that User A will be audible from a greater distance.
        If you don't supply an `hiFiGain` when constructing instantiations of this class, `hiFiGain` will be `nil`.
        
        ✔ The client sends `hiFiGain` data to the server when `_transmitHiFiAudioAPIDataToServer()` is called.

        ❌ The server does not send `hiFiGain` data to all clients as part of "peer updates".
    */
    public var hiFiGain: Float?
    /**
        This value affects how far a user's sound will travel in 3D space, without affecting the user's loudness.
        By default, there is a global attenuation value (set for a given space) that applies to all users in a space. This default space attenuation is usually 0.5, which represents a reasonable approximation of a real-world fall-off in sound over distance.
        
        Lower numbers represent less attenuation (i.e. sound travels farther); higher numbers represent more attenuation (i.e. sound drops off more quickly).
        
        When setting this value for an individual user, the following holds:
     
        - Positive numbers should be between 0 and 1, and they represent a logarithmic attenuation. This range is recommended, as sounds more natural.
        - Smaller numbers represent less attenuation, so a number such as `0.2` can be used to make a particular user's audio travel farther than other users', for instance in "amplified" concert type settings. Similarly, an extremely small non-zero number (e.g. `0.00001`) can be used to effectively turn off attenuation for a given user within a reasonably sized space, resulting in a "broadcast mode" where the user can be heard throughout most of the space regardless of their location relative to other users.
            - Note: The actual value `0` is used internally to represent the default; for setting minimal attenuation, use small non-zero numbers instead. See also `userRolloff` below.
        - Negative attenuation numbers are used to represent linear attenuation, and are a somewhat artificial, non-real-world concept. However, this setting can be used as a blunt tool to easily test attenuation, and tune it aggressively in extreme circumstances. When using linear attenuation, the setting is the distance in meters at which the audio becomes totally inaudible.
        
        If you don't supply an `userAttenuation` when constructing instantiations of this class, `userAttenuation` will be `nil` and the default will be used.
        
        ✔ The client sends `userAttenuation` data to the server when `_transmitHiFiAudioAPIDataToServer()` is called.
        
        ❌ The server never sends `userAttenuation` data.
     */
    public var userAttenuation: Float?
    /**
        This value represents the progressive high frequency roll-off in meters, a measure of how the higher frequencies in a user's sound are dampened as the user gets further away. By default, there is a global roll-off value (set for a given space), currently 16 meters, which applies to all users in a space. This value represents the distance for a 1kHz rolloff. Values in the range of 12 to 32 meters provide a more "enclosed" sound, in which high frequencies tend to be dampened over distance as they are in the real world.
        
        Generally, you should change roll-off values for the entire space rather than for individual users, but
        extremely high values (e.g. `99999`) may be used in combination with "broadcast mode"-style `userAttenuation` settings to cause the broadcasted voice to sound crisp and "up close" even at very large distances.
        
        If you don't supply an `userRolloff` when constructing instantiations of this class, `userRolloff` will be `nil`.
        
        ✔ The client sends `userRolloff` data to the server when `_transmitHiFiAudioAPIDataToServer()` is called.
        
        ❌ The server never sends `userRolloff` data.
    */
    public var userRolloff: Float?
    /**
        This is an internal class and it is not recommended for normal usage of the API.
        
        See instead `HiFiCommunicator.setOtherUserGainsForThisConnection`, which allows you to set the desired gains for one or more users as perceived by this client only. If you need to perform moderation actions on the server side, use the <https://docs.highfidelity.com/rest/latest/index.html|Administrative REST API>.
        
        Internally, this variable is used to keep track of which other user gain changes need to be sent to the server. The keys are hashed visit IDs, and the values have units of `HiFiGain`.
    */
    public var _otherUserGainQueue: [String : Int]?
    /**
        This is an internal class and it is not recommended for normal usage of the API.
        
        See instead `HiFiAudioAPIData.position`, which allows you to set the position for a client.
        
        Internally, this variable is used to keep track of when the client's position has changed and needs to be sent to the server.
    */
    public var _transformedPosition: Point3D?
    /**
        This is an internal class and it is not recommended for normal usage of the API.
        
        See instead `HiFiAudioAPIData.orientationQuat`, which allows you to set the orientation for a client.
        
        Internally, this variable is used to keep track of when the client's orientation has changed and needs to be sent to the server.
    */
    public var _transformedOrientationQuat: OrientationQuat3D?
    
    public init(
        position: Point3D? = nil,
        orientationQuat: OrientationQuat3D? = nil,
        orientationEuler: OrientationEuler3D? = nil,
        volumeThreshold: Float? = nil,
        hiFiGain: Float? = nil,
        userAttenuation: Float? = nil,
        userRolloff: Float? = nil
    ) {
        self.position = position
        self.orientationQuat = orientationQuat
        self.orientationEuler = orientationEuler
        self.volumeThreshold = volumeThreshold
        self.hiFiGain = hiFiGain
        self.userAttenuation = userAttenuation
        self.userRolloff = userRolloff
    }
}

/**
    Instantiations of this class contain all of the data that is possible to **receive from** the High Fidelity Audio API Server.

    See `HiFiAudioAPIData` for data that can both be sent to and received from the Server (i.e. `position`).
*/
public class ReceivedHiFiAudioAPIData : HiFiAudioAPIData {
    /**
        This User ID is an arbitrary string provided by an application developer which can be used to identify the user associated with a client.

        We recommend that this `providedUserID` is unique across all users, but the High Fidelity API will not enforce uniqueness across clients for this value.
     */
    public var providedUserID: String?
    /**
        This string is a hashed version of the random UUID that is generated automatically.
        
        A connecting client sends this value as the `session` key inside the argument to the `audionet.init` command.
        
        It is used to identify a given client across a cloud of mixers and is guaranteed ("guaranteed" given the context of random UUIDs) to be unique.
        Application developers should not need to interact with or make use of this value, unless they want to use it internally for tracking or other purposes.
        
        This value cannot be set by the application developer.
     */
    public var hashedVisitID: String?
    /**
        The current volume of the user in decibels.
        
        ❌ The client never sends `volumeDecibels` data to the server.
        
        ✔ The server sends `volumeDecibels` data to all clients connected to a server during "peer updates".
     */
    public var volumeDecibels: Float?
    /**
        Indicates that the peer is providing stereo audio.
        
        ✔ The server sends `isStereo` data to all clients connected to a server during "peer updates".
     */
    public var isStereo: Bool?
    
    /// Initializes an instantiation of a `ReceivedHiFiAudioAPIData` class. All values are optional.
    init(
        providedUserID: String?,
        hashedVisitID: String?,
        volumeDecibels: Float?,
        position: Point3D?,
        orientationQuat: OrientationQuat3D?,
        isStereo: Bool?
    ) {
        super.init(position: position, orientationQuat: orientationQuat, orientationEuler: nil, volumeThreshold: nil, hiFiGain: nil, userAttenuation: nil, userRolloff: nil)
        self.providedUserID = providedUserID
        self.hashedVisitID = hashedVisitID
        self.volumeDecibels = volumeDecibels
        self.isStereo = isStereo
    }
}

//
//  HiFiAxisConfiguration.swift
//  
//
//  Created by zach on 3/9/21.
//

import Foundation

/// Enumerates the XYZ 3D axes used in High Fidelity's virtual audio environments.
public enum HiFiAxes : String {
    case PositiveX = "Positive X"
    case NegativeX = "Negative X"
    case PositiveY = "Positive Y"
    case NegativeY = "Negative Y"
    case PositiveZ = "Positive Z"
    case NegativeZ = "Negative Z"
}

/// Used when determining the handedness of your application's coordinate system.
public enum HiFiHandedness : String {
    case RightHand = "Right Hand"
    case LeftHand = "Left Hand"
}

/**
    The axis configuration describes the 3D frame of reference which expresses the position and orientation of the `HifiCommunicator` peers.
    All position and orientation send to and received from from the API calls are expected to be expressed using that space convention.
    On the wire and on the server, the HiFi Spatial Audio system uses a single unified convention called "Mixer Space" which corresponds to the default value of `ourHiFiAxisConfiguration`.

    When converting `OrientationEuler3D` objects to or from the `OrientationQuat3D` representation, the client library relies on the `hiFiAxisConfiguration` argument passed to the `HiFiCommunicator` constructor to apply the expected convention and correct conversion.
    The 'eulerOrder' field of the axis configuration is used for this conversion.

    ⚠ WARNING ⚠ 
    The axis configuration fields (`rightAxis`, `leftAxis`, `intoScreenAxis`, `outOfScreenAxis`, `upAxis`, `downAxis`, `handedness`) are not in use yet. Only the default value for these fields will result in the expected behavior.
    The `eulerOrder` field works correctly and can be configured at the creation of the `HiFiCommunicator`.
 */
public class HiFiAxisConfiguration {
    var rightAxis: HiFiAxes
    var leftAxis: HiFiAxes

    var intoScreenAxis: HiFiAxes
    var outOfScreenAxis: HiFiAxes

    var upAxis: HiFiAxes
    var downAxis: HiFiAxes

    var handedness: HiFiHandedness

    var eulerOrder: OrientationEuler3DOrder

    /// Initialize a new `HiFiAxisConfiguration` class instantiation. All parameters are required.
    init(
        rightAxis: HiFiAxes,
        leftAxis: HiFiAxes,
        intoScreenAxis: HiFiAxes,
        outOfScreenAxis: HiFiAxes,
        upAxis: HiFiAxes,
        downAxis: HiFiAxes,
        handedness: HiFiHandedness,
        eulerOrder: OrientationEuler3DOrder
    ) {
        self.rightAxis = rightAxis
        self.leftAxis = leftAxis
        self.intoScreenAxis = intoScreenAxis
        self.outOfScreenAxis = outOfScreenAxis
        self.upAxis = upAxis
        self.downAxis = downAxis
        self.handedness = handedness
        self.eulerOrder = eulerOrder
    }

    static func verify(axisConfiguration: HiFiAxisConfiguration) -> Bool {
        var isValid = true

        // START left/right axis error checking
        if (axisConfiguration.rightAxis == HiFiAxes.PositiveX && axisConfiguration.leftAxis != HiFiAxes.NegativeX) {
            HiFiLogger.error("Invalid axis configuration!\nRight Axis is \(axisConfiguration.rightAxis), and Left Axis is \(axisConfiguration.leftAxis)!")
            isValid = false
        }
        if (axisConfiguration.leftAxis == HiFiAxes.PositiveX && axisConfiguration.rightAxis != HiFiAxes.NegativeX) {
            HiFiLogger.error("Invalid axis configuration!\nRight Axis is \(axisConfiguration.rightAxis), and Left Axis is \(axisConfiguration.leftAxis)!")
            isValid = false
        }

        if (axisConfiguration.rightAxis == HiFiAxes.PositiveY && axisConfiguration.leftAxis != HiFiAxes.NegativeY) {
            HiFiLogger.error("Invalid axis configuration!\nRight Axis is \(axisConfiguration.rightAxis), and Left Axis is \(axisConfiguration.leftAxis)!")
            isValid = false
        }
        if (axisConfiguration.leftAxis == HiFiAxes.PositiveY && axisConfiguration.rightAxis != HiFiAxes.NegativeY) {
            HiFiLogger.error("Invalid axis configuration!\nRight Axis is \(axisConfiguration.rightAxis), and Left Axis is \(axisConfiguration.leftAxis)!")
            isValid = false
        }

        if (axisConfiguration.rightAxis == HiFiAxes.PositiveZ && axisConfiguration.leftAxis != HiFiAxes.NegativeZ) {
            HiFiLogger.error("Invalid axis configuration!\nRight Axis is \(axisConfiguration.rightAxis), and Left Axis is \(axisConfiguration.leftAxis)!")
            isValid = false
        }
        if (axisConfiguration.leftAxis == HiFiAxes.PositiveZ && axisConfiguration.rightAxis != HiFiAxes.NegativeZ) {
            HiFiLogger.error("Invalid axis configuration!\nRight Axis is \(axisConfiguration.rightAxis), and Left Axis is \(axisConfiguration.leftAxis)!")
            isValid = false
        }
        // END left/right axis error checking

        // START into-screen/out-of-screen axis error checking
        if (axisConfiguration.intoScreenAxis == HiFiAxes.PositiveX && axisConfiguration.outOfScreenAxis != HiFiAxes.NegativeX) {
            HiFiLogger.error("Invalid axis configuration!\nIntoScreen Axis is \(axisConfiguration.intoScreenAxis), and OutOfScreen is \(axisConfiguration.outOfScreenAxis)!")
            isValid = false
        }
        if (axisConfiguration.outOfScreenAxis == HiFiAxes.PositiveX && axisConfiguration.intoScreenAxis != HiFiAxes.NegativeX) {
            HiFiLogger.error("Invalid axis configuration!\nOutOfScreen is \(axisConfiguration.intoScreenAxis), and IntoScreen Axis is \(axisConfiguration.outOfScreenAxis)!")
            isValid = false
        }

        if (axisConfiguration.intoScreenAxis == HiFiAxes.PositiveY && axisConfiguration.outOfScreenAxis != HiFiAxes.NegativeY) {
            HiFiLogger.error("Invalid axis configuration!\nIntoScreen is \(axisConfiguration.intoScreenAxis), and OutOfScreen is \(axisConfiguration.outOfScreenAxis)!")
            isValid = false
        }
        if (axisConfiguration.outOfScreenAxis == HiFiAxes.PositiveY && axisConfiguration.intoScreenAxis != HiFiAxes.NegativeY) {
            HiFiLogger.error("Invalid axis configuration!\nOutOfScreen Axis is \(axisConfiguration.intoScreenAxis), and IntoScreen Axis is \(axisConfiguration.outOfScreenAxis)!")
            isValid = false
        }

        if (axisConfiguration.intoScreenAxis == HiFiAxes.PositiveZ && axisConfiguration.outOfScreenAxis != HiFiAxes.NegativeZ) {
            HiFiLogger.error("Invalid axis configuration!\nIntoScreen Axis is \(axisConfiguration.intoScreenAxis), and OutOfScreen Axis is \(axisConfiguration.outOfScreenAxis)!")
            isValid = false
        }
        if (axisConfiguration.outOfScreenAxis == HiFiAxes.PositiveZ && axisConfiguration.intoScreenAxis != HiFiAxes.NegativeZ) {
            HiFiLogger.error("Invalid axis configuration!\nOutOfScreen Axis is \(axisConfiguration.intoScreenAxis), and IntoScreen Axis is \(axisConfiguration.outOfScreenAxis)!")
            isValid = false
        }
        // END into-screen/out-of-screen axis error checking

        // START up/down axis error checking
        if (axisConfiguration.upAxis == HiFiAxes.PositiveX && axisConfiguration.downAxis != HiFiAxes.NegativeX) {
            HiFiLogger.error("Invalid axis configuration!\nUp Axis is \(axisConfiguration.upAxis), and Down Axis is \(axisConfiguration.downAxis)!")
            isValid = false
        }
        if (axisConfiguration.downAxis == HiFiAxes.PositiveX && axisConfiguration.upAxis != HiFiAxes.NegativeX) {
            HiFiLogger.error("Invalid axis configuration!\nUp Axis is \(axisConfiguration.upAxis), and Down Axis is \(axisConfiguration.downAxis)!")
            isValid = false
        }

        if (axisConfiguration.upAxis == HiFiAxes.PositiveY && axisConfiguration.downAxis != HiFiAxes.NegativeY) {
            HiFiLogger.error("Invalid axis configuration!\nUp Axis is \(axisConfiguration.upAxis), and Down Axis is \(axisConfiguration.downAxis)!")
            isValid = false
        }
        if (axisConfiguration.downAxis == HiFiAxes.PositiveY && axisConfiguration.upAxis != HiFiAxes.NegativeY) {
            HiFiLogger.error("Invalid axis configuration!\nDown Axis is \(axisConfiguration.upAxis), and Up Axis is \(axisConfiguration.downAxis)!")
            isValid = false
        }

        if (axisConfiguration.upAxis == HiFiAxes.PositiveZ && axisConfiguration.downAxis != HiFiAxes.NegativeZ) {
            HiFiLogger.error("Invalid axis configuration!\nUp Axis is \(axisConfiguration.upAxis), and Down Axis is \(axisConfiguration.downAxis)!")
            isValid = false
        }
        if (axisConfiguration.downAxis == HiFiAxes.PositiveZ && axisConfiguration.upAxis != HiFiAxes.NegativeZ) {
            HiFiLogger.error("Invalid axis configuration!\nDown Axis is \(axisConfiguration.upAxis), and Up Axis is \(axisConfiguration.downAxis)!")
            isValid = false
        }
        // END up/down axis error checking

        if (!(axisConfiguration.handedness == HiFiHandedness.RightHand || axisConfiguration.handedness == HiFiHandedness.LeftHand)) {
            HiFiLogger.error("Invalid axis configuration!\nHandedness is \(axisConfiguration.handedness)!")
            isValid = false
        }

        return isValid
    }

    /**
        ⚠ WARNING ⚠ The code in this function IS wrong.
        TODO: implement the function, just a NO OP at the moment.

        - Parameter axisConfiguration
        - Parameter inputPoint3D
     */
    static func translatePoint3DToMixerSpace(axisConfiguration: HiFiAxisConfiguration, inputPoint3D: Point3D) -> Point3D {
        var retval = Point3D()
        retval = inputPoint3D
        return retval
    }

    /**
        ⚠ WARNING ⚠ The code in this function IS wrong.
        TODO: implement the function, just a NO OP at the moment.

        - Parameter axisConfiguration
        - Parameter inputOrientationQuat3D
     */
    static func translatePoint3DFromMixerSpace(axisConfiguration: HiFiAxisConfiguration, mixerPoint3D: Point3D) -> Point3D {
        var retval = Point3D()
        retval = mixerPoint3D
        return retval
    }

    /**
        ⚠ WARNING ⚠ The code in this function IS wrong.
        TODO: implement the function, just a NO OP at the moment.

        - Parameter axisConfiguration
        - Parameter inputOrientationQuat3D
     */
    static func translateOrientationQuat3DToMixerSpace(axisConfiguration: HiFiAxisConfiguration, inputOrientationQuat3D: OrientationQuat3D) -> OrientationQuat3D {
        var retval = OrientationQuat3D()
        retval = inputOrientationQuat3D
        return retval
    }

    /**
        ⚠ WARNING ⚠ The code in this function IS wrong.
        TODO: implement the function, just a NO OP at the moment.

        - Parameter axisConfiguration
        - Parameter inputOrientationQuat3D
     */
    static func translateOrientationQuat3DFromMixerSpace(axisConfiguration: HiFiAxisConfiguration, mixerOrientationQuat3D: OrientationQuat3D) -> OrientationQuat3D {
        var retval = OrientationQuat3D()
        retval = mixerOrientationQuat3D
        return retval
    }
}

/**
    Contains the application's 3D axis configuration. By default:

    - `+x` is to the right and `-x` is to the left
    - `+y` is up and `-y` is down
    - `+z` is back and `-z` is front
    - The coordinate system is right-handed.
    - Euler order is `OrientationEuler3DOrder.YawPitchRoll`
 */
var ourHiFiAxisConfiguration = HiFiAxisConfiguration(rightAxis: .PositiveX, leftAxis: .NegativeX, intoScreenAxis: .PositiveZ, outOfScreenAxis: .NegativeZ, upAxis: .PositiveY, downAxis: .NegativeY, handedness: .RightHand, eulerOrder: .YawPitchRoll)

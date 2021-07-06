//
//  HiFiUtilities.swift
//  
//
//  Created by zach on 3/9/21.
//

import Foundation

/**
    Various utility functions used by the Swift Client Library. Developers may find them useful as well, so they are all `public`.
*/
public class HiFiUtilities {
    /// Ensures that a number isn't `NaN`.
    public static func noNaN(v: Double, ifNaN: Double) -> Double {
        return (v.isNaN ? ifNaN : v)
    }
    
    /// Ensures that a number is between `min` and `max`.
    public static func clamp<T: FloatingPoint>(v: T, min: T, max: T) -> T {
        // if v is NaN, returns NaN
        return (v > max ? max : (v < min ? min : v))
    }
    
    /// Ensures that a number is between `min` and `max`. Never returns `NaN`.
    public static func clampNoNaN(v: Double, min: Double, max: Double, ifNaN: Double) -> Double {
        return (v > max ? max : ( v < min ? min : self.noNaN(v: v, ifNaN: ifNaN)))
    }
    
    /// Clamps a number between `-1.0` and `+1.0`. Can return `NaN`.
    public static func clampNormalized(v: Double) -> Double {
        // If `v` is `NaN`, returns `NaN`
        return v > 1.0 ? 1.0 : (v < -1.0 ? -1.0 : v)
    }
    
    /// Ensures that a given angle in degrees is represented numerically between `-360.0` and `+360.0` degrees.
    public static func sanitizeAngleDegrees(v: Double) -> Double {
        if (v.isNaN || v == Double.infinity) {
            return 0
        } else if (v == -Double.infinity) {
            return -0
        } else {
            return v.truncatingRemainder(dividingBy: 360)
        }
    }
    
    /// Translates Euler angles to Quaternions.
    public static func eulerToQuaternion(euler: OrientationEuler3D, order: OrientationEuler3DOrder) -> OrientationQuat3D {
        // Compute the individual euler angle rotation quaternion terms sin(angle/2) and cos(angle/2)
        let HALF_DEG_TO_RAD = 0.5 * Double.pi / 180.0
        let cosP = cos(euler.pitchDegrees * HALF_DEG_TO_RAD)
        let cosY = cos(euler.yawDegrees * HALF_DEG_TO_RAD)
        let cosR = cos(euler.rollDegrees * HALF_DEG_TO_RAD)
        let sinP = sin(euler.pitchDegrees * HALF_DEG_TO_RAD)
        let sinY = sin(euler.yawDegrees * HALF_DEG_TO_RAD)
        let sinR = sin(euler.rollDegrees * HALF_DEG_TO_RAD)
        
        // the computed quaternion components for the 6 orders are based on the same pattern
        // q.x = ax +/- bx
        // q.y = ay +/- by
        // q.z = az +/- bz
        // q.w = aw +/- bw
        
        let ax = sinP * cosY * cosR
        let ay = cosP * sinY * cosR
        let az = cosP * cosY * sinR
        let aw = cosP * cosY * cosR
        
        let bx = cosP * sinY * sinR
        let by = sinP * cosY * sinR
        let bz = sinP * sinY * cosR
        let bw = sinP * sinY * sinR
        
        let retQuat = OrientationQuat3D()
        
        switch (order) {
        // from 'base' space rotate Pitch, then Yaw then Roll
        // Resulting rotation is defining the 'rotated' space relative to the 'base' space.
        // A vector Vr in "rotated' space and its equivalent value Vb in the'base' space is computed as follows:
        // Vb = [P][Y][R] Vr
        case .PitchYawRoll:
            retQuat.w = aw - bw
            retQuat.x = ax + bx
            retQuat.y = ay - by
            retQuat.z = az + bz
            break
        
        // From 'base' space rotate Yaw, then Pitch then Roll...
        case .YawPitchRoll:
            retQuat.w = aw + bw
            retQuat.x = ax + bx
            retQuat.y = ay - by
            retQuat.z = az - bz
            break
        
        // From 'base' space rotate Roll, then Pitch then Yaw...
        case .RollPitchYaw:
            retQuat.w = aw - bw
            retQuat.x = ax - bx
            retQuat.y = ay + by
            retQuat.z = az + bz
            break
        
        // From 'base' space rotate Roll, then Yaw then Pitch...
        case .RollYawPitch:
            retQuat.w = aw + bw
            retQuat.x = ax - bx
            retQuat.y = ay + by
            retQuat.z = az - bz
            break
        
        // From 'base' space rotate Yaw, then Roll then Pitch...
        case .YawRollPitch:
            retQuat.w = aw - bw
            retQuat.x = ax + bx
            retQuat.y = ay + by
            retQuat.z = az - bz
            break
        
        // From 'base' space rotate Pitch, then Roll then Yaw...
        case .PitchRollYaw:
            retQuat.w = aw + bw
            retQuat.x = ax - bx
            retQuat.y = ay - by
            retQuat.z = az + bz
            break
        }
        return retQuat
    }
    
    /// Translates Quaternions to Euler angles.
    public static func eulerFromQuaternion(quat: OrientationQuat3D, order: OrientationEuler3DOrder) -> OrientationEuler3D {
        // We need to convert the quaternion to the equivalent mat3x3
        let qx2 = quat.x * quat.x
        let qy2 = quat.y * quat.y
        let qz2 = quat.z * quat.z
        // let qw2 = quat.w * quat.w; we could choose to use it instead of the 1 - 2* term...
        let qwx = quat.w * quat.x
        let qwy = quat.w * quat.y
        let qwz = quat.w * quat.z
        let qxy = quat.x * quat.y
        let qyz = quat.y * quat.z
        let qxz = quat.z * quat.x
        // ROT Mat33 =  {  1 - 2qy2 - 2qz2  |  2(qxy - qwz)    |  2(qxz + qwy)  }
        //              {  2(qxy + qwz)     |  1 - 2qx2 - 2qz2 |  2(qyz - qwx)  }
        //              {  2(qxz - qwy)     |  2(qyz + qwx)    |  1 - 2qx2 - 2qy2  }
        let r00 = 1.0 - 2.0 * (qy2 + qz2)
        let r10 = 2.0 * (qxy + qwz)
        let r20 = 2.0 * (qxz - qwy)
        
        let r01 = 2.0 * (qxy - qwz)
        let r11 = 1.0 - 2.0 * (qx2 + qz2)
        let r21 = 2.0 * (qyz + qwx)
        
        let r02 = 2.0 * (qxz + qwy)
        let r12 = 2.0 * (qyz - qwx)
        let r22 = 1.0 - 2.0 * (qx2 + qy2)
        
        // then depending on the euler rotation order decomposition, we extract the angles
        // from the base vector components
        var pitch = 0.0
        var yaw = 0.0
        var roll = 0.0
        
        let ONE_MINUS_EPSILON = 0.9999999
        
        switch (order) {
        case .PitchYawRoll:
            yaw = asin(HiFiUtilities.clampNormalized(v: r02))
            if ( abs( r02 ) < ONE_MINUS_EPSILON ) {
                pitch = atan2( -r12, r22)
                roll = atan2( -r01, r00)
            } else {
                pitch = atan2(r21, r11)
            }
            break
        case OrientationEuler3DOrder.YawPitchRoll:
            pitch = asin(HiFiUtilities.clampNormalized(v: -r12))
            if ( abs( r12 ) < ONE_MINUS_EPSILON ) {
                yaw = atan2(r02, r22)
                roll = atan2(r10, r11)
            } else {
                yaw = atan2(-r20, r00)
            }
            break
        case OrientationEuler3DOrder.RollPitchYaw:
            pitch = asin(HiFiUtilities.clampNormalized(v: r21))
            if ( abs( r21 ) < ONE_MINUS_EPSILON ) {
                yaw = atan2(-r20, r22)
                roll = atan2(-r01, r11)
            } else {
                roll = atan2(r10, r00)
            }
            break
        case OrientationEuler3DOrder.RollYawPitch:
            yaw = asin(HiFiUtilities.clampNormalized(v: -r20))
            if ( abs( r20 ) < ONE_MINUS_EPSILON ) {
                pitch = atan2( r21, r22)
                roll = atan2( r10, r00)
            } else {
                roll = atan2( -r01, r11)
            }
            break
        case OrientationEuler3DOrder.YawRollPitch:
            roll = asin(HiFiUtilities.clampNormalized(v: r10))
            if ( abs( r10 ) < ONE_MINUS_EPSILON ) {
                pitch = atan2( -r12, r11)
                yaw = atan2( -r20, r00)
            } else {
                yaw = atan2( r02, r22)
            }
            break
        case OrientationEuler3DOrder.PitchRollYaw:
            roll = asin(HiFiUtilities.clampNormalized(v: -r01))
            if ( abs( r01 ) < ONE_MINUS_EPSILON ) {
                pitch = atan2( r21, r11)
                yaw = atan2( r02, r00)
            } else {
                yaw = atan2( -r12, r22)
            }
            break
        }
        
        let RAD_TO_DEG = 180.0 / Double.pi
        
        return OrientationEuler3D(pitchDegrees: RAD_TO_DEG * pitch, yawDegrees: RAD_TO_DEG * yaw, rollDegrees: RAD_TO_DEG * roll)
    }
    
    /// Linearly scales a number between two output values given a minimum input value and maximum input value.
    public static func linearScale<T: FloatingPoint>(factor: T, minInput: T, maxInput: T, minOutput: T, maxOutput: T) -> T {
        let newFactor = clamp(v: factor, min: minInput, max: maxInput)
        
        return minOutput + (maxOutput - minOutput) * (newFactor - minInput) / (maxInput - minInput)
    }
}

//
//  RaviUtils.swift
//  
//
//  Created by zach on 2/24/21.
//

import Foundation

internal class RaviUtils {
    /**
     * Simple UUID implementation.
     * Taken from http://stackoverflow.com/a/105074/515584
     * Strictly speaking, it's not a real UUID, but it gives us what we need
     * for RAVI handling.
     */
    static func createUUID() -> String {
        func s4() -> String {
            return String(format: "%04x", Int.random(in: 1..<0x10000))
        }
        
        return s4() + s4() + "-" + s4() + "-" + s4() + "-" + s4() + "-" + s4() + s4() + s4()
    }
}

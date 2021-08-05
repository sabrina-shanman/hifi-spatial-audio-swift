//
//  HiFiConstants.swift
//  
//
//  Created by zach on 3/10/21.
//

import Foundation


/**
    Defines a number of constants used throughout the API code.
*/
public class HiFiConstants {
    /**
        Defines the minimum amount of time that must pass between API transmission
        of data from the client to the server.
    */
    static public let MIN_TRANSMIT_RATE_LIMIT_TIMEOUT_MS: Int = 10
    /**
        Defines the default amount of time that must pass between API transmission
        of data from the client to the server.
    */
    static public let DEFAULT_TRANSMIT_RATE_LIMIT_TIMEOUT_MS: Int = 50
    /**
        The production endpoint for connections between client and High Fidelity Audio API Server.
    */
    static public let DEFAULT_SIGNALING_HOST_URL: String = "api.highfidelity.com"
    /**
        The production port for connections between client and High Fidelity Audio API Server.
    */
    static public let DEFAULT_SIGNALING_PORT: Int = 443
}

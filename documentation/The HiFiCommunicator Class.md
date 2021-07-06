# The `HiFiCommunicator` Class

Instantiations of the `HiFiCommunicator` class contain the methods used to communicate with the High Fidelity Audio API servers. For example:

```swift
import HiFiSpatialAudio

let communicator = HiFiCommunicator()
communicator.connectToHiFiAudioAPIServer(hifiAuthJWT: <your JWT>)
```

After a successful connection, you can perform actions such as updating the client's position in the virtual audio environment:

```swift
let audioAPIData = HiFiAudioAPIData(position: Point3D(x: 5, y: 0, z: -3))
communicator.updateUserDataAndTransmit(newUserData: audioAPIData)
```

Running the code above would update the client's position in the 3D virtual audio environment to `(5, 0, -3)`.


## Examples
For example code, check out [the `Test Apps` subdirectory of the `hifi-spatial-audio-swift` GitHub repository.](https://github.com/highfidelity/hifi-spatial-audio-swift/tree/main/Test%20Apps) All of the sample apps run on an iPhone Simulator via XCode and on real iOS hardware.

- The `HiFiSpatialAudioTest` app is the simplest, most straightforward, and closest to "production-ready".
- The `HiFiUnionSquare` app is a complex app which uses device sensor fusion to place your avatar on a map of Union Square. Your avatar's position and orientation are driven by your phone's real-world position and orientation.
- The **(unfinished)** `HiFiPlace` app shows your avatar and other avatars on a map.

## Additional Information
For more example code, guides, and other support, please [visit our website at https://highfidelity.com.](https://highfidelity.com)

# Please read all of the below before continuing.

# hifi-spatial-audio-swift

The `HiFiSpatialAudio` Swift Package is a Swift version of High Fidelity's Spatial Audio client library for TypeScript. [Click here to access documentation for the TypeScript version of our client library.](https://docs.highfidelity.com/js/latest/index.html)

The goal of this project is to mirror the functionality of the TypeScript library for iOS applications. However, you may find that not all features from the TS client library are present in the Swift client library. Additionally, some functionality may be different, and some functionality may be buggy.

You can explore some of the features of the Swift client library by compiling and running any of the included Test Apps in [./Test Apps](the Test Apps subdirectory of this repository). All of the sample apps run on an iPhone Simulator via XCode and on real iOS hardware.
- The `HiFiSpatialAudioTest` app is the simplest, most straightforward, and closest to "production-ready".
- The `HiFiUnionSquare` app is a complex app which uses device sensor fusion to place your avatar on a map of Union Square. Your avatar's position and orientation are driven by your phone's real-world position and orientation.
- The **(unfinished)** `HiFiPlace` app shows your avatar and other avatars on a map.

## Usage in Your iOS Apps
If you'd like to make use of the `HiFiSpatialAudio` Swift Package in your iOS apps:
1. Open your iOS app's code in XCode.
2. Create a `Frameworks` group inside your XCode project if one doesn't already exist.
3. Drag the `hifi-spatial-audio-swift` directory into the `Frameworks` folder in your Project Navigator. You should end up with a Project Navigator which looks something like this:
    
    <img src="./usage.png" height="280" alt="A screenshot of XCode showing the `hifi-spatial-audio-swift` framework installed.">

## Package Dependencies
The `HiFiSpatialAudio` package relies on several Swift Package Dependencies, all of which should be automatically downloaded before your project is built.

These Swift Package Dependencies include:
- `Gzip` (for un-gzipping binary peer data sent from the mixer)
- `Promises` (for JavaScript-like Promises)
- `Starscream` (for Web Sockets)
- A custom version of `WebRTC` for iOS, which includes stereo output support (for...WebRTC stuff)

## Audio Peripherals and Bluetooth

By default, the `HiFiSpatialAudio` Swift package will automatically use whatever stereophonic headphones or AirPods that may be connected by wire or by Bluetooth, using the Apple-defined behavior of “last peripheral connected, wins”. If there is no such stereo peripheral connected, the two speakers on the phone are used, where the “bottom” speaker is the left channel, and the “top” speaker is the right channel. The phone microphone is used.

The constructor for the `HiFiCommunicator` object also accepts a boolean named argument called `echoCancellingVoiceProcessingInMono`, which instead uses hardware echo cancellation and automatic gain control, but the ouput is monophonic and of “speech” quality. In this mode, wireless peripherals are connected via the “hands-free” Bluetooth mode. In this mode, if the wireless hardware contains a microphone, that microphone will be used for audio input.

## Generating Documentation

First, install Jazzy with `gem install jazzy` from a Terminal window.

Then, run the following command from the repository directory to generate documentation for the `HiFiSpatialAudio` Swift package:

```
jazzy
```

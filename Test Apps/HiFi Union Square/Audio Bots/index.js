const { MediaStream, nonstandard: { RTCAudioSource } } = require('wrtc'); // Used to create the `MediaStream` containing your DJ Bot's audio.
const fs = require('fs'); // Used to read the specified audio file from your local disk.
const path = require('path'); // Used to verify that the specified audio file is an MP3 or WAV file.
const decode = require('audio-decode'); // Used to decode the audio file present on your local disk.
const format = require('audio-format'); // Allows us to retrieve available format properties from an audio-like object, such as our `AudioBuffer`.
const convert = require('pcm-convert'); // Allows us to convert our `AudioBuffer` into the proper `int16` format.
import { Point3D, OrientationEuler3D, HiFiAudioAPIData, HiFiCommunicator, preciseInterval } from 'hifi-spatial-audio'; // Used to interface with the Spatial Audio API.
const auth = require("./auth.json");

/**
 * Play the audio from a file into a High Fidelity Space. The audio will loop indefinitely.
 *
 * @param {string} audioPath - Path to an `.mp3` or `.wav` audio file
 * @param {object} position - The {x, y, z} point at which to spatialize the audio.
 * @param {number} hiFiGain - Set above 1 to boost the volume of the bot, or set below 1 to attenuate the volume of the bot.
 */
async function startHiFiUnionSquareAudioBot(botName, audioPath, position, orientationEuler, hiFiGain) {
    // Make sure we've been passed an `audioPath`...
    console.log(`${botName}: Audio file path: ${audioPath}`);

    // Make sure the `audioPath` we've been passed is actually a file that exists on the filesystem...
    if (!fs.statSync(audioPath).isFile()) {
        console.error(`Specified path "${audioPath}" is not a file!`);
        return;
    }

    // Make sure that the file at `audioPath` is a `.mp3` or a `.wav` file.
    let audioFileExtension = path.extname(audioPath).toLowerCase();
    if (!(audioFileExtension === ".mp3" || audioFileExtension === ".wav")) {
        console.error(`Specified audio file must be a \`.mp3\` or a \`.wav\`!\nInstead, it's a \`${audioFileExtension}\``);
        return;
    }

    // Read the audio file from our local filesystem into a file buffer.
    const fileBuffer = fs.readFileSync(audioPath),
        // Decode the audio file buffer into an AudioBuffer object.
        audioBuffer = await decode(fileBuffer),
        // Obtain various necessary pieces of information about the audio file.
        { numberOfChannels, sampleRate, length, duration } = audioBuffer,
        // Get the correct format of the `audioBuffer`.
        parsed = format.detect(audioBuffer),
        // Convert the parsed `audioBuffer` into the proper format.
        convertedAudioBuffer = convert(audioBuffer, parsed, 'int16'),
        // Define the number of bits per sample encoded into the original audio file. `16` is a commonly-used number. The DJ Bot may malfunction
        // if the audio file specified is encoded using a different number of bits per sample.
        BITS_PER_SAMPLE = 16,
        // Define the interval at which we want to fill the sample data being streamed into the `MediaStream` sent up to the Server.
        // `wrtc` expects this to be 10ms.
        TICK_INTERVAL_MS = 10,
        // There are 1000 milliseconds per second :)
        MS_PER_SEC = 1000,
        // The number of times we fill up the audio buffer per second.
        TICKS_PER_SECOND = MS_PER_SEC / TICK_INTERVAL_MS,
        // The number of audio samples present in the `MediaStream` audio buffer per tick.
        SAMPLES_PER_TICK = sampleRate / TICKS_PER_SECOND,
        // Contains the audio sample data present in the `MediaStream` audio buffer sent to the Server.
        currentSamples = new Int16Array(numberOfChannels * SAMPLES_PER_TICK),
        // Contains all of the data necessary to pass to our `RTCAudioSource()`, which is sent to the Server.
        currentAudioData = { samples: currentSamples, sampleRate, bitsPerSample: BITS_PER_SAMPLE, channelCount: numberOfChannels, numberOfFrames: SAMPLES_PER_TICK },
        // The `MediaStream` sent to the server consists of an "Audio Source" and, within that Source, a single "Audio Track".
        source = new RTCAudioSource(),
        track = source.createTrack(),
        // This is the final `MediaStream` sent to the server. The data within that `MediaStream` will be updated on an interval.
        inputAudioMediaStream = new MediaStream([track]),
        // Define the initial HiFi Audio API Data used when connecting to the Spatial Audio API.
        initialAudioData = new HiFiAudioAPIData({
            position: new Point3D(position),
            orientationEuler: new OrientationEuler3D(orientationEuler),
            hiFiGain: hiFiGain
        }),
        // Set up the HiFiCommunicator used to communicate with the Spatial Audio API.
        hifiCommunicator = new HiFiCommunicator({ initialHiFiAudioAPIData: initialAudioData });

    // Set the Input Audio Media Stream to the `MediaStream` we created above. We'll fill it up with data below.
    await hifiCommunicator.setInputAudioMediaStream(inputAudioMediaStream);

    // `sampleNumber` defines where we are in the decoded audio stream from above. `0` means "we're at the beginning of the audio file".
    let sampleNumber = 0;
    // Called once every `TICK_INTERVAL_MS` milliseconds.
    let tick = () => {
        // This `for()` loop fills up `currentSamples` with the right amount of raw audio data grabbed from the correct position
        // in the decoded audio file.
        for (let frameNumber = 0; frameNumber < SAMPLES_PER_TICK; frameNumber++, sampleNumber++) {
            for (let channelNumber = 0; channelNumber < numberOfChannels; channelNumber++) {
                currentSamples[frameNumber * numberOfChannels + channelNumber] = convertedAudioBuffer[sampleNumber * numberOfChannels + channelNumber] || 0;
            }
        }

        // This is the function that actually modifies the `MediaStream` we're sending to the Server.
        source.onData(currentAudioData);

        // Check if we're at the end of our audio file. If so, reset the `sampleNumber` so that we loop.
        if (sampleNumber > length) {
            sampleNumber = 0;
        }
    }

    // Generate the JWT used to connect to our High Fidelity Space.
    let hiFiJWT = auth.HIFI_JWT;
    if (!hiFiJWT) {
        return;
    }

    // Connect to our High Fidelity Space.
    let connectResponse;
    try {
        connectResponse = await hifiCommunicator.connectToHiFiAudioAPIServer(hiFiJWT);
    } catch (e) {
        console.error(`Call to \`connectToHiFiAudioAPIServer()\` failed! Error:\n${JSON.stringify(e)}`);
        return;
    }

    // Set up the `preciseInterval` used to regularly update the `MediaStream` we're sending to the Server.
    preciseInterval(tick, TICK_INTERVAL_MS);

    console.log(`${botName}: AudioBot connected.`);
}

const unionSquareCenter = {
    lat: 37.78791580632116,
    lon: -122.40751566482355
};

const EARTH_RADIUS_M = 6370000;
const AUDIO_ENVIRONMENT_SCALE_FACTOR = 0.75;
function point3DFromLatLon(latitude, longitude, startingLatitude, startingLongitude) {
    const dx = (EARTH_RADIUS_M * longitude * Math.PI / 180 * Math.cos(startingLatitude * Math.PI / 180)) - (EARTH_RADIUS_M * startingLongitude * Math.PI / 180 * Math.cos(startingLatitude * Math.PI / 180));
    const dy = (EARTH_RADIUS_M * latitude * Math.PI / 180) - (EARTH_RADIUS_M * startingLatitude * Math.PI / 180);

    return { x: dx * AUDIO_ENVIRONMENT_SCALE_FACTOR, y: 0, z: -dy * AUDIO_ENVIRONMENT_SCALE_FACTOR}
}

const allBotInfo = [
    {
        "name": "Terra",
        "audioPath": path.resolve("audio", "terra.mp3"),
        "latitude": 37.788062,
        "longitude": -122.407552,
        "yawDegrees": 180,
        "hiFiGain": 1.0
    },
    {
        "name": "Sam",
        "audioPath": path.resolve("audio", "sam.mp3"),
        "latitude": 37.787925,
        "longitude": -122.407236,
        "yawDegrees": 0,
        "hiFiGain": 1.0
    },
    {
        "name": "Claire",
        "audioPath": path.resolve("audio", "claire.mp3"),
        "latitude": 37.787951,
        "longitude": -122.407241,
        "yawDegrees": 180,
        "hiFiGain": 1.0
    },
    {
        "name": "Bridie",
        "audioPath": path.resolve("audio", "bridie.mp3"),
        "latitude": 37.787911,
        "longitude": -122.407901,
        "yawDegrees": 255,
        "hiFiGain": 1.0
    },
    {
        "name": "Alan",
        "audioPath": path.resolve("audio", "alan.mp3"),
        "latitude": 37.787903,
        "longitude": -122.407871,
        "yawDegrees": 75,
        "hiFiGain": 1.0
    },
];

allBotInfo.forEach((botInfo) => {
    startHiFiUnionSquareAudioBot(
        botInfo.name,
        botInfo.audioPath,
        point3DFromLatLon(botInfo.latitude, botInfo.longitude, unionSquareCenter.lat, unionSquareCenter.lon),
        { pitchDegrees: unionSquareCenter.lat - botInfo.latitude, yawDegrees: botInfo.yawDegrees, rollDegrees: unionSquareCenter.lon - botInfo.longitude },
        botInfo.hiFiGain
    );
});

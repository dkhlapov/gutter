import QtQuick
import QtMultimedia

// The only file that imports QtMultimedia: CameraCard loads it by URL, so a missing qt6-multimedia
// only breaks this view. Mirrored, like a mirror.
Item {
    id: root

    property bool active: false
    readonly property bool hasCamera: devices.videoInputs.length > 0
    readonly property string error: camera.errorString
    readonly property bool live: camera.active

    MediaDevices {
        id: devices
    }

    CaptureSession {
        camera: Camera {
            id: camera

            cameraDevice: devices.defaultVideoInput
            active: root.active && root.hasCamera
        }
        videoOutput: output
    }

    VideoOutput {
        id: output

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop

        transform: Scale {
            origin.x: output.width / 2
            xScale: -1
        }
    }
}

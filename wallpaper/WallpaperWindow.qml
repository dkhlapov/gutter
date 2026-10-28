import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.theme

// One per screen, on the Background layer. The paper fill shows whenever there is no usable image (or until it loads).
PanelWindow {
    id: win

    required property var modelData

    screen: modelData
    color: Theme.paper
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "gutter-wallpaper"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Image {
        anchors.fill: parent
        source: Wallpaper.path === "" ? "" : "file://" + encodeURI(Wallpaper.path).replace(/#/g, "%23").replace(/\?/g, "%3F")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Not cached: whenever the image loads again (another wallpaper and back, a new screen, a shell reload)
        // it shows the file as it is now. Nothing watches the image itself, so an overwrite in place shows on the next load.
        cache: false
        sourceSize: Qt.size(win.screen.width * win.screen.devicePixelRatio, win.screen.height * win.screen.devicePixelRatio)
        visible: status === Image.Ready
    }
}

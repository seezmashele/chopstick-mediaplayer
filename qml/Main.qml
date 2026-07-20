import QtQuick
import Chopstick

Window {
    id: root
    width: 1280
    height: 720
    visible: true
    title: "Chopstick Media Player"
    color: "black"

    // Format a duration in seconds as [h:]mm:ss.
    function fmt(t) {
        if (!t || t < 0 || isNaN(t))
            t = 0;
        t = Math.floor(t);
        var h = Math.floor(t / 3600);
        var m = Math.floor((t % 3600) / 60);
        var s = t % 60;
        var mm = (h > 0 && m < 10 ? "0" : "") + m;
        var ss = (s < 10 ? "0" : "") + s;
        return (h > 0 ? h + ":" : "") + mm + ":" + ss;
    }

    // Cycle audio among real tracks only — never the "no" (disabled) state.
    // mpv's aid is 1-based and sequential per audio track, matching
    // audioTrackCurrent, so we can select the next track's aid directly.
    function cycleAudioTrack() {
        if (player.audioTrackCount > 0) {
            var next = (player.audioTrackCurrent % player.audioTrackCount) + 1;
            player.command(["set", "aid", next]);
        }
        player.forceActiveFocus();
    }

    // Subtitles keep cycling through off (mpv's default cycle).
    function toggleSubtitle() {
        player.command(["cycle", "sub"]);
        player.forceActiveFocus();
    }

    function toggleFullScreen() {
        root.visibility = (root.visibility === Window.FullScreen)
            ? Window.Windowed : Window.FullScreen;
        player.forceActiveFocus();
    }

    // Phosphor icon font, bundled as a module resource.
    FontLoader {
        id: phosphorFont
        source: "../assets/fonts/Phosphor.ttf"
    }

    // Phosphor icon codepoints (Private Use Area) for the glyphs we use.
    readonly property var ph: ({
        "play": String.fromCharCode(0xe3d0),
        "pause": String.fromCharCode(0xe39e),
        "prev": String.fromCharCode(0xe5a4),
        "next": String.fromCharCode(0xe5a6),
        "volume": String.fromCharCode(0xe44a),
        "mute": String.fromCharCode(0xe45a),
        "subtitle": String.fromCharCode(0xe1a8), // subtitles
        "audio": String.fromCharCode(0xe802)     // waveform
    })

    // A small icon button rendering a Phosphor glyph, with an optional text
    // label beside it. `contentOpacity` dims the whole thing (e.g. when no
    // track of that type exists).
    component IconButton: Item {
        id: ib
        property string glyph
        property string label: ""
        property color color: "#f0f0f0"
        property int glyphSize: 18
        property real contentOpacity: 1.0
        signal clicked()

        implicitWidth: content.implicitWidth + 14
        implicitHeight: 30

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: hover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 4
            opacity: ib.contentOpacity

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ib.glyph
                color: ib.color
                font.family: phosphorFont.font.family
                font.pixelSize: ib.glyphSize
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: ib.label !== ""
                text: ib.label
                color: ib.color
                font.pixelSize: 12
            }
        }

        HoverHandler { id: hover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    MpvItem {
        id: player
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Space:
                player.command(["cycle", "pause"]);
                event.accepted = true;
                break;
            case Qt.Key_Left:
                player.command(["seek", -5]);
                event.accepted = true;
                break;
            case Qt.Key_Right:
                player.command(["seek", 5]);
                event.accepted = true;
                break;
            case Qt.Key_S:
                root.toggleSubtitle();
                event.accepted = true;
                break;
            case Qt.Key_A:
                root.cycleAudioTrack();
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (event.modifiers & Qt.AltModifier) {
                    root.toggleFullScreen();
                    event.accepted = true;
                }
                break;
            case Qt.Key_Escape:
                if (root.visibility === Window.FullScreen) {
                    root.toggleFullScreen();
                    event.accepted = true;
                }
                break;
            case Qt.Key_Q:
                Qt.quit();
                event.accepted = true;
                break;
            }
        }

        // Load only after the render context exists (vo=libmpv needs it first),
        // otherwise mpv fails to initialize video output.
        onReady: {
            if (startupFile && startupFile.length > 0)
                player.loadFile(startupFile);
        }
    }

    // Drop video files anywhere on the window to play them. First file replaces
    // playback; any others queue onto mpv's playlist.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]

        onEntered: (drag) => {
            if (drag.hasUrls)
                drag.accept();
        }
        onDropped: (drop) => {
            if (drop.hasUrls) {
                player.openUrls(drop.urls);
                drop.accept();
            }
        }
    }

    // Drag the video to move the window; double-click to toggle fullscreen.
    // Covers the video region only (stops at the control bar so it doesn't
    // interfere with the seek bar / buttons).
    MouseArea {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: controlBar.top
        }
        acceptedButtons: Qt.LeftButton
        property real pressX: 0
        property real pressY: 0

        onPressed: (mouse) => {
            pressX = mouse.x;
            pressY = mouse.y;
        }
        onPositionChanged: (mouse) => {
            // Only begin a window move once it's clearly a drag, so a stationary
            // double-click still registers.
            if (pressed && (Math.abs(mouse.x - pressX) > 8
                            || Math.abs(mouse.y - pressY) > 8))
                player.beginWindowDrag();
        }
        onDoubleClicked: root.toggleFullScreen()
    }

    // Bottom control bar: seek bar + info row.
    Rectangle {
        id: controlBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: contentColumn.implicitHeight + 20
        // rgba(10, 10, 10, 0.85) — alpha kept in the color so child controls stay opaque.
        color: Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0.85)

        Column {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 14
            }
            spacing: 8

            // Seek bar (click or drag to seek).
            Item {
                id: seekBar
                width: parent.width
                height: 16

                // While scrubbing, follow the cursor directly so the handle
                // never lags behind mpv's seek round-trip; otherwise track
                // actual playback position.
                property bool seeking: false
                property bool restoreMuted: false
                property real dragFraction: 0
                property real fraction: seeking
                    ? dragFraction
                    : (player.duration > 0 ? player.position / player.duration : 0)

                function fractionAt(x) {
                    return Math.max(0, Math.min(1, x / width));
                }

                // Throttle live previews while dragging to fast keyframe seeks
                // (inexact but cheap), so we don't flood mpv with exact seeks.
                Timer {
                    interval: 200
                    repeat: true
                    running: seekBar.seeking
                    onTriggered: {
                        if (player.duration > 0)
                            player.command(["seek", seekBar.dragFraction * player.duration,
                                            "absolute+keyframes"]);
                    }
                }

                Rectangle { // track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: "#4a4a4a"

                    Rectangle { // elapsed
                        width: parent.width * seekBar.fraction
                        height: parent.height
                        radius: 2
                        color: "#f0f0f0"
                    }
                }

                Rectangle { // handle
                    width: 12
                    height: 12
                    radius: 6
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * seekBar.fraction - width / 2
                    visible: player.duration > 0
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: (mouse) => {
                        // Silence the choppy audio that repeated seeks produce;
                        // remember the prior mute state to restore on release.
                        seekBar.restoreMuted = player.muted;
                        player.command(["set", "mute", "yes"]);
                        seekBar.dragFraction = seekBar.fractionAt(mouse.x);
                        seekBar.seeking = true;
                    }
                    onPositionChanged: (mouse) => {
                        if (seekBar.seeking)
                            seekBar.dragFraction = seekBar.fractionAt(mouse.x);
                    }
                    onReleased: (mouse) => {
                        seekBar.dragFraction = seekBar.fractionAt(mouse.x);
                        seekBar.seeking = false;
                        // Land on the exact frame once the drag ends.
                        if (player.duration > 0)
                            player.command(["seek", seekBar.dragFraction * player.duration,
                                            "absolute+exact"]);
                        // Restore audio last, so the final seek's blip stays muted.
                        player.command(["set", "mute", seekBar.restoreMuted ? "yes" : "no"]);
                        player.forceActiveFocus();
                    }
                }
            }

            // Controls row: playback buttons (left) + volume (right).
            Item {
                width: parent.width
                height: 32

                Row { // playback buttons
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    IconButton {
                        glyph: root.ph.prev
                        onClicked: {
                            player.command(["playlist-prev", "weak"]);
                            player.forceActiveFocus();
                        }
                    }
                    IconButton {
                        glyph: player.paused ? root.ph.play : root.ph.pause
                        onClicked: {
                            player.command(["cycle", "pause"]);
                            player.forceActiveFocus();
                        }
                    }
                    IconButton {
                        glyph: root.ph.next
                        onClicked: {
                            player.command(["playlist-next", "weak"]);
                            player.forceActiveFocus();
                        }
                    }
                }

                Row { // volume control
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    IconButton {
                        glyph: player.muted ? root.ph.mute : root.ph.volume
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            player.command(["cycle", "mute"]);
                            player.forceActiveFocus();
                        }
                    }

                    Item {
                        id: volBar
                        width: 110
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        property real fraction: Math.max(0, Math.min(1, player.volume / 100))

                        function setAt(x) {
                            var f = Math.max(0, Math.min(1, x / width));
                            player.command(["set", "volume", f * 100]);
                            player.forceActiveFocus();
                        }

                        Rectangle { // track
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: "#4a4a4a"

                            Rectangle { // fill
                                width: parent.width * volBar.fraction
                                height: parent.height
                                radius: 2
                                color: "#f0f0f0"
                            }
                        }
                        Rectangle { // handle
                            width: 11
                            height: 11
                            radius: 5.5
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * volBar.fraction - width / 2
                        }
                        MouseArea {
                            anchors.fill: parent
                            property bool dragging: false
                            onPressed: (mouse) => { dragging = true; volBar.setAt(mouse.x); }
                            onPositionChanged: (mouse) => { if (dragging) volBar.setAt(mouse.x); }
                            onReleased: dragging = false
                        }
                    }
                }
            }

            // Info row: left = status/codec/resolution/audio,
            // right = subtitle + audio-track buttons, then times.
            Item {
                width: parent.width
                height: 30

                Text {
                    id: infoText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#e8e8e8"
                    font.pixelSize: 13
                    text: (player.paused ? "Paused" : "Playing")
                          + "   ·   " + (player.videoCodec !== "" ? player.videoCodec : "—")
                          + "   ·   " + (player.videoWidth > 0 ? player.videoWidth + "×" + player.videoHeight : "—")
                          + "   ·   " + (player.audioCodec !== "" ? player.audioCodec : "—")
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    IconButton { // subtitle track toggle
                        glyph: root.ph.subtitle
                        label: player.subTrackCurrent + "/" + player.subTrackCount
                        contentOpacity: player.subTrackCount === 0 ? 0.4 : 1.0
                        onClicked: root.toggleSubtitle()
                    }
                    IconButton { // audio track toggle
                        glyph: root.ph.audio
                        label: player.audioTrackCurrent + "/" + player.audioTrackCount
                        contentOpacity: player.audioTrackCount === 0 ? 0.4 : 1.0
                        onClicked: root.cycleAudioTrack()
                    }
                    Text {
                        id: timeText
                        height: 30
                        leftPadding: 4
                        verticalAlignment: Text.AlignVCenter
                        color: "#e8e8e8"
                        font.pixelSize: 13
                        text: root.fmt(player.position) + " / " + root.fmt(player.duration)
                    }
                }
            }
        }
    }
}

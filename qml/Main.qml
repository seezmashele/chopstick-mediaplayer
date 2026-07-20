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

    // Bottom control bar: seek bar + info row.
    Rectangle {
        id: controlBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: contentColumn.implicitHeight + 20
        color: Qt.rgba(0, 0, 0, 0.65)

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
                    interval: 150
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

            // Info row: left = status/codec/resolution/audio, right = times.
            Item {
                width: parent.width
                height: Math.max(infoText.implicitHeight, timeText.implicitHeight)

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

                Text {
                    id: timeText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#e8e8e8"
                    font.pixelSize: 13
                    text: root.fmt(player.position) + " / " + root.fmt(player.duration)
                }
            }
        }
    }
}

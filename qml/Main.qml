import QtQuick
import QtCore
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

    // Prev/next: navigate the playlist when the user built one, otherwise walk
    // the neighbouring files in the current file's folder. Folder stepping
    // replaces what's loaded, so it's restricted to the single-file case — it
    // must never wipe a playlist the user deliberately queued up.
    function playNext() {
        if (player.playlist.length > 1)
            player.command(["playlist-next", "weak"]);
        else
            player.stepFolder(1);
        player.forceActiveFocus();
    }

    function playPrevious() {
        if (player.playlist.length > 1)
            player.command(["playlist-prev", "weak"]);
        else
            player.stepFolder(-1);
        player.forceActiveFocus();
    }

    function toggleFullScreen() {
        root.visibility = (root.visibility === Window.FullScreen)
            ? Window.Windowed : Window.FullScreen;
        player.forceActiveFocus();
    }

    // Shared size for general UI text (status row, playlist rows, button
    // labels). Icon glyph sizes and the filename badge are set separately.
    readonly property int uiFontSize: 13

    // --- Auto-hiding control bar -------------------------------------------
    // The bar only appears while the pointer is near the bottom of the window,
    // and slides away a few seconds after the last movement down there.
    readonly property int controlsHotZone: 140
    property bool controlsVisible: true

    // Individually toggleable sections of the bar (Ctrl+2 / Ctrl+5).
    property bool controlsRowVisible: true
    property bool statusRowVisible: true
    // Playlist panel (Ctrl+7). Width is drag-resizable from the panel's left edge.
    // Hidden by default on first run; afterwards the stored setting wins.
    property bool playlistVisible: false
    property real playlistWidth: 320
    readonly property real playlistMinWidth: 240
    readonly property real playlistMaxWidth: 720

    // Remembers which UI elements the user hid, plus the panel width. The
    // aliases are bidirectional: stored values load at startup, and changes are
    // written back automatically. Each property's declared default is what
    // first-run uses.
    Settings {
        category: "ui"
        property alias playlistVisible: root.playlistVisible
        property alias controlsRowVisible: root.controlsRowVisible
        property alias statusRowVisible: root.statusRowVisible
        property alias playlistWidth: root.playlistWidth
    }

    Timer {
        id: hideControlsTimer
        interval: 3000
        running: true
        onTriggered: {
            // Never hide out from under an active interaction.
            if (barHover.hovered || seekBar.seeking)
                restart();
            else
                root.controlsVisible = false;
        }
    }

    // --- Transient info badge (top-left OSD) -------------------------------
    // Shows either the filename or a volume readout, then fades out.
    property bool badgeVisible: false
    property string badgeMode: "title" // "title" | "volume"

    Timer {
        id: badgeTimer
        interval: 3000
        onTriggered: root.badgeVisible = false
    }

    // Flash the current filename.
    function showTitle() {
        if (player.fileName === "")
            return;
        root.badgeMode = "title";
        root.badgeVisible = true;
        badgeTimer.restart();
    }

    // Flash the current volume. The label binds to player.volume rather than
    // capturing it here, because mpv applies volume changes asynchronously —
    // formatting now would show the previous value.
    function showVolume() {
        root.badgeMode = "volume";
        root.badgeVisible = true;
        badgeTimer.restart();
    }

    // Called on pointer movement; only movement near the bottom wakes the bar.
    function nudgeControls(y) {
        if (y >= root.height - root.controlsHotZone) {
            root.controlsVisible = true;
            hideControlsTimer.restart();
        }
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
        "audio": String.fromCharCode(0xe802),    // waveform
        "close": String.fromCharCode(0xe4f6)     // x
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
                font.pixelSize: root.uiFontSize
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
            case Qt.Key_Up:
                player.command(["add", "volume", 5]);
                root.showVolume();
                event.accepted = true;
                break;
            case Qt.Key_Down:
                player.command(["add", "volume", -5]);
                root.showVolume();
                event.accepted = true;
                break;
            case Qt.Key_PageUp:
                root.playPrevious();
                event.accepted = true;
                break;
            case Qt.Key_PageDown:
                root.playNext();
                event.accepted = true;
                break;
            case Qt.Key_N:
                root.showTitle();
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
            case Qt.Key_2:
                if (event.modifiers & Qt.ControlModifier) {
                    root.controlsRowVisible = !root.controlsRowVisible;
                    event.accepted = true;
                }
                break;
            case Qt.Key_5:
                if (event.modifiers & Qt.ControlModifier) {
                    root.statusRowVisible = !root.statusRowVisible;
                    event.accepted = true;
                }
                break;
            case Qt.Key_7:
                if (event.modifiers & Qt.ControlModifier) {
                    root.playlistVisible = !root.playlistVisible;
                    event.accepted = true;
                }
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
            if (startupFiles && startupFiles.length > 0)
                player.openPaths(startupFiles);
        }

        // Flash the name whenever a new file starts playing.
        onFileNameChanged: root.showTitle()

        // A file played to its end: roll into the next file in the folder.
        // A real playlist advances itself, so only do this for the single-file
        // case (same rule as playNext()).
        onFileEnded: {
            if (player.playlist.length <= 1)
                player.stepFolder(1);
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

    // Click the video to play/pause, drag it to move the window, double-click
    // to toggle fullscreen. Covers the video region only (stops at the control
    // bar so it doesn't interfere with the seek bar / buttons).
    MouseArea {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: controlBar.top
        }
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true // needed to track the pointer for the auto-hiding bar
        property real pressX: 0
        property real pressY: 0
        property bool draggedWindow: false

        onPressed: (mouse) => {
            pressX = mouse.x;
            pressY = mouse.y;
            draggedWindow = false;
        }
        onPositionChanged: (mouse) => {
            root.nudgeControls(mouse.y);
            // Only begin a window move once it's clearly a drag, so a stationary
            // click / double-click still registers. Fire it once per press.
            if (pressed && !draggedWindow
                && (Math.abs(mouse.x - pressX) > 8
                    || Math.abs(mouse.y - pressY) > 8)) {
                draggedWindow = true;
                player.beginWindowDrag();
            }
        }
        onClicked: {
            // A drag that moved the window shouldn't also toggle playback.
            if (!draggedWindow)
                player.command(["cycle", "pause"]);
            player.forceActiveFocus();
        }
        onDoubleClicked: {
            // Qt delivers onClicked for the *first* click of a double-click, so
            // that already flipped pause — undo it, leaving playback untouched.
            player.command(["cycle", "pause"]);
            root.toggleFullScreen();
        }

        // Scroll over the video to change volume in 5% steps.
        property real wheelAccum: 0
        onWheel: (wheel) => {
            // A notched mouse wheel sends ±120 per detent; high-resolution
            // wheels and touchpads send many small deltas. Accumulate so both
            // step evenly instead of the touchpad racing through the range.
            wheelAccum += wheel.angleDelta.y;
            while (wheelAccum >= 120) {
                player.command(["add", "volume", 5]);
                wheelAccum -= 120;
            }
            while (wheelAccum <= -120) {
                player.command(["add", "volume", -5]);
                wheelAccum += 120;
            }
            root.showVolume();
            wheel.accepted = true;
        }
    }

    // Transient filename badge, top-left. Shown when a file starts playing and
    // on demand (N), then fades out after 3s.
    Rectangle {
        id: infoBadge
        anchors {
            top: parent.top
            left: parent.left
            margins: 16
        }
        width: Math.min(badgeLabel.implicitWidth + 24, root.width * 0.5)
        height: 38
        radius: 6
        color: Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0.85)
        opacity: root.badgeVisible ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 220 }
        }

        Text {
            id: badgeLabel
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
            }
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.badgeMode === "volume"
                ? "vol: " + Math.round(player.volume)
                : player.fileName
            color: "#f0f0f0"
            font.pixelSize: 18
        }
    }

    // Playlist panel — overlays the video on the right, spanning the full window
    // height. The control bar is declared after this, so it draws over the
    // panel's bottom edge.
    Rectangle {
        id: playlistPanel
        width: root.playlistWidth
        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
            rightMargin: root.playlistVisible ? 0 : -playlistPanel.width
        }
        color: Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0.9)
        opacity: root.playlistVisible ? 1 : 0

        Behavior on anchors.rightMargin {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        // Swallow clicks so they don't reach the window-drag / double-click
        // area beneath, but still wake the auto-hiding bar on hover (the panel
        // can cover the hot zone once the bar is hidden).
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: (mouse) => root.nudgeControls(mouse.y)
            // Swallow wheel events so scrolling over panel background doesn't
            // fall through to the video and change the volume.
            onWheel: (wheel) => { wheel.accepted = true; }
        }

        IconButton {
            id: playlistClose
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 6
                rightMargin: 6
            }
            glyph: root.ph.close
            glyphSize: 16
            color: "#c8c8c8"
            onClicked: {
                root.playlistVisible = false;
                player.forceActiveFocus();
            }
        }

        ListView {
            id: playlistView
            anchors {
                top: playlistClose.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 10
                leftMargin: 8
                rightMargin: 8
                bottomMargin: 10
            }
            clip: true
            spacing: 2
            model: player.playlist

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: ListView.view.width
                height: 34
                radius: 4
                color: modelData.current ? Qt.rgba(1, 1, 1, 0.14)
                     : entryHover.hovered ? Qt.rgba(1, 1, 1, 0.07)
                     : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Item { // index, or a play glyph for the current entry
                        width: 16
                        height: parent.height

                        Text {
                            anchors.centerIn: parent
                            visible: !modelData.current
                            text: index + 1
                            color: "#8a8a8a"
                            font.pixelSize: root.uiFontSize
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: modelData.current
                            text: root.ph.play
                            font.family: phosphorFont.font.family
                            font.pixelSize: 12 // icon metric, not body text
                            color: "#ffcf8a"
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 32
                        elide: Text.ElideRight
                        text: modelData.title
                        color: modelData.current ? "#ffffff" : "#d0d0d0"
                        font.pixelSize: root.uiFontSize
                    }
                }

                HoverHandler { id: entryHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        player.command(["set", "playlist-pos", index]);
                        player.forceActiveFocus();
                    }
                }
            }
        }

        // Drag the panel's left edge to resize. Declared last so it sits above
        // the list and the catch-all area.
        MouseArea {
            id: playlistResizer
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: 6
            cursorShape: Qt.SizeHorCursor
            hoverEnabled: true

            property real pressSceneX: 0
            property real startWidth: 0

            // Track in scene coordinates: the handle itself moves as the panel
            // resizes, so local x would drift mid-drag.
            onPressed: (mouse) => {
                pressSceneX = mapToItem(null, Qt.point(mouse.x, mouse.y)).x;
                startWidth = root.playlistWidth;
            }
            onPositionChanged: (mouse) => {
                if (!pressed)
                    return;
                const sceneX = mapToItem(null, Qt.point(mouse.x, mouse.y)).x;
                const delta = pressSceneX - sceneX; // drag left ⇒ wider
                root.playlistWidth = Math.max(
                    root.playlistMinWidth,
                    Math.min(root.playlistMaxWidth, startWidth + delta));
            }
        }

        // Subtle grab affordance on the resize edge.
        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: 1
            color: playlistResizer.pressed || playlistResizer.containsMouse
                ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.10)
        }
    }

    // Bottom control bar: seek bar + info row.
    Rectangle {
        id: controlBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            // Slide fully out of view when hidden. Moving the item (rather than
            // just fading it) also frees the region: the video MouseArea is
            // anchored to controlBar.top, so it extends to the window bottom and
            // can detect the pointer entering the hot zone.
            bottomMargin: root.controlsVisible ? 0 : -controlBar.height
        }
        height: contentColumn.implicitHeight + 20
        // rgba(10, 10, 10, 0.9) — alpha kept in the color so child controls stay opaque.
        color: Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0.9)
        opacity: root.controlsVisible ? 1 : 0

        Behavior on anchors.bottomMargin {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        // Keeps the bar awake while the pointer rests on it.
        HoverHandler { id: barHover }

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

            // Controls row: playback buttons (left) + volume (right). Ctrl+2.
            Item {
                width: parent.width
                height: 32
                visible: root.controlsRowVisible

                Row { // playback buttons
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    IconButton {
                        glyph: root.ph.prev
                        onClicked: root.playPrevious()
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
                        onClicked: root.playNext()
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
                        property bool dragging: false
                        property real fraction: Math.max(0, Math.min(1, player.volume / 100))

                        // Glide when volume changes from keys / scroll, but stay
                        // 1:1 with the cursor while dragging the slider itself.
                        Behavior on fraction {
                            enabled: !volBar.dragging
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        function setAt(x) {
                            var f = Math.max(0, Math.min(1, x / width));
                            player.command(["set", "volume", f * 100]);
                            root.showVolume();
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
                            onPressed: (mouse) => { volBar.dragging = true; volBar.setAt(mouse.x); }
                            onPositionChanged: (mouse) => { if (volBar.dragging) volBar.setAt(mouse.x); }
                            onReleased: volBar.dragging = false
                        }
                    }
                }
            }

            // Info/status row: left = status/codec/resolution/audio,
            // right = subtitle + audio-track buttons, then times. Ctrl+5.
            Item {
                width: parent.width
                height: 30
                visible: root.statusRowVisible

                Text {
                    id: infoText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#e8e8e8"
                    font.pixelSize: root.uiFontSize
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
                        font.pixelSize: root.uiFontSize
                        text: root.fmt(player.position) + " / " + root.fmt(player.duration)
                    }
                }
            }
        }
    }
}

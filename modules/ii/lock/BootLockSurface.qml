import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import Quickshell

/**
 * The BOOT lock: LockSurface without the shell's services (no now playing, no unread count,
 * no island state), so a second, tiny quickshell instance (bootlock.qml) can lock the
 * session within about a second of the compositor starting, while the full shell loads
 * behind it. Same ground, clock, pills and discs. Keep in step with LockSurface.qml.
 *
 * The lock screen on the desktop's language. The wallpaper blurred and dimmed; the notch pill
 * at the top centre with the time and the desktop's status glyph; a big clock and the date;
 * now playing and the unread count only when there is something; the password as a docked
 * pill at the bottom centre; Sleep / Restart / Shut down as the session panel's discs in the
 * bottom-right corner. Replaced hyprlock (no hover, no shared components) on 2026-09-09.
 */
MouseArea {
    id: root
    required property BootLockContext context
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    // a new account's first boot has no wallpaper yet (the first start applies one): Tacit's own, not a flat grey
    readonly property string wallpaper: Config.options.background.lockWall !== ""
        ? Config.options.background.lockWall : Config.options.background.wallpaperPath !== ""
        ? Config.options.background.wallpaperPath : Quickshell.shellPath("assets/wallpapers/dusk.jpg")

    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: root.context
        function onShouldReFocus() {
            root.forceFieldFocus();
        }
    }
    // Hyprland hands the lock surface back keyboard-unfocused after a resume or a monitor
    // change, and then typing does nothing with no clue why. The lockFocus shortcut and the
    // lock.focus IPC method both need someone to call them; this notices on its own.
    Timer {
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            if (!passwordBox.activeFocus) {
                root.forceFieldFocus();
            }
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => { root.activity(); root.forceFieldFocus(); }

    // Entrance: the pills rise a little and fade in, once. With holdEntrance (bootlock.qml's sky plays first) they
    // wait for enter(); the field has focus from the start, so nothing typed meanwhile is lost.
    property real entrance: 0
    Behavior on entrance {
        Anim {}
    }
    property bool holdEntrance: false
    function enter() { entrance = 1; }
    Component.onCompleted: {
        forceFieldFocus();
        // decided once creation is done: bootlock.qml's holdEntrance follows a file read that can land after this
        // surface completes, and deciding here showed the clock and field over the sky from the first frame
        Qt.callLater(() => {
            if (!root.holdEntrance)
                root.entrance = 1;
        });
    }
    // a key or a press: bootlock.qml takes its sky to the end
    signal activity()
    // drawn over the ground and under everything else (bootlock.qml's sky)
    property Component underlay: null
    readonly property Item underlayItem: underlayLoader.item

    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.activity();
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = true;
        if (event.key === Qt.Key_Escape)
            root.context.currentText = "";
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control)
            root.ctrlHeld = false;
        forceFieldFocus();
    }

    // ------------------------------------------------------------ the ground
    // The pre-rendered lock ground (mkassets.sh --ground): the exact pixels the boot splash
    // held and swaybg shows, so the lock appearing changes nothing but the clock. Live blur
    // only as the fallback when the file is missing.
    property string groundPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/tacit-boot/lock-ground.png"
    readonly property bool groundReady: ground.status === Image.Ready
    Image {
        id: ground
        anchors.fill: parent
        source: "file://" + root.groundPath
        fillMode: Image.PreserveAspectCrop
        cache: true
        visible: root.groundReady
    }
    // misc:session_lock_xray means the compositor paints nothing under this surface, so
    // whatever it does not cover opaquely IS the live desktop. The blur below can come out
    // empty (no lockWall, an unreadable wallpaper): this is the floor under it.
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3background
        visible: !root.groundReady
    }
    Image {
        id: wallSource
        anchors.fill: parent
        // Only the blur reads this: skip the decode while the ground file is shown, and decode small (radius 48 hides the detail).
        source: root.groundReady ? "" : root.wallpaper
        sourceSize: Qt.size(Math.ceil(width / 4), Math.ceil(height / 4))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }
    FastBlur {
        anchors.fill: parent
        source: wallSource
        radius: 48
        visible: !root.groundReady
    }
    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.6)
        visible: !root.groundReady
    }
    Loader {
        id: underlayLoader
        anchors.fill: parent
        active: root.underlay !== null
        sourceComponent: root.underlay
    }

    // ------------------------------------------------------------ the notch
    Item {
        id: notch
        anchors.top: parent.top
        anchors.topMargin: Appearance.liquidGlass.enabled ? 10 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property string glyph: Battery.available && Battery.isCharging ? "bolt" : ""
        opacity: root.holdEntrance ? root.entrance : 1
        width: 108 + (glyph !== "" ? 30 : 0)
        height: 34
        DockedRect {
            anchors.fill: parent
            edge: "top"
            floating: Appearance.liquidGlass.enabled
            cornerRadius: Appearance.liquidGlass.enabled ? 17 : 14
            fillet: Appearance.liquidGlass.enabled ? 0 : 6
            color: Appearance.colors.colPanelFrost
        }
        Row {
            anchors.centerIn: parent
            spacing: 8
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: DateTime.time
                font.family: Appearance.font.family.numbers
                font.pixelSize: 16
                color: Appearance.colors.colOnSurface
            }
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: notch.glyph !== ""
                text: notch.glyph
                iconSize: 18
                color: Appearance.colors.colPrimary
            }
        }
    }

    // ------------------------------------------------------------ clock, date, now, away
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * (Appearance.liquidGlass.enabled ? 0.19 : 0.22)
        spacing: 6
        opacity: root.entrance

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: Appearance.liquidGlass.enabled
            text: Qt.formatDate(DateTime.clock.date, "dddd d MMMM")
            font.pixelSize: 19
            font.weight: Font.Medium
            color: Tacit.inkSec
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: DateTime.time
            font.family: Appearance.font.family.numbers
            font.pixelSize: 96
            font.weight: Appearance.liquidGlass.enabled ? Font.DemiBold : Font.Normal
            color: Appearance.liquidGlass.enabled ? ColorUtils.transparentize(Tacit.inkMain, 0.12) : Appearance.colors.colOnSurface
            layer.enabled: Appearance.liquidGlass.enabled
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Appearance.liquidGlass.shadow
                shadowBlur: 0.45
                shadowVerticalOffset: 4
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: !Appearance.liquidGlass.enabled
            text: Qt.formatDate(DateTime.clock.date, "dddd d MMMM")
            font.pixelSize: 19
            color: Appearance.colors.colSubtext
        }

        Item {
            Layout.preferredHeight: 28
        }

    }

    // ------------------------------------------------------------ who: your picture (~/.face, chosen in Setup or in
    // Settings) over your name, above the field, as a Mac's login has it; the name alone when there is no picture
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: passwordPill.top
        anchors.bottomMargin: 28
        spacing: 10
        opacity: root.entrance
        Item {
            Layout.alignment: Qt.AlignHCenter
            visible: face.status === Image.Ready
            implicitWidth: 72
            implicitHeight: 72
            Image {
                id: face
                anchors.fill: parent
                source: `file://${Quickshell.env("HOME")}/.face`
                sourceSize: Qt.size(144, 144)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: 72; height: 72; radius: 36 }
                }
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Config.options.profile.displayName || SystemInfo.username
            font.pixelSize: 16
            color: Appearance.colors.colSubtext
        }
    }

    // ------------------------------------------------------------ the password pill
    Item {
        id: passwordPill
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: 420
        height: Appearance.liquidGlass.enabled ? 58 : 58 + 6
        y: 0
        anchors.bottomMargin: Appearance.liquidGlass.enabled ? 24 - 12 * (1 - root.entrance) : -6 * (1 - root.entrance)
        opacity: root.entrance

        DockedRect {
            anchors.fill: parent
            edge: "bottom"
            floating: Appearance.liquidGlass.enabled
            cornerRadius: Appearance.liquidGlass.enabled ? 29 : 23
            fillet: Appearance.liquidGlass.enabled ? 0 : 6
            color: Appearance.colors.colPanelFrost
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 10
            anchors.rightMargin: 7
            height: 58
            spacing: 6

            Loader {
                Layout.leftMargin: 6
                active: root.context.fingerprintsConfigured
                visible: active
                sourceComponent: MaterialSymbol {
                    fill: 1
                    text: "fingerprint"
                    iconSize: 24
                    color: Appearance.colors.colSubtext
                }
            }

            ToolbarTextField {
                id: passwordBox
                Layout.fillWidth: true
                colBackground: "transparent"
                placeholderText: {
                    if (root.context.authUnavailable)
                        return Translation.tr("Authentication unavailable");
                    return root.context.unlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Password");
                }
                clip: true
                font.pixelSize: Appearance.font.pixelSize.large
                selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
                selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

                enabled: !root.context.unlockInProgress
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData

                onTextChanged: root.context.currentText = this.text
                onAccepted: root.context.tryUnlock(root.ctrlHeld)
                Connections {
                    target: root.context
                    function onCurrentTextChanged() {
                        passwordBox.text = root.context.currentText;
                    }
                }
                Keys.onPressed: event => root.context.resetClearTimer()

                ErrorShakeAnimation {
                    id: wrongPasswordShakeAnim
                    target: passwordBox
                }
                Connections {
                    target: root.context
                    function onUnlockFailedChanged() {
                        if (root.context.unlockFailed)
                            wrongPasswordShakeAnim.restart();
                    }
                }

                property bool materialShapeChars: Config.options.lock.materialShapeChars
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
                Loader {
                    active: passwordBox.materialShapeChars
                    anchors {
                        fill: parent
                        leftMargin: passwordBox.padding
                        rightMargin: passwordBox.padding
                    }
                    sourceComponent: PasswordChars {
                        length: root.context.currentText.length
                        selectionStart: passwordBox.selectionStart
                        selectionEnd: passwordBox.selectionEnd
                        cursorPosition: passwordBox.cursorPosition
                        charSize: 26
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            // Confirm: the session's disc, filled. Coffee while Ctrl is held (unlock + caffeine).
            Disc {
                implicitWidth: 46
                implicitHeight: 46
                glyph: {
                    if (root.context.targetAction === BootLockContext.ActionEnum.Poweroff)
                        return "power_settings_new";
                    if (root.context.targetAction === BootLockContext.ActionEnum.Reboot)
                        return "restart_alt";
                    return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                }
                filled: true
                enabled: !root.context.unlockInProgress
                opacity: root.context.unlockInProgress ? 0.6 : 1
                checking: root.context.unlockInProgress
                onActivated: root.context.tryUnlock(root.ctrlHeld)
            }
        }
    }

    // Battery beside the pill, from the real battery.
    StyledText {
        anchors.left: passwordPill.right
        anchors.leftMargin: 16
        anchors.verticalCenter: passwordPill.verticalCenter
        anchors.verticalCenterOffset: -6
        visible: Battery.available
        text: `${Math.round(Battery.percentage * 100)}%${Battery.isCharging ? " · " + Translation.tr("charging") : ""}`
        font.pixelSize: 15
        color: Battery.isLowAndNotCharging ? Appearance.colors.colError : Appearance.colors.colSubtext
        opacity: root.entrance
    }

    // ------------------------------------------------------------ power, bottom right
    // The session panel's discs, in its corner: hover turns them white, exactly as there.
    Item {
        id: powerPanel
        readonly property int pad: Appearance.liquidGlass.enabled ? 14 : 20
        readonly property int edgeInset: Appearance.liquidGlass.enabled ? 0 : 6
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Appearance.liquidGlass.enabled ? 20 : 0
        width: 3 * 44 + 2 * 16 + 2 * pad + edgeInset
        height: 44 + 2 * pad + edgeInset
        anchors.bottomMargin: Appearance.liquidGlass.enabled ? 20 - 12 * (1 - root.entrance) : -12 * (1 - root.entrance)
        opacity: root.entrance

        DockedRect {
            anchors.fill: parent
            edge: "bottom-right"
            floating: Appearance.liquidGlass.enabled
            cornerRadius: Appearance.liquidGlass.enabled ? 30 : Appearance.rounding.verylarge
            fillet: Appearance.liquidGlass.enabled ? 0 : 6
            color: Appearance.colors.colPanelFrost
        }

        Row {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: powerPanel.edgeInset + powerPanel.pad
            anchors.topMargin: powerPanel.edgeInset + powerPanel.pad
            spacing: 16

            Disc {
                glyph: "dark_mode"
                onActivated: Session.suspend()
            }
            Disc {
                glyph: "restart_alt"
                onActivated: root.power(BootLockContext.ActionEnum.Reboot, () => Session.reboot())
            }
            Disc {
                glyph: "power_settings_new"
                onActivated: root.power(BootLockContext.ActionEnum.Poweroff, () => Session.poweroff())
            }
        }
    }

    // Shut down and restart honour lock.security.requirePasswordToPower: the disc arms the
    // confirm button's action and the password does the rest.
    function power(action, run) {
        if (root.requirePasswordToPower) {
            root.context.targetAction = action;
            root.forceFieldFocus();
            return;
        }
        run();
    }

    // The session panel's BigAction, verbatim in size and colours (SessionScreen.qml).
    component Disc: RippleButton {
        id: disc
        property string glyph: ""
        property bool filled: false
        property bool checking: false
        signal activated
        implicitWidth: 44
        implicitHeight: 44
        padding: 0
        buttonRadius: Appearance.rounding.full
        border: Appearance.liquidGlass.enabled
        borderWidth: Appearance.liquidGlass.enabled ? 1 : 0
        colBorder: (filled || hovered) ? Appearance.liquidGlass.pillBorderActive : Appearance.liquidGlass.pillBorder
        colBackground: filled ? Appearance.colors.colPrimary : (Appearance.liquidGlass.enabled ? Appearance.liquidGlass.pillFill : Appearance.colors.colLayer2)
        colBackgroundHover: Appearance.colors.colPrimary
        colRipple: Appearance.colors.colPrimaryActive
        scale: disc.down ? 0.92 : 1.0
        Behavior on scale { Anim { type: Anim.FastSpatial } }
        releaseAction: () => disc.activated()
        contentItem: MaterialSymbol {
            text: disc.checking ? "progress_activity" : disc.glyph
            iconSize: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: (disc.filled || disc.hovered) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
            RotationAnimation on rotation {
                running: disc.checking
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }
    }
}

import QtQuick
import QtQuick.Effects
import qs.modules.common

/**
 * Floating iOS 27 Liquid Glass surface rendered via an analytical SDF GPU shader
 * with directional Fresnel specular rims, inner chromatic edge dispersion,
 * ambient elevation shadow, and subtle pointer-reactive caustic sheen.
 */
Item {
    id: root

    property color color: Appearance.colors.colPanelFrost
    property real radius: Appearance.liquidGlass.panelRadius
    property vector4d cornerRadii: Qt.vector4d(radius, radius, radius, radius)
    property vector4d freeEdges: Qt.vector4d(1, 1, 1, 1)
    property real rimWidth: 1.4
    property real lensStrength: 1.0
    property bool interactive: true
    property bool shadowEnabled: true
    property real shadowBlur: 28
    property vector2d shadowOffset: Qt.vector2d(0, 10)
    property color rimColor: Appearance.liquidGlass.rimPrimary
    property color chromaColor: Appearance.liquidGlass.rimSecondary
    property color counterColor: Appearance.liquidGlass.rimCounter
    property color depthColor: Appearance.liquidGlass.tintBottom

    readonly property bool glassEnabled: Appearance.liquidGlass.enabled
    property real lightX: 0.22
    property real lightY: 0.10

    Behavior on lightX {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }
    Behavior on lightY {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    HoverHandler {
        enabled: root.interactive && root.glassEnabled
        onPointChanged: {
            if (hovered && root.width > 1 && root.height > 1) {
                root.lightX = Math.max(0.0, Math.min(1.0, point.position.x / root.width));
                root.lightY = Math.max(0.0, Math.min(1.0, point.position.y / root.height));
            }
        }
        onHoveredChanged: {
            if (!hovered) {
                root.lightX = 0.22;
                root.lightY = 0.10;
            }
        }
    }

    RectangularShadow {
        anchors.fill: parent
        visible: root.shadowEnabled && root.glassEnabled && root.width > 4 && root.height > 4
        radius: Math.min(root.radius, Math.min(root.width, root.height) / 2)
        blur: root.shadowBlur
        offset: root.shadowOffset
        color: Appearance.liquidGlass.shadow
    }

    ShaderEffect {
        id: shader
        anchors.fill: parent
        visible: root.glassEnabled && root.width > 0 && root.height > 0

        property vector2d res: Qt.vector2d(width, height)
        property vector4d radii: root.cornerRadii
        property vector4d freeEdges: root.freeEdges
        property color bodyColor: root.color
        property color rimColor: root.rimColor
        property color chromaColor: root.chromaColor
        property color counterColor: root.counterColor
        property color depthColor: root.depthColor
        property vector2d lightPos: Qt.vector2d(root.lightX, root.lightY)
        property real rimWidth: root.rimWidth
        property real lensStrength: root.lensStrength

        fragmentShader: Qt.resolvedUrl("shaders/liquid_glass.frag.qsb")
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.glassEnabled
        radius: Math.min(root.radius, Math.min(root.width, root.height) / 2)
        color: root.color
    }
}

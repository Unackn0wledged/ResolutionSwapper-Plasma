import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

MouseArea {
    id: compact

    required property var swapper

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool showLabel: Plasmoid.configuration.showResolution && !vertical && swapper.currentMode !== null

    // Clicking outside closes the popup before this click arrives, so the
    // state has to be read on press or a click could not close it.
    property bool wasExpanded: false

    Layout.minimumWidth: vertical ? 0 : row.implicitWidth
    Layout.minimumHeight: vertical ? row.implicitHeight : 0

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true

    onPressed: wasExpanded = swapper.expanded
    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton || Plasmoid.configuration.leftClickSwaps) {
            swapper.swap();
        } else {
            swapper.expanded = !wasExpanded;
        }
    }

    RowLayout {
        id: row

        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.fillWidth: !compact.showLabel
            Layout.fillHeight: true
            Layout.preferredWidth: height

            source: Plasmoid.icon
            active: compact.containsMouse
        }

        PlasmaComponents.Label {
            visible: compact.showLabel
            text: compact.swapper.currentMode ? `${compact.swapper.currentMode.size.width} x ${compact.swapper.currentMode.size.height}` : ""
        }
    }
}

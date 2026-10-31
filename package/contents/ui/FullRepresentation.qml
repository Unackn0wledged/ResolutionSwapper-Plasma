import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: full

    required property var swapper

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("Current: %1", full.swapper.currentModeText)
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: full.swapper.mainOutput !== null
                text: full.swapper.mainOutput ? i18n("Main monitor: %1", full.swapper.mainOutput.name) : ""
                opacity: 0.7
                elide: Text.ElideRight
            }
        }

        PlasmaComponents.BusyIndicator {
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            visible: full.swapper.busy
            running: visible
        }
    }

    Repeater {
        model: full.swapper.presets

        delegate: PlasmaComponents.ItemDelegate {
            id: presetRow

            required property var modelData
            required property int index

            Layout.fillWidth: true

            enabled: !full.swapper.busy && !full.swapper.trial
            highlighted: modelData.active

            onClicked: {
                if (modelData.mode) {
                    full.swapper.switchToPreset(index);
                }
            }

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: presetRow.modelData.active ? "checkmark" : ""
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: presetRow.modelData.name
                        elide: Text.ElideRight
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: presetRow.modelData.mode
                            ? full.swapper.formatPreset(presetRow.modelData)
                            : i18n("%1 is not offered by this monitor", full.swapper.formatPreset(presetRow.modelData))
                        visible: presetRow.modelData.valid
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                    }
                }

                PlasmaComponents.Button {
                    visible: presetRow.modelData.valid && !presetRow.modelData.mode
                    text: i18nc("@action:button Add a custom display mode", "Add")
                    onClicked: full.swapper.addCustomMode(presetRow.index)

                    PlasmaComponents.ToolTip.text: i18n("Try this resolution as a custom mode for %1 seconds", full.swapper.trialSeconds)
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: full.swapper.trial !== null
        type: Kirigami.MessageType.Warning
        text: i18np("Keep this resolution? Going back in 1 second.",
                    "Keep this resolution? Going back in %1 seconds.",
                    full.swapper.trialSecondsLeft)
        actions: [
            Kirigami.Action {
                text: i18n("Keep")
                icon.name: "dialog-ok"
                onTriggered: full.swapper.keepTrial()
            },
            Kirigami.Action {
                text: i18n("Go back")
                icon.name: "edit-undo"
                onTriggered: full.swapper.revertTrial()
            }
        ]
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: full.swapper.errorText !== ""
        type: Kirigami.MessageType.Error
        text: full.swapper.errorText
    }

    // Keeps the rows together when the widget sits on the desktop.
    Item {
        Layout.fillHeight: true
    }
}

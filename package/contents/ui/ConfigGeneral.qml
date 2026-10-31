import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_presetAName: presetAName.text
    property alias cfg_presetAResolution: presetAResolution.text
    property alias cfg_presetBName: presetBName.text
    property alias cfg_presetBResolution: presetBResolution.text
    property alias cfg_customModeRefreshRate: customModeRefreshRate.value
    property alias cfg_showResolution: showResolution.checked
    property alias cfg_leftClickSwaps: leftClickSwaps.checked
    property alias cfg_showNotifications: showNotifications.checked

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("First resolution")
        }

        QQC2.TextField {
            id: presetAName

            Kirigami.FormData.label: i18n("Name:")
        }

        ResolutionField {
            id: presetAResolution

            Kirigami.FormData.label: i18n("Resolution:")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Second resolution")
        }

        QQC2.TextField {
            id: presetBName

            Kirigami.FormData.label: i18n("Name:")
        }

        ResolutionField {
            id: presetBResolution

            Kirigami.FormData.label: i18n("Resolution:")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Custom modes")
        }

        QQC2.SpinBox {
            id: customModeRefreshRate

            Kirigami.FormData.label: i18n("Refresh rate (Hz):")
            from: 24
            to: 360
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Behavior")
        }

        QQC2.CheckBox {
            id: showResolution

            text: i18n("Show current resolution in the panel")
        }

        QQC2.CheckBox {
            id: leftClickSwaps

            text: i18n("Left click swaps instead of opening the widget")
        }

        QQC2.CheckBox {
            id: showNotifications

            text: i18n("Show a notification after switching")
        }
    }
}

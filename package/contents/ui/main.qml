import QtQml
import QtQuick
import org.kde.notification
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

import "../code/logic.js" as Logic

PlasmoidItem {
    id: root

    // How long a new custom mode has to be confirmed before it is undone. A mode
    // the monitor rejects leaves it black, so nothing on it could be clicked.
    readonly property int trialSeconds: 15

    property var outputs: []
    property bool busy: false
    property string errorText: ""
    property var trial: null
    property int trialSecondsLeft: 0

    readonly property var mainOutput: Logic.mainOutput(outputs)
    readonly property var currentMode: Logic.currentMode(mainOutput)
    readonly property string currentModeText: currentMode ? Logic.formatMode(currentMode) : i18n("unknown")
    readonly property var presets: [
        Logic.buildPreset(mainOutput, Plasmoid.configuration.presetAName, Plasmoid.configuration.presetAResolution),
        Logic.buildPreset(mainOutput, Plasmoid.configuration.presetBName, Plasmoid.configuration.presetBResolution),
    ]

    function formatPreset(preset) {
        return preset.mode ? Logic.formatMode(preset.mode) : Logic.formatResolution(preset.width, preset.height);
    }

    function announce(text) {
        if (Plasmoid.configuration.showNotifications) {
            notification.text = text;
            notification.sendEvent();
        }
    }

    function fail(text) {
        errorText = text;
        notification.text = text;
        notification.sendEvent();
    }

    // `done` only runs on success. Background refreshes pass none, and they stay
    // quiet on failure so a broken setup does not repeat a notification.
    function refresh(done) {
        shell.run(Logic.queryCommand, data => {
            const parsed = data["exit code"] === 0 ? Logic.parseOutputs(data.stdout) : null;
            if (parsed === null) {
                const message = i18n("Could not read the monitor setup: %1", data.stderr.trim());
                busy = false;
                if (done) {
                    fail(message);
                } else {
                    errorText = message;
                }
                return;
            }
            outputs = parsed;
            if (done) {
                done();
            }
        });
    }

    // kscreen-doctor exits with 0 even when it rejects a mode, so success is
    // decided by reading the setup back.
    function applyMode(target, done) {
        shell.run(Logic.switchCommand(outputs, mainOutput, target), () => {
            refresh(() => done(currentMode !== null && currentMode.id === target.id));
        });
    }

    function switchToPreset(index) {
        if (busy || trial) {
            return;
        }
        busy = true;
        errorText = "";
        refresh(() => {
            const preset = presets[index];
            if (preset.active) {
                busy = false;
            } else if (!preset.mode) {
                busy = false;
                fail(i18n("The main monitor does not offer %1. Open the widget to add it as a custom mode.",
                          formatPreset(preset)));
            } else {
                applyMode(preset.mode, succeeded => {
                    busy = false;
                    if (succeeded) {
                        announce(i18n("Main monitor switched to %1", formatPreset(preset)));
                    } else {
                        fail(i18n("Could not switch the main monitor to %1.", formatPreset(preset)));
                    }
                });
            }
        });
    }

    function swap() {
        switchToPreset(Logic.nextPresetIndex(presets));
    }

    function addCustomMode(index) {
        if (busy || trial) {
            return;
        }
        busy = true;
        errorText = "";
        refresh(() => {
            const output = mainOutput;
            const previous = currentMode;
            const preset = presets[index];
            if (!output || !previous || !preset.valid) {
                busy = false;
                fail(i18n("Could not read the monitor setup."));
                return;
            }
            const refreshRate = Plasmoid.configuration.customModeRefreshRate;
            shell.run(Logic.listCommand, listing => {
                const customIndex = Logic.customModeCount(listing.stdout, output.name);
                shell.run(Logic.addCustomModeCommand(output, preset.width, preset.height, refreshRate), () => {
                    refresh(() => startTrial(index, previous, customIndex));
                });
            });
        });
    }

    function startTrial(index, previousMode, customIndex) {
        const preset = presets[index];
        if (!preset.mode) {
            busy = false;
            fail(i18n("KWin did not accept %1 as a custom mode.", formatPreset(preset)));
            return;
        }
        applyMode(preset.mode, succeeded => {
            if (!succeeded) {
                removeCustomMode(customIndex, () => {
                    fail(i18n("The main monitor could not use %1, so the custom mode was removed.", formatPreset(preset)));
                });
                return;
            }
            busy = false;
            trial = { previousMode: previousMode, customIndex: customIndex, name: formatPreset(preset) };
            trialSecondsLeft = trialSeconds;
            trialTimer.start();
            expanded = true;
        });
    }

    function keepTrial() {
        trialTimer.stop();
        announce(i18n("Main monitor switched to %1", trial.name));
        trial = null;
    }

    // Mode ids can shift when the mode list changes, so the mode to go back to
    // is looked up again by its size and refresh rate.
    function revertTrial(done) {
        trialTimer.stop();
        const finished = trial;
        trial = null;
        busy = true;
        refresh(() => {
            applyMode(Logic.sameMode(mainOutput, finished.previousMode), () => {
                removeCustomMode(finished.customIndex, () => {
                    if (done) {
                        done(finished);
                    }
                });
            });
        });
    }

    function removeCustomMode(index, done) {
        shell.run(Logic.removeCustomModeCommand(mainOutput, index), () => {
            refresh(() => {
                busy = false;
                done();
            });
        });
    }

    Plasmoid.icon: "video-display"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: Plasmoid.title
    toolTipSubText: i18n("Main monitor: %1", currentModeText)

    // The widget's keyboard shortcut swaps directly, like the Windows hotkey.
    activationTogglesExpanded: false
    hideOnWindowDeactivate: trial === null

    compactRepresentation: CompactRepresentation {
        swapper: root
    }
    fullRepresentation: FullRepresentation {
        swapper: root
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Current: %1", root.currentModeText)
            enabled: false
        },
        PlasmaCore.Action {
            isSeparator: true
        },
        PlasmaCore.Action {
            text: root.presets[0].name
            icon.name: root.presets[0].active ? "checkmark" : ""
            enabled: !root.busy && !root.trial
            onTriggered: root.switchToPreset(0)
        },
        PlasmaCore.Action {
            text: root.presets[1].name
            icon.name: root.presets[1].active ? "checkmark" : ""
            enabled: !root.busy && !root.trial
            onTriggered: root.switchToPreset(1)
        },
        PlasmaCore.Action {
            isSeparator: true
        }
    ]

    onExpandedChanged: expanded => {
        if (expanded) {
            refresh();
        }
    }

    Component.onCompleted: refresh()

    Connections {
        target: Plasmoid

        function onActivated() {
            root.swap();
        }
    }

    P5Support.DataSource {
        id: shell

        property var pending: ({})

        function run(command, callback) {
            pending[command] = (pending[command] || []).concat(callback);
            connectSource(command);
        }

        engine: "executable"
        connectedSources: []

        onNewData: (source, data) => {
            disconnectSource(source);
            const callbacks = pending[source] || [];
            delete pending[source];
            callbacks.forEach(callback => callback(data));
        }
    }

    Notification {
        id: notification

        componentName: "plasma_workspace"
        eventId: "notification"
        title: Plasmoid.title
        iconName: Plasmoid.icon
    }

    Timer {
        id: trialTimer

        interval: 1000
        repeat: true

        onTriggered: {
            root.trialSecondsLeft--;
            if (root.trialSecondsLeft <= 0) {
                root.revertTrial(finished => {
                    root.fail(i18n("No confirmation for %1, so the widget went back and removed the custom mode. If the monitor stayed black, lower the custom mode refresh rate in the widget settings and try again.",
                                   finished.name));
                });
            }
        }
    }

    Timer {
        id: refreshTimer

        interval: 300

        onTriggered: root.refresh()
    }

    // Picks up changes made outside the widget, such as in System Settings.
    Instantiator {
        model: Qt.application.screens

        delegate: QtObject {
            required property var modelData
            readonly property size screenSize: Qt.size(modelData.width, modelData.height)

            onScreenSizeChanged: refreshTimer.restart()
        }

        onObjectAdded: refreshTimer.restart()
        onObjectRemoved: refreshTimer.restart()
    }
}

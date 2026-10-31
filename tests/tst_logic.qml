import QtQuick
import QtTest

import "../package/contents/code/logic.js" as Logic

TestCase {
    name: "Logic"

    function mode(id, width, height, refreshRate) {
        return { id: id, size: { width: width, height: height }, refreshRate: refreshRate };
    }

    function output(name, priority, x, y, currentModeId, modes) {
        return {
            name: name,
            priority: priority,
            enabled: true,
            connected: true,
            rotation: 1,
            scale: 1,
            pos: { x: x, y: y },
            currentModeId: currentModeId,
            modes: modes,
        };
    }

    function ultrawide(x) {
        return output("DP-2", 1, x, 0, "12", [
            mode("11", 3440, 1440, 60),
            mode("12", 3440, 1440, 143.92),
            mode("13", 3440, 1440, 99.99),
            mode("33", 2560, 1440, 143.91),
        ]);
    }

    function side(x) {
        return output("DP-3", 2, x, 0, "3", [mode("3", 2560, 1440, 144)]);
    }

    function test_mainOutputIsLowestPriority() {
        compare(Logic.mainOutput([side(0), ultrawide(2560)]).name, "DP-2");
    }

    function test_mainOutputSkipsDisabledOutputs() {
        const main = ultrawide(2560);
        main.enabled = false;
        compare(Logic.mainOutput([side(0), main]).name, "DP-3");
        compare(Logic.mainOutput([]), null);
    }

    function test_bestModePicksHighestRefreshRate() {
        compare(Logic.bestMode(ultrawide(0), 3440, 1440).id, "12");
        compare(Logic.bestMode(ultrawide(0), 1920, 1080), null);
        compare(Logic.bestMode(null, 3440, 1440), null);
    }

    function test_parseResolution() {
        compare(Logic.parseResolution("2560x1440"), { width: 2560, height: 1440 });
        compare(Logic.parseResolution(" 2560 X 1440 "), { width: 2560, height: 1440 });
        compare(Logic.parseResolution("wide"), null);
    }

    function test_presets() {
        const main = ultrawide(0);
        const active = Logic.buildPreset(main, "Ultrawide", "3440x1440");
        verify(active.active);
        compare(active.mode.id, "12");

        const missing = Logic.buildPreset(main, "HD", "1920x1080");
        verify(missing.valid);
        verify(!missing.active);
        compare(missing.mode, null);

        const invalid = Logic.buildPreset(main, "Broken", "wide");
        verify(!invalid.valid);
        verify(!invalid.active);
    }

    function test_toggleGoesToTheOtherPreset() {
        compare(Logic.nextPresetIndex([{ active: true }, { active: false }]), 1);
        compare(Logic.nextPresetIndex([{ active: false }, { active: true }]), 0);
        compare(Logic.nextPresetIndex([{ active: false }, { active: false }]), 0);
    }

    function test_monitorOnTheLeftStaysPut() {
        const main = ultrawide(2560);
        const target = Logic.bestMode(main, 2560, 1440);
        compare(Logic.switchCommand([side(0), main], main, target), "kscreen-doctor 'output.DP-2.mode.33'");
    }

    function test_monitorOnTheRightFollowsTheEdge() {
        const main = ultrawide(0);
        const target = Logic.bestMode(main, 2560, 1440);
        compare(Logic.switchCommand([main, side(3440)], main, target),
                "kscreen-doctor 'output.DP-2.mode.33' 'output.DP-3.position.2560,0'");
    }

    function test_rotatedAndScaledOutputsUseLogicalSize() {
        const main = ultrawide(0);
        main.scale = 2;
        compare(Logic.logicalSize(main, Logic.currentMode(main)), { width: 1720, height: 720 });
        main.scale = 1;
        main.rotation = 2;
        compare(Logic.logicalSize(main, Logic.currentMode(main)), { width: 1440, height: 3440 });
    }

    function test_customModeCommands() {
        compare(Logic.addCustomModeCommand(ultrawide(0), 2560, 1440, 144),
                "kscreen-doctor 'output.DP-2.addCustomMode.2560.1440.144000.reduced'");
        compare(Logic.removeCustomModeCommand(ultrawide(0), 2),
                "kscreen-doctor 'output.DP-2.removeCustomMode.2'");
    }

    function test_customModeCountReadsTheRightOutput() {
        const listing = [
            "Output: 1 DP-3 uuid",
            "\tenabled",
            "\tCustom modes: None",
            "\tGeometry: 0,0 2560x1440",
            "Output: 2 DP-2 uuid",
            "\tenabled",
            "\t\x1b[32mCustom modes:\x1b[0m",
            "\t\t0: 2560x1440@143.91",
            "\t\t1: 1920x1200@60.00",
            "\tGeometry: 2560,0 3440x1440",
        ].join("\n");
        compare(Logic.customModeCount(listing, "DP-2"), 2);
        compare(Logic.customModeCount(listing, "DP-3"), 0);
        compare(Logic.customModeCount(listing, "HDMI-1"), 0);
    }

    function test_parseOutputsRejectsBadOutput() {
        compare(Logic.parseOutputs('{"outputs": []}'), []);
        compare(Logic.parseOutputs("{}"), null);
        compare(Logic.parseOutputs("not json"), null);
    }

    function test_sameModeFindsTheModeAfterItsIdChanged() {
        const main = ultrawide(0);
        const remembered = mode("old-id", 3440, 1440, 99.99);
        compare(Logic.sameMode(main, remembered).id, "13");
        compare(Logic.sameMode(main, mode("x", 1, 1, 60)), null);
    }

    function test_shellQuote() {
        compare(Logic.shellQuote("a'b"), "'a'\\''b'");
    }
}

.pragma library

// Reads `kscreen-doctor -j` output and builds kscreen-doctor commands. Kept free
// of QML types so tests/tst_logic.qml can exercise it directly.

// KScreen::Output::Rotation values that swap an output's width and height.
const ROTATION_LEFT = 2;
const ROTATION_RIGHT = 8;

const queryCommand = "kscreen-doctor -j";
const listCommand = "kscreen-doctor -o";

function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
}

function doctorCommand(settings) {
    return "kscreen-doctor " + settings.map(shellQuote).join(" ");
}

// Returns null when the text is not the JSON kscreen-doctor normally prints.
function parseOutputs(json) {
    try {
        return JSON.parse(json).outputs || null;
    } catch (error) {
        return null;
    }
}

function parseResolution(text) {
    const match = /^\s*(\d+)\s*[x×]\s*(\d+)\s*$/i.exec(text);
    return match ? { width: Number(match[1]), height: Number(match[2]) } : null;
}

function formatResolution(width, height) {
    return width + " x " + height;
}

function formatMode(mode) {
    return formatResolution(mode.size.width, mode.size.height) + " @ " + Math.round(mode.refreshRate) + " Hz";
}

// The main monitor is the enabled output with the lowest priority number, the
// Wayland equivalent of the primary display on Windows.
function mainOutput(outputs) {
    const active = outputs.filter(output => output.enabled && output.connected);
    active.sort((a, b) => a.priority - b.priority);
    return active.length > 0 ? active[0] : null;
}

function currentMode(output) {
    if (!output) {
        return null;
    }
    return output.modes.find(mode => mode.id === output.currentModeId) || null;
}

// Highest refresh rate available at width x height, or null if there is none.
function bestMode(output, width, height) {
    if (!output) {
        return null;
    }
    const matches = output.modes.filter(mode => mode.size.width === width && mode.size.height === height);
    matches.sort((a, b) => b.refreshRate - a.refreshRate);
    return matches.length > 0 ? matches[0] : null;
}

function sameMode(output, mode) {
    return output.modes.find(candidate => candidate.size.width === mode.size.width
        && candidate.size.height === mode.size.height
        && candidate.refreshRate === mode.refreshRate) || null;
}

function buildPreset(output, name, resolution) {
    const size = parseResolution(resolution);
    const mode = size ? bestMode(output, size.width, size.height) : null;
    const current = currentMode(output);
    return {
        name: name,
        valid: size !== null,
        width: size ? size.width : 0,
        height: size ? size.height : 0,
        mode: mode,
        active: size !== null && current !== null
            && current.size.width === size.width && current.size.height === size.height,
    };
}

// Like the tray app: anything other than the first preset goes back to it.
function nextPresetIndex(presets) {
    return presets[0].active ? 1 : 0;
}

function logicalSize(output, mode) {
    const rotated = output.rotation === ROTATION_LEFT || output.rotation === ROTATION_RIGHT;
    return {
        width: Math.round((rotated ? mode.size.height : mode.size.width) / output.scale),
        height: Math.round((rotated ? mode.size.width : mode.size.height) / output.scale),
    };
}

// Monitors right of or below the main one have to follow its new edge, or
// resizing leaves a gap the pointer cannot cross.
function neighbourMoves(outputs, main, target) {
    const from = logicalSize(main, currentMode(main));
    const to = logicalSize(main, target);
    const right = main.pos.x + from.width;
    const bottom = main.pos.y + from.height;

    const moves = [];
    for (const output of outputs) {
        if (output.name === main.name || !output.enabled) {
            continue;
        }
        const x = output.pos.x >= right ? output.pos.x + to.width - from.width : output.pos.x;
        const y = output.pos.y >= bottom ? output.pos.y + to.height - from.height : output.pos.y;
        if (x !== output.pos.x || y !== output.pos.y) {
            moves.push("output." + output.name + ".position." + x + "," + y);
        }
    }
    return moves;
}

function switchCommand(outputs, main, target) {
    const mode = "output." + main.name + ".mode." + target.id;
    return doctorCommand([mode].concat(neighbourMoves(outputs, main, target)));
}

function addCustomModeCommand(output, width, height, refreshRate) {
    const millihertz = refreshRate * 1000;
    return doctorCommand(["output." + output.name + ".addCustomMode." + width + "." + height + "." + millihertz + ".reduced"]);
}

function removeCustomModeCommand(output, index) {
    return doctorCommand(["output." + output.name + ".removeCustomMode." + index]);
}

// `kscreen-doctor -j` does not mark custom modes, so they are counted from the
// `-o` listing. A new mode lands at the end, which gives its removal index.
function customModeCount(listing, outputName) {
    const lines = listing.replace(/\x1b\[[0-9;]*m/g, "").split("\n");
    const start = lines.findIndex(line => line.trim().split(/\s+/)[2] === outputName && line.startsWith("Output:"));
    if (start < 0) {
        return 0;
    }
    let count = 0;
    let inCustomModes = false;
    for (const line of lines.slice(start + 1)) {
        if (line.startsWith("Output:")) {
            break;
        }
        if (inCustomModes && !/^\s+\d+:/.test(line)) {
            break;
        }
        if (inCustomModes) {
            count++;
        } else if (/^\s+Custom modes:\s*$/.test(line)) {
            inCustomModes = true;
        }
    }
    return count;
}

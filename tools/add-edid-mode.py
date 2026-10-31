#!/usr/bin/env python3
"""Writes a copy of a monitor's EDID with a narrower resolution added.

NVIDIA's driver refuses modes that are not in the EDID, so KWin custom modes fail
on it. This adds the resolution to the EDID instead. It only reads the monitor's
EDID and writes a new file; applying that file is a separate step, see the README.

Each new mode copies one of the monitor's own timings and shortens only the visible
line width. The line rate and refresh rate stay the same, which gives the monitor
the best chance of accepting a mode it never advertised.

Generated files contain the monitor's serial number, so don't publish them.
"""

import argparse
import glob
import re
import subprocess
import sys

BLOCK_SIZE = 128
DTD_SIZE = 18
CTA_TAG = 0x02
DISPLAYID_TAG = 0x70
DISPLAYID_TIMING_TYPE_1 = 0x03
DISPLAYID_TIMING_SIZE = 20
# DTDs store the pixel clock in 10 kHz units in 16 bits.
MAX_DTD_CLOCK_KHZ = 655350


def parse_dtd(data):
    """Returns the timing in an 18 byte DTD, or None for a display descriptor."""
    clock = int.from_bytes(data[0:2], "little") * 10
    if clock == 0:
        return None
    return {
        "clock_khz": clock,
        "hactive": data[2] | (data[4] & 0xF0) << 4,
        "hblank": data[3] | (data[4] & 0x0F) << 8,
        "vactive": data[5] | (data[7] & 0xF0) << 4,
        "vblank": data[6] | (data[7] & 0x0F) << 8,
        "hfront": data[8] | (data[11] & 0xC0) << 2,
        "hsync": data[9] | (data[11] & 0x30) << 4,
        "vfront": data[10] >> 4 | (data[11] & 0x0C) << 2,
        "vsync": data[10] & 0x0F | (data[11] & 0x03) << 4,
        "himage": data[12] | (data[14] & 0xF0) << 4,
        "vimage": data[13] | (data[14] & 0x0F) << 8,
        "flags": data[17],
    }


def parse_displayid_timing(data):
    """Returns the timing in a 20 byte DisplayID type 1 detailed timing."""
    word = lambda offset: int.from_bytes(data[offset:offset + 2], "little")
    return {
        "clock_khz": (int.from_bytes(data[0:3], "little") + 1) * 10,
        "hactive": word(4) + 1,
        "hblank": word(6) + 1,
        "hfront": (word(8) & 0x7FFF) + 1,
        "hsync": word(10) + 1,
        "vactive": word(12) + 1,
        "vblank": word(14) + 1,
        "vfront": (word(16) & 0x7FFF) + 1,
        "vsync": word(18) + 1,
        # Digital separate sync, with the source's polarities.
        "flags": 0x18 | (word(16) >> 15) << 2 | (word(8) >> 15) << 1,
        "himage": None,
        "vimage": None,
    }


def encode_dtd(timing):
    return bytes([
        timing["clock_khz"] // 10 & 0xFF,
        timing["clock_khz"] // 10 >> 8,
        timing["hactive"] & 0xFF,
        timing["hblank"] & 0xFF,
        timing["hactive"] >> 8 << 4 | timing["hblank"] >> 8,
        timing["vactive"] & 0xFF,
        timing["vblank"] & 0xFF,
        timing["vactive"] >> 8 << 4 | timing["vblank"] >> 8,
        timing["hfront"] & 0xFF,
        timing["hsync"] & 0xFF,
        (timing["vfront"] & 0x0F) << 4 | timing["vsync"] & 0x0F,
        timing["hfront"] >> 8 << 6 | timing["hsync"] >> 8 << 4
            | timing["vfront"] >> 4 << 2 | timing["vsync"] >> 4,
        timing["himage"] & 0xFF,
        timing["vimage"] & 0xFF,
        timing["himage"] >> 8 << 4 | timing["vimage"] >> 8,
        0,
        0,
        timing["flags"],
    ])


def block_timings(block):
    """Yields every detailed timing in one EDID block."""
    if block[0] == CTA_TAG:
        for offset in range(block[2], 127 - DTD_SIZE, DTD_SIZE):
            timing = parse_dtd(block[offset:offset + DTD_SIZE])
            if timing is None:
                break
            yield timing
    elif block[0] == DISPLAYID_TAG:
        offset = 5
        end = 5 + block[2]
        while offset + 3 <= end:
            tag, length = block[offset], block[offset + 2]
            if tag == DISPLAYID_TIMING_TYPE_1:
                for start in range(offset + 3, offset + 3 + length, DISPLAYID_TIMING_SIZE):
                    yield parse_displayid_timing(block[start:start + DISPLAYID_TIMING_SIZE])
            offset += 3 + length


def all_timings(edid):
    for offset in (54, 72, 90, 108):
        timing = parse_dtd(edid[offset:offset + DTD_SIZE])
        if timing is not None:
            yield timing
    for start in range(BLOCK_SIZE, len(edid), BLOCK_SIZE):
        yield from block_timings(edid[start:start + BLOCK_SIZE])


def refresh_rate(timing):
    total = (timing["hactive"] + timing["hblank"]) * (timing["vactive"] + timing["vblank"])
    return timing["clock_khz"] * 1000 / total


def narrowed(source, width, reference):
    """Copies a timing at a smaller width, keeping its line rate and refresh rate."""
    total = source["hactive"] + source["hblank"]
    timing = dict(source)
    timing["hactive"] = width
    timing["clock_khz"] = round(source["clock_khz"] * (width + source["hblank"]) / total / 10) * 10
    # Physical size scales with the width, since the panel keeps its pixel pitch.
    timing["himage"] = round(reference["himage"] * width / reference["hactive"])
    timing["vimage"] = reference["vimage"]
    return timing


def find_edid(connector):
    paths = glob.glob(f"/sys/class/drm/card*-{connector}/edid")
    if len(paths) != 1:
        sys.exit(f"Expected one EDID for {connector}, found {len(paths)}.")
    return paths[0]


def issues(path):
    """Returns edid-decode's complaints with numbers removed.

    Factory EDIDs often fail its checks, so only a comparison means anything, and
    a range that moved slightly should not read as a new problem.
    """
    check = subprocess.run(["edid-decode", "--check", path], capture_output=True, text=True)
    start = re.search(r"^(Warnings|Failures):", check.stdout, re.MULTILINE)
    report = check.stdout[start.start():] if start else ""
    return {re.sub(r"[\d.]+", "#", line.strip()) for line in report.splitlines() if line.strip()}


def add_modes(edid, width, height):
    timings = list(all_timings(edid))
    if any(t["hactive"] == width and t["vactive"] == height for t in timings):
        sys.exit(f"The EDID already has a {width}x{height} timing.")

    sources = [t for t in timings if t["vactive"] == height and t["hactive"] > width]
    if not sources:
        sys.exit(f"The EDID has no wider timing with a height of {height} to base {width}x{height} on.")
    reference = next(t for t in timings if t["himage"])

    start = next((s for s in range(BLOCK_SIZE, len(edid), BLOCK_SIZE) if edid[s] == CTA_TAG), None)
    if start is None:
        sys.exit("The EDID has no CTA block to add timings to.")
    block = edid[start:start + BLOCK_SIZE]
    offset = block[2] + DTD_SIZE * len(list(block_timings(block)))

    # Fastest first, so the slower modes are the ones left out if space runs out.
    added = []
    for source in sorted(sources, key=refresh_rate, reverse=True):
        timing = narrowed(source, width, reference)
        if timing["clock_khz"] > MAX_DTD_CLOCK_KHZ:
            print(f"Skipping {refresh_rate(timing):.2f} Hz: its pixel clock does not fit in a DTD.")
            continue
        if offset + DTD_SIZE > 127:
            print(f"Skipping {refresh_rate(timing):.2f} Hz: the CTA block is full.")
            continue
        block[offset:offset + DTD_SIZE] = encode_dtd(timing)
        offset += DTD_SIZE
        added.append(timing)

    if not added:
        sys.exit("No timing could be added.")
    block[127] = -sum(block[:127]) & 0xFF
    edid[start:start + BLOCK_SIZE] = block
    return added


def main():
    parser = argparse.ArgumentParser(description="Add a resolution to a copy of a monitor's EDID.")
    parser.add_argument("connector", help="connector name, such as DP-2")
    parser.add_argument("resolution", help="resolution to add, such as 2560x1440")
    parser.add_argument("output", help="file to write")
    args = parser.parse_args()

    width, height = (int(part) for part in args.resolution.lower().split("x"))
    source = find_edid(args.connector)
    with open(source, "rb") as file:
        edid = bytearray(file.read())
    added = add_modes(edid, width, height)

    with open(args.output, "wb") as file:
        file.write(edid)

    for timing in added:
        line_rate = timing["clock_khz"] / (timing["hactive"] + timing["hblank"])
        print(f"Added {width}x{height} @ {refresh_rate(timing):.2f} Hz "
              f"({timing['clock_khz'] / 1000:.2f} MHz, {line_rate:.3f} kHz)")

    new_issues = issues(args.output) - issues(source)
    print("New EDID problems:", ", ".join(sorted(new_issues)) if new_issues else "none")


if __name__ == "__main__":
    main()

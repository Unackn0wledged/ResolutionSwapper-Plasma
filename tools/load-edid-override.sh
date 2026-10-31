#!/bin/sh
# Loads /etc/resolution-swapper/<connector>.bin as that connector's EDID override.
# Runs at boot from resolution-swapper-edid@.service.
connector=$1
file=/etc/resolution-swapper/$connector.bin

# The GPU driver may still be loading when this starts.
for attempt in $(seq 1 50); do
    dir=$(ls -d /sys/kernel/debug/dri/*/"$connector" 2>/dev/null | head -1)
    [ -n "$dir" ] && break
    sleep 0.2
done
if [ -z "$dir" ]; then
    echo "No $connector connector found." >&2
    exit 1
fi

# The base block is untouched by add-edid-mode.py, so it identifies the monitor.
# It is empty until the connector has been probed, which is fine to skip.
current=$(ls /sys/class/drm/card*-"$connector"/edid | head -1)
if [ "$(head -c 128 "$current" | wc -c)" -eq 128 ] && ! cmp -s -n 128 "$current" "$file"; then
    echo "A different monitor is on $connector, leaving its EDID alone."
    exit 0
fi

cat "$file" > "$dir/edid_override"

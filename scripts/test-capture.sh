#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Set up the IPU4P media pipeline and capture RAW frames.
#
#   ./scripts/test-capture.sh front   # ov5693 2592x1944
#   ./scripts/test-capture.sh rear    # ov8865 3264x2448
#
# Verified working on a Surface Pro 7 with kernel 7.2.9-2-cachyos-surface-latest
# after loading the intel_ipu4 stack (see README section 5).
#
# Writes RAW10 (SBGGR10_1X10) frames. Render them with scripts/raw2png.py.
# Note the CSI-2 BE SOC path is used: the per-CSI-2 direct capture nodes emit
# MIPI packet dumps rather than raster frames.

set -euo pipefail

CAM="${1:-front}"
case "$CAM" in
front)
	SENSOR_RE=ov5693
	RES=2592x1944
	FMT=SBGGR10_1X10
	PIXFMT=BG10
	;;
rear)
	SENSOR_RE=ov8865
	RES=3264x2448
	FMT=SBGGR10_1X10
	PIXFMT=BG10
	;;
ir)
	# OV7251 IR: 10-bit greyscale, single plane, no Bayer pattern.
	SENSOR_RE=ov7251
	RES=640x480
	FMT=Y10_1X10
	PIXFMT="Y10 "	# fourcc really does end in a space
	;;
*)
	echo "usage: $0 [front|rear|ir]" >&2
	exit 2
	;;
esac
# These links are registered MEDIA_LNK_FL_DYNAMIC (0x4); media-ctl passes the
# requested flags to MEDIA_IOC_SETUP_LINK verbatim, so keep that bit while
# enabling (0x4 | MEDIA_LNK_FL_ENABLED).
DYN_ENABLED=5
FRAMES="${FRAMES:-3}"
OUT="${OUT:-/var/tmp/${CAM}.raw}"

MD=""
for c in /dev/media*; do
	[ -e "$c" ] || continue
	media-ctl -d "$c" -p 2>/dev/null | grep "$SENSOR_RE" >/dev/null || continue
	MD="$c"
	break
done
[ -n "$MD" ] || { echo "no media device contains $SENSOR_RE" >&2; exit 1; }

G=$(media-ctl -d "$MD" -p)
SENSOR=$(printf '%s\n' "$G" | awk -v re="$SENSOR_RE" \
	'$0 ~ "- entity .*: " re { name=$0; sub(/.*: /,"",name); sub(/ \(.*/,"",name); print name; exit }')
PORT=$(printf '%s\n' "$G" | awk -v re="$SENSOR_RE" \
	'$0 ~ "- entity .*: " re { hit=1 } hit && /-> "Intel IPU4 CSI-2 [0-9]+":0/ { match($0,/CSI-2 [0-9]+/); print substr($0,RSTART+6,RLENGTH-6); exit }')
[ -n "$SENSOR" ] && [ -n "$PORT" ] || { echo "could not resolve $SENSOR_RE entity / CSI-2 port" >&2; exit 1; }

SUB=$(media-ctl -d "$MD" -e "$SENSOR")
CAP=$(media-ctl -d "$MD" -e "Intel IPU4 BE SOC capture 0")
W=${RES%x*}
H=${RES#*x}

echo "media=$MD sensor='$SENSOR' ($SUB) csi-port=$PORT capture=$CAP $RES"

media-ctl -d "$MD" -r
media-ctl -d "$MD" -V "\"$SENSOR\":0 [fmt:$FMT/$RES]"
media-ctl -d "$MD" -V "\"Intel IPU4 CSI-2 $PORT\":0 [fmt:$FMT/$RES]"
media-ctl -d "$MD" -V "\"Intel IPU4 CSI-2 $PORT\":1 [fmt:$FMT/$RES]"
media-ctl -d "$MD" -l "\"$SENSOR\":0 -> \"Intel IPU4 CSI-2 $PORT\":0 [1]"
media-ctl -d "$MD" -l "\"Intel IPU4 CSI-2 $PORT\":1 -> \"Intel IPU4 CSI2 BE SOC\":0 [$DYN_ENABLED]"
media-ctl -d "$MD" -l "\"Intel IPU4 CSI2 BE SOC\":8 -> \"Intel IPU4 BE SOC capture 0\":0 [$DYN_ENABLED]"
media-ctl -d "$MD" -V "\"Intel IPU4 CSI2 BE SOC\":0 [fmt:$FMT/$RES]"
media-ctl -d "$MD" -V "\"Intel IPU4 CSI2 BE SOC\":8 [fmt:$FMT/$RES]"

# The sensor comes up at default analogue gain and the first frame after
# stream start is always a flat pedestal frame, hence --stream-count >= 2.
# All three sensor drivers expose the standard V4L2_CID_ANALOGUE_GAIN
# (ov7251 was moved off the non-standard V4L2_CID_GAIN so libcamera accepts it).
if [ -n "${GAIN:-}" ]; then
	v4l2-ctl -d "$SUB" --set-ctrl "analogue_gain=$GAIN"
fi

echo "capturing $FRAMES frame(s) -> $OUT"
timeout "${TIMEOUT:-60}" v4l2-ctl -d "$CAP" \
	--set-fmt-video=width="$W",height="$H",pixelformat="$PIXFMT" \
	--stream-mmap=4 --stream-count="$FRAMES" --stream-to="$OUT"

ls -l "$OUT"
echo "expected size: $((W * H * 2 * FRAMES)) bytes"

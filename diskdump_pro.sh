#!/bin/bash

echo "======================================"
echo " FORENSIC ACQUISITION TOOL v4 FIXED STABLE"
echo "======================================"

set -e

# =========================
# INTERNET / TOOLS
# =========================

echo ""
echo "🌐 Check internet..."

if ping -c 1 8.8.8.8 &>/dev/null; then
    echo "✔ Internet OK"
    sudo apt update -y >/dev/null 2>&1 || echo "⚠️ apt update failed (ignored)"

    for pkg in pigz lz4 pv; do
        command -v $pkg >/dev/null 2>&1 || sudo apt install -y $pkg
    done
else
    echo "⚠️ Offline mode"
fi

# =========================
# DISK
# =========================

echo ""
echo "📀 DISKS:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

echo ""
read -p "Select source (/dev/sdX): " SRC

[ ! -b "$SRC" ] && echo "❌ Invalid device" && exit 1

echo "✔ Source: $SRC"

# =========================
# CASE
# =========================

read -p "Case name: " CASE_NAME
[ -z "$CASE_NAME" ] && exit 1

# =========================
# DEST
# =========================

echo ""
echo "Destination:"
echo "1) Netcat"
echo "2) File"
echo "3) NFS"
read -p "Choice: " DST

SERVER=""
PORT=""
DEST=""

if [ "$DST" == "3" ]; then
    NFS=$(findmnt -rn -t nfs,nfs4 -o TARGET)

    [ -z "$NFS" ] && echo "❌ No NFS mounts" && exit 1

    echo "$NFS"
    read -p "Select mount: " DEST

elif [ "$DST" == "2" ]; then
    read -p "Output dir: " DEST

elif [ "$DST" == "1" ]; then
    read -p "Server IP: " SERVER
    read -p "Port: " PORT
fi

# =========================
# OPTIONS
# =========================

read -p "Block size (default 4M): " BS
BS=${BS:-4M}

echo ""
echo "Compression: 1 raw / 2 gzip / 3 pigz / 4 zstd / 5 lz4"
read -p "Choice: " COMP

echo ""
echo "Hash (no/md5/sha256): "
read -p "Choice: " HASH

# =========================
# OUTPUT
# =========================

TS=$(date +%Y%m%d_%H%M%S)
BASE_DIR="${DEST:-/tmp}/case_${CASE_NAME}_${TS}"

mkdir -p "$BASE_DIR" || exit 1

IMG="${CASE_NAME}_${TS}"
OUT_FILE="$BASE_DIR/${IMG}.img"
HASH_FILE="$BASE_DIR/${IMG}.hash"
RESTORE="$BASE_DIR/${IMG}_restore.sh"

# =========================
# NETCAT INFO
# =========================

if [ "$DST" == "1" ]; then
    echo ""
    echo "======================================"
    echo "RUN ON SERVER:"
    echo "nc -l -p $PORT > ${IMG}.img"
    echo "======================================"
fi

read -p "Start acquisition? (y/N): " OK
[[ "$OK" != "y" ]] && exit 0

# =========================
# ACQUISITION
# =========================

echo ""
echo "🚀 Acquiring..."

DD="dd if=$SRC bs=$BS status=progress"

if [ "$DST" == "1" ]; then

    case $COMP in
        1) $DD | nc "$SERVER" "$PORT" ;;
        2) $DD | gzip -1 | nc "$SERVER" "$PORT" ;;
        3) $DD | pigz -1 | nc "$SERVER" "$PORT" ;;
        4) $DD | zstd -T0 -3 | nc "$SERVER" "$PORT" ;;
        5) $DD | lz4 | nc "$SERVER" "$PORT" ;;
    esac

else

    case $COMP in
        1) $DD > "$OUT_FILE" ;;
        2) $DD | gzip -1 > "$OUT_FILE.gz" ;;
        3) $DD | pigz -1 > "$OUT_FILE.gz" ;;
        4) $DD | zstd -T0 -3 > "$OUT_FILE.zst" ;;
        5) $DD | lz4 > "$OUT_FILE.lz4" ;;
    esac

fi

# =========================
# SAFE SYNC
# =========================

sync
sync

# =========================
# HASH (FIXED SAFE)
# =========================

if [ "$DST" != "1" ]; then

    FINAL_FILE=""

    if [ -f "$OUT_FILE" ]; then
        FINAL_FILE="$OUT_FILE"
    elif [ -f "$OUT_FILE.gz" ]; then
        FINAL_FILE="$OUT_FILE.gz"
    elif [ -f "$OUT_FILE.zst" ]; then
        FINAL_FILE="$OUT_FILE.zst"
    elif [ -f "$OUT_FILE.lz4" ]; then
        FINAL_FILE="$OUT_FILE.lz4"
    fi

    if [ -n "$FINAL_FILE" ]; then

        echo "🧾 Hashing: $FINAL_FILE"

        if [ "$HASH" == "md5" ]; then
            md5sum "$FINAL_FILE" > "$HASH_FILE"
        elif [ "$HASH" == "sha256" ]; then
            sha256sum "$FINAL_FILE" > "$HASH_FILE"
        fi

    else
        echo "⚠️ No file to hash (netcat mode or missing output)"
    fi
fi

# =========================
# RESTORE
# =========================

echo ""
echo "🧾 Creating restore script..."

case $COMP in
    1) CMD="dd if=IMAGE of=$SRC bs=$BS status=progress" ;;
    2) CMD="gzip -d -c IMAGE | dd of=$SRC bs=$BS status=progress" ;;
    3) CMD="pigz -d -c IMAGE | dd of=$SRC bs=$BS status=progress" ;;
    4) CMD="zstd -d -c IMAGE | dd of=$SRC bs=$BS status=progress" ;;
    5) CMD="lz4 -d IMAGE | dd of=$SRC bs=$BS status=progress" ;;
esac

cat > "$RESTORE" <<EOF
#!/bin/bash
echo "RESTORE START"
$CMD
sync
echo "DONE"
EOF

chmod +x "$RESTORE"

# =========================
# DONE
# =========================

echo ""
echo "======================================"
echo "✔ DONE"
echo "CASE: $BASE_DIR"
echo "IMAGE: $OUT_FILE"
[ -f "$HASH_FILE" ] && echo "HASH: $HASH_FILE"
echo "RESTORE: $RESTORE"
echo "======================================"
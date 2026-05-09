#!/bin/sh
set -eu

ZT_VERSION="${ZT_VERSION:-1.16.0}"
BUILD_ROOT="${BUILD_ROOT:-/root/build}"
PREFIX="${PREFIX:-/usr/local}"
ZT_HOME="${ZT_HOME:-/var/db/zerotier-one}"

SRC_DIR="${BUILD_ROOT}/ZeroTierOne-${ZT_VERSION}"
ARCHIVE="${BUILD_ROOT}/ZeroTierOne-${ZT_VERSION}.tar.gz"
URL="https://github.com/zerotier/ZeroTierOne/archive/refs/tags/${ZT_VERSION}.tar.gz"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATCH_FILE="${SCRIPT_DIR}/patches/openbsd-managed-ip-multicast-subscriptions.patch"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root or with doas" >&2
	exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
	echo "missing patch: $PATCH_FILE" >&2
	exit 1
fi

pkg_add -I gmake

mkdir -p "$BUILD_ROOT"

if [ -d "$SRC_DIR" ]; then
	mv "$SRC_DIR" "${SRC_DIR}.bak.$(date +%Y%m%d%H%M%S)"
fi

ftp -o "$ARCHIVE" "$URL"
tar -xzf "$ARCHIVE" -C "$BUILD_ROOT"

cd "$SRC_DIR"
patch -p1 < "$PATCH_FILE"
gmake -j"$JOBS"

install -d -o root -g wheel -m 755 "${PREFIX}/sbin"
if [ -f "${PREFIX}/sbin/zerotier-one" ]; then
	cp "${PREFIX}/sbin/zerotier-one" "${PREFIX}/sbin/zerotier-one.bak.$(date +%Y%m%d%H%M%S)"
fi
install -m 0755 -o root -g wheel zerotier-one "${PREFIX}/sbin/zerotier-one"
ln -sf "${PREFIX}/sbin/zerotier-one" "${PREFIX}/sbin/zerotier-cli"
ln -sf "${PREFIX}/sbin/zerotier-one" "${PREFIX}/sbin/zerotier-idtool"

install -d -o root -g wheel -m 700 "$ZT_HOME"

cat > /etc/rc.d/zerotier_one <<EOF
#!/bin/ksh

daemon="${PREFIX}/sbin/zerotier-one"
daemon_flags="-d ${ZT_HOME}"
daemon_timeout=60

. /etc/rc.d/rc.subr

pexp="${PREFIX}/sbin/zerotier-one.*"
rc_reload=NO

rc_pre() {
	install -d -o root -g wheel -m 700 ${ZT_HOME}
}

rc_cmd \$1
EOF

chown root:wheel /etc/rc.d/zerotier_one
chmod 555 /etc/rc.d/zerotier_one

rcctl enable zerotier_one
rm -f "${ZT_HOME}/zerotier-one.pid" "${ZT_HOME}/zerotier-one.port"

if rcctl check zerotier_one >/dev/null 2>&1; then
	rcctl restart zerotier_one
else
	rcctl start zerotier_one
fi

sleep 3
"${PREFIX}/sbin/zerotier-one" -v
"${PREFIX}/sbin/zerotier-cli" status || true
rcctl check zerotier_one


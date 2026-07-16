#!/bin/sh
set -eu

ZT_VERSION="${ZT_VERSION:-1.16.2}"
BUILD_ROOT="${BUILD_ROOT:-/root/build}"
PREFIX="${PREFIX:-/usr/local}"
ZT_HOME="${ZT_HOME:-/var/db/zerotier-one}"
BUILD_ONLY="${BUILD_ONLY:-0}"

SRC_DIR="${BUILD_ROOT}/ZeroTierOne-${ZT_VERSION}"
ARCHIVE="${BUILD_ROOT}/ZeroTierOne-${ZT_VERSION}.tar.gz"
URL="https://github.com/zerotier/ZeroTierOne/archive/refs/tags/${ZT_VERSION}.tar.gz"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PATCH_FILES="
${SCRIPT_DIR}/patches/openbsd-managed-ip-multicast-subscriptions.patch
${SCRIPT_DIR}/patches/openbsd-tap-reader-failure-handling.patch
"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)

if [ "$(id -u)" -ne 0 ]; then
	echo "run as root or with doas" >&2
	exit 1
fi

for patch_file in $PATCH_FILES; do
	if [ ! -f "$patch_file" ]; then
		echo "missing patch: $patch_file" >&2
		exit 1
	fi
done

if ! command -v gmake >/dev/null 2>&1; then
	pkg_add -I gmake
fi

mkdir -p "$BUILD_ROOT"

if [ -d "$SRC_DIR" ]; then
	mv "$SRC_DIR" "${SRC_DIR}.bak.$(date +%Y%m%d%H%M%S)"
fi

ftp -o "$ARCHIVE" "$URL"
tar -xzf "$ARCHIVE" -C "$BUILD_ROOT"

cd "$SRC_DIR"
for patch_file in $PATCH_FILES; do
	patch -p1 < "$patch_file"
done
gmake -j"$JOBS"
./zerotier-one -v

if [ "$BUILD_ONLY" = "1" ]; then
	echo "build completed: ${SRC_DIR}/zerotier-one"
	exit 0
fi

install -d -o root -g wheel -m 755 "${PREFIX}/sbin"
install -d -o root -g wheel -m 755 "${PREFIX}/bin"
BACKUP_BINARY=""
if [ -f "${PREFIX}/sbin/zerotier-one" ]; then
	BACKUP_BINARY="${PREFIX}/sbin/zerotier-one.bak.$(date +%Y%m%d%H%M%S)"
	cp -p "${PREFIX}/sbin/zerotier-one" "$BACKUP_BINARY"
fi
install -m 0755 -o root -g wheel zerotier-one "${PREFIX}/sbin/zerotier-one"
ln -sf "${PREFIX}/sbin/zerotier-one" "${PREFIX}/sbin/zerotier-cli"
ln -sf "${PREFIX}/sbin/zerotier-one" "${PREFIX}/bin/zerotier-idtool"

install -d -o root -g wheel -m 700 "$ZT_HOME"

cat > /etc/rc.d/zerotier_one <<EOF
#!/bin/ksh

# ZeroTier One built from source on OpenBSD.

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

if rcctl check zerotier_one >/dev/null 2>&1; then
	SERVICE_ACTION=restart
else
	SERVICE_ACTION=start
	rm -f "${ZT_HOME}/zerotier-one.pid" "${ZT_HOME}/zerotier-one.port"
fi

if ! rcctl "$SERVICE_ACTION" zerotier_one; then
	if [ -n "$BACKUP_BINARY" ]; then
		rcctl stop zerotier_one >/dev/null 2>&1 || true
		install -m 0755 -o root -g wheel "$BACKUP_BINARY" "${PREFIX}/sbin/zerotier-one"
		rm -f "${ZT_HOME}/zerotier-one.pid" "${ZT_HOME}/zerotier-one.port"
		rcctl start zerotier_one
	fi
	echo "ZeroTier service failed after installation; the previous binary was restored when available" >&2
	exit 1
fi

sleep 3
"${PREFIX}/sbin/zerotier-one" -v
"${PREFIX}/sbin/zerotier-cli" status || true
if ! rcctl check zerotier_one; then
	if [ -n "$BACKUP_BINARY" ]; then
		rcctl stop zerotier_one >/dev/null 2>&1 || true
		install -m 0755 -o root -g wheel "$BACKUP_BINARY" "${PREFIX}/sbin/zerotier-one"
		rm -f "${ZT_HOME}/zerotier-one.pid" "${ZT_HOME}/zerotier-one.port"
		rcctl start zerotier_one
	fi
	echo "ZeroTier health check failed after installation; the previous binary was restored when available" >&2
	exit 1
fi

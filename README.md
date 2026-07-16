# ZeroTierOne for OpenBSD

Build and install upstream ZeroTierOne 1.16.2 with two OpenBSD-specific source patches.

## Overview

ZeroTierOne source code is not vendored in this repository. `install.sh` downloads the selected upstream release archive, applies the patches in a fixed order, builds the daemon with `gmake`, validates the resulting binary, installs it, and registers an OpenBSD `rc.d` service.

The patch set is maintained against ZeroTierOne 1.16.2. `ZT_VERSION` can select another release, but a different release is not supported until both patches have been checked against that source tree.

## Included Source Changes

### Managed IP multicast subscriptions

`patches/openbsd-managed-ip-multicast-subscriptions.patch` changes `osdep/BSDEthernetTap.cpp` and `osdep/BSDEthernetTap.hpp`.

- Adds `BSDEthernetTap::_assignedIps` as an in-process record of addresses successfully assigned through ZeroTier.
- Updates `addIp()` only after `ifconfig` succeeds, replaces same-address entries, sorts the cache, and invalidates the interface-address cache.
- Updates `removeIp()` only after the operating-system removal succeeds and invalidates the interface-address cache.
- Merges managed addresses into `ips()` without duplicating addresses reported by `getifaddrs(3)`.
- Makes managed IPv4 addresses available to `scanMulticastGroups()`, allowing the existing address-resolution group derivation to retain the ARP multicast subscription required by ZeroTier peers.

ZeroTierOne 1.16.2 already erases the unused tail produced by `std::unique()` in `ips()` and `scanMulticastGroups()`. Earlier versions of this repository patched those calls locally; the 1.16.2 patch no longer duplicates the upstream fix.

### TAP reader failure handling

`patches/openbsd-tap-reader-failure-handling.patch` changes `osdep/BSDEthernetTap.cpp` on OpenBSD.

- Reinitializes the `fd_set` before each `select(2)` call and checks the return value.
- Retries interrupted operations immediately.
- Retries `EAGAIN`, `EWOULDBLOCK`, and `ETIMEDOUT` read failures with bounded backoff from 10 ms through 640 ms.
- Logs the first transient read failure and all terminal reader failures to syslog and standard error with the interface, operation, errno, and consecutive-failure count.
- Terminates the daemon after eight consecutive transient read failures, a zero-length read, a non-transient read failure such as OpenBSD `EIO`, or a non-interrupted `select(2)` failure.
- Joins the reader threads before closing the TAP and shutdown descriptors, preventing descriptor teardown races during normal shutdown.

Fatal TAP reader failures terminate the whole daemon instead of leaving a control-plane process running without a working data plane. Use an external service supervisor or watchdog when automatic restart after such a failure is required.

## Requirements

- OpenBSD
- root privileges
- outbound HTTPS access to GitHub
- the OpenBSD base build toolchain, `ftp`, `tar`, and `patch`
- `pkg_add`; the installer installs `gmake` when it is not already available

## Install

Run as root:

```sh
sh install.sh
```

Or use `doas`:

```sh
doas sh install.sh
```

Default settings:

```sh
ZT_VERSION=1.16.2
BUILD_ROOT=/root/build
PREFIX=/usr/local
ZT_HOME=/var/db/zerotier-one
BUILD_ONLY=0
```

Settings can be overridden in the environment:

```sh
BUILD_ROOT=/tmp/zerotier-build PREFIX=/usr/local sh install.sh
```

To download, patch, build, and validate without installing files or changing service state:

```sh
BUILD_ONLY=1 sh install.sh
```

## Service And Diagnostics

```sh
rcctl check zerotier_one
rcctl start zerotier_one
rcctl restart zerotier_one
rcctl stop zerotier_one
```

Check TAP reader diagnostics in the OpenBSD system log:

```sh
grep 'ZeroTier TAP reader' /var/log/messages
```

Check ZeroTier status through the installed CLI:

```sh
zerotier-cli status
```

## License And Credits

ZeroTierOne remains subject to its upstream license. The source patch files are distributed under MPL-2.0, and repository-local installer and documentation files are distributed under the MIT License described in `LICENSE`.

- ZeroTierOne by ZeroTier, Inc.: https://github.com/zerotier/ZeroTierOne
- OpenBSD installer and OpenBSD source patches: itinfra7

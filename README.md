# ZeroTierOne OpenBSD Installer

Build and install ZeroTierOne 1.16.0 on OpenBSD with an OpenBSD multicast subscription patch.

## Scope

This repository does not vendor ZeroTierOne source code.

The installer downloads the ZeroTierOne 1.16.0 release archive from GitHub, applies the local OpenBSD patch, builds it with `gmake`, installs the binary, and registers an OpenBSD `rc.d` service.

## Why This Patch Exists

ZeroTier uses multicast subscriptions for IPv4 ARP resolution.

On OpenBSD, the unpatched 1.16.0 BSD tap path can miss ZeroTier-managed IP assignments while deriving multicast subscriptions.

When that happens, peers can fail to resolve the OpenBSD node's ZeroTier IPv4 address even though IPv6 still works.

The patch preserves managed IP assignments inside `BSDEthernetTap` and uses them when deriving multicast subscriptions.

## Requirements

- OpenBSD
- root privileges
- outbound HTTPS access to GitHub
- `pkg_add`

## Install

```sh
doas sh install.sh
```

or as root:

```sh
sh install.sh
```

Defaults:

```sh
ZT_VERSION=1.16.0
BUILD_ROOT=/root/build
PREFIX=/usr/local
ZT_HOME=/var/db/zerotier-one
```

Example override:

```sh
BUILD_ROOT=/tmp/build sh install.sh
```

## Service

The installer registers:

```sh
/etc/rc.d/zerotier_one
```

Service commands:

```sh
rcctl check zerotier_one
rcctl start zerotier_one
rcctl restart zerotier_one
rcctl stop zerotier_one
```

## Credits

- ZeroTierOne by ZeroTier, Inc.: https://github.com/zerotier/ZeroTierOne, https://www.zerotier.com
- OpenBSD installer and multicast subscription patch: itinfra7 from GitHub
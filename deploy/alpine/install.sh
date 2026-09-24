#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root on Alpine Linux." >&2
    exit 1
fi
if [ ! -f /etc/alpine-release ]; then
    echo "This installer requires Alpine Linux." >&2
    exit 1
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_dir=$(CDPATH= cd "$script_dir/../.." && pwd)

apk add --no-cache python3
mkdir -p /opt/boltsnip/licensing /root/boltsnip
chmod 700 /root/boltsnip
cp "$repo_dir/bsoio" /opt/boltsnip/bsoio
cp "$repo_dir/licensing/server.py" /opt/boltsnip/licensing/server.py
chmod 755 /opt/boltsnip/bsoio
chmod 644 /opt/boltsnip/licensing/server.py

if [ -e /usr/local/bin/bsoio ] && [ ! -L /usr/local/bin/bsoio ]; then
    echo "Cannot replace the existing /usr/local/bin/bsoio file." >&2
    exit 1
fi
if [ -L /usr/local/bin/bsoio ]; then
    rm /usr/local/bin/bsoio
fi
ln -s /opt/boltsnip/bsoio /usr/local/bin/bsoio

cp "$script_dir/bsoio.initd" /etc/init.d/bsoio
chmod 755 /etc/init.d/bsoio
rc-update add bsoio default
if rc-service bsoio status >/dev/null 2>&1; then
    rc-service bsoio restart
else
    rc-service bsoio start
fi

echo "Installed. Run 'bsoio' to list codes, 'bsoio c' to create one, or 'bsoio d MyLicense' for a custom code."
echo "The database stays at /root/boltsnip/licenses.db across code updates."

#!/bin/bash -ex
#
# networking.sh - Prepare image to boot with cloud-init
#
# Author: Alexsander de Souza <alexsander.souza@canonical.com>
# Author: Alan Baghumian <alan.baghumian@canonical.com>
#
# Copyright (C) 2023 Canonical
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
export DEBIAN_FRONTEND=noninteractive

# Configure apt proxy if needed.
packer_apt_proxy_config="/etc/apt/apt.conf.d/packer-proxy.conf"
if  [ ! -z  "${http_proxy}" ]; then
  echo "Acquire::http::Proxy \"${http_proxy}\";" >> ${packer_apt_proxy_config}
fi
if  [ ! -z  "${https_proxy}" ]; then
  echo "Acquire::https::Proxy \"${https_proxy}\";" >> ${packer_apt_proxy_config}
fi

apt-get install -qy cloud-init netplan.io python3-serial

cat > /etc/sysctl.d/99-cloudimg-ipv6.conf <<EOF
net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.default.use_tempaddr = 0
EOF

rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
rm -f /etc/cloud/ds-identify.cfg

# Install a dpkg-query wrapper to bypass MAAS netplan.io check
cat > /usr/local/bin/dpkg-query <<EOF
#!/bin/sh
[ "\$1" = '-s' ] && [ "\$2" = 'netplan.io' ] && exit 0
/usr/bin/dpkg-query "\$@"
EOF
chmod 755 /usr/local/bin/dpkg-query


# Debian netplan.io does not have an info parameter, work around it
cat > /usr/local/bin/netplan <<EOF
#!/bin/sh
[ "\$1" = 'info' ] && exit 0
/usr/sbin/netplan "\$@"
EOF
chmod 755 /usr/local/bin/netplan


# This is a super dirty trick to make this work. Debian's cloud-init is
# missing MAAS bindings and this causes the installation to fail the 
# last phase after a reboot. This can be upgraded back to Debian's 
# version after the installation has been completed.
# TODO: Figure a way to upstream the changes.

# Fetch the SHA256 of a file from the Launchpad build API.
# Usage: launchpad_sha256 <launchpad-build-url> <filename>
launchpad_sha256() {
    local build_url="$1"
    local filename="$2"
    # Convert web URL to REST API URL: launchpad.net/ -> api.launchpad.net/1.0/
    local api_url="${build_url/launchpad.net\//api.launchpad.net\/1.0\/}"

    python3 -c "
import urllib.request, json, sys

def fetch_json(url):
    req = urllib.request.Request(url, headers={'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())

api_url, filename = sys.argv[1], sys.argv[2]
build = fetch_json(api_url)
files_url = build.get('files_collection_link', api_url + '/+files')
files = fetch_json(files_url)
for entry in files.get('entries', []):
    if entry.get('filename') == filename:
        sha256 = entry.get('sha256', '')
        if sha256 and len(sha256) == 64:
            print(sha256)
            sys.exit(0)
print('ERROR: sha256 not found for ' + filename, file=sys.stderr)
sys.exit(1)
" "${api_url}" "${filename}"
}

# Bookworm LP#2011454
# These are Ubuntu cloud-init builds with MAAS support that Debian's version lacks.
CLOUD_INIT_23_DEB="cloud-init_23.1.2-0ubuntu0~23.04.1_all.deb"
CLOUD_INIT_23_BUILD="https://launchpad.net/~ubuntu-security/+archive/ubuntu/ubuntu-security-collab/+build/26002103"

CLOUD_INIT_20_DEB="cloud-init_20.1-10-g71af48df-0ubuntu5_all.deb"
CLOUD_INIT_20_BUILD="https://launchpad.net/ubuntu/+source/cloud-init/20.1-10-g71af48df-0ubuntu5/+build/19168684"

if [ ${DEBIAN_VERSION} == '12' ] || [ ${DEBIAN_VERSION} == '13' ]; then
     apt-get -y install python3-netifaces isc-dhcp-client python3-six
     CLOUD_INIT_23_SHA256=$(launchpad_sha256 "${CLOUD_INIT_23_BUILD}" "${CLOUD_INIT_23_DEB}")
     wget "${CLOUD_INIT_23_BUILD}/+files/${CLOUD_INIT_23_DEB}" -O "${CLOUD_INIT_23_DEB}"
     echo "${CLOUD_INIT_23_SHA256}  ${CLOUD_INIT_23_DEB}" | sha256sum -c
     dpkg -i "${CLOUD_INIT_23_DEB}"
     rm "${CLOUD_INIT_23_DEB}"
else
    CLOUD_INIT_20_SHA256=$(launchpad_sha256 "${CLOUD_INIT_20_BUILD}" "${CLOUD_INIT_20_DEB}")
    wget "${CLOUD_INIT_20_BUILD}/+files/${CLOUD_INIT_20_DEB}" -O "${CLOUD_INIT_20_DEB}"
    echo "${CLOUD_INIT_20_SHA256}  ${CLOUD_INIT_20_DEB}" | sha256sum -c
    dpkg -i "${CLOUD_INIT_20_DEB}"
    rm "${CLOUD_INIT_20_DEB}"
fi

# Extra Trixie Specific
if [ ${DEBIAN_VERSION} == '13' ]; then
     # Fix lsb_release for Trixie beta
     grep -q '^VERSION_ID=' /etc/os-release || sed -i '/^VERSION_CODENAME/ a VERSION_ID=13.0' /etc/os-release
     # Another Trixie fix
     truncate --size 0 /etc/apt/sources.list
fi

# Enable the following lines if willing to use Netplan
#echo 'ENABLED=1' > /etc/default/netplan
#systemctl disable networking; systemctl mask networking
#mv /etc/network/{interfaces,interfaces.save}
#systemctl enable systemd-networkd

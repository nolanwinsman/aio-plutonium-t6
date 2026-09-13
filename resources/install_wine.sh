#!/bin/bash

# Clear error helper
fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# Allow i386 Architecture
dpkg --add-architecture i386 && \
apt-get update && \
apt-get install wget gnupg2 software-properties-common -y

apt install -y apt-transport-https

# We will now setup the winehq key and repository
WINEHQ_KEY_URL="https://dl.winehq.org/wine-builds/winehq.key"
wget -nc "$WINEHQ_KEY_URL"
if [ $? -ne 0 ]; then
    fail "failed to access $WINEHQ_KEY_URL - check your internet connection, or the key may have moved"
fi

apt-key add winehq.key && \
add-apt-repository 'deb https://dl.winehq.org/wine-builds/ubuntu/ jammy main'

# Setup key and repository for dependency of wine
OPENSUSE_KEY_URL="https://download.opensuse.org/repositories/Emulators:/Wine:/Debian/xUbuntu_22.04/Release.key"
wget -nv "$OPENSUSE_KEY_URL" -O Release.key
if [ $? -ne 0 ]; then
    fail "failed to access $OPENSUSE_KEY_URL - check your internet connection, or the key may have moved"
fi
apt-key add - < Release.key &&
apt-add-repository 'deb https://download.opensuse.org/repositories/Emulators:/Wine:/Debian/xUbuntu_22.04/ ./'

# Update repository 
apt-get update

## Now we will install wine
apt-get install -y --install-recommends winehq-stable winbind
apt-get install -y xvfb libvulkan1 libgl1-mesa-glx

# Clean key files
rm winehq.key Release.key

wine --version

# Install winetricks
WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"
wget "$WINETRICKS_URL" -O /usr/sbin/winetricks
if [ $? -ne 0 ]; then
    fail "failed to access $WINETRICKS_URL - check your internet connection, or the script may have moved"
fi
chmod a+x /usr/sbin/winetricks
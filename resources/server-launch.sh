#!/bin/bash

PLUTONIUM_DIRECTORY=/t6server/plutonium
SERVER_DIRECTORY=/t6server/server
GAME_FILES_DIR=/t6server/game_files
IW4ADMIN_DIRECTORY=/t6server/admin
DOWNLOAD_DIRECTORY=/t6server/downloaded_files
UPDATER_DIRECTORY=/t6server/updater
STATUS_DIRECTORY=/t6server/status

# Blank SERVER_RCON_PASSWORD must fall back to the image default ('admin'),
# otherwise the rcon_password sed below is skipped and the server runs with an
# empty password (IW4MAdmin/watchdog can't log in).
SERVER_RCON_PASSWORD="${SERVER_RCON_PASSWORD:-admin}"

# Create Directories (redudant as they are created in the Dockerfile)
mkdir -p $PLUTONIUM_DIRECTORY \
         $IW4ADMIN_DIRECTORY \
         $DOWNLOAD_DIRECTORY \
         $UPDATER_DIRECTORY \
         $SERVER_DIRECTORY \
         $STATUS_DIRECTORY

################################################################################
#                              Error Handling                                 #
################################################################################

# Print a clear error and exit
fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# Download a file to a specific destination, failing with a clear message
# download <url> <destination> [extra wget args...]
download() {
    local url="$1"
    local dest="$2"
    shift 2
    echo "Downloading: $url"
    if ! wget "$@" "$url" -O "$dest"; then
        fail "failed to access $url - check your internet connection, or the site/file may be down or moved"
    fi
    echo "Downloaded: $dest"
}

# Download a file into a directory, failing with a clear message
# download_to_dir <url> <directory> [extra wget args...]
download_to_dir() {
    local url="$1"
    local dir="$2"
    shift 2
    echo "Downloading: $url"
    if ! wget "$@" -P "$dir" "$url"; then
        fail "failed to access $url - check your internet connection, or the site/file may be down or moved"
    fi
    echo "Downloaded to: $dir"
}

# Extract a zip into a directory, failing with a clear message
# extract <zipfile> <destination>
extract() {
    local zipfile="$1"
    local dest="$2"
    echo "Extracting: $zipfile"
    if ! unzip -o "$zipfile" -d "$dest"; then
        fail "failed to extract $zipfile - the archive may be corrupt or incomplete"
    fi
    echo "Extracted to: $dest"
}

################################################################################
#                  Server Files Provisioning (LOCAL FILES VERSION)             #
################################################################################
# Instead of downloading a pre-built "T6-Server.zip" (the original source for
# this, vault.our-space.xyz, is no longer reachable), we build the same
# Multiplayer/ + Zombie/ + zone layout the launcher expects directly from the
# user's own legally-obtained game files, mounted read-only at $GAME_FILES_DIR.

echo "Checking plutonium server files, please wait..."

if [ -e $STATUS_DIRECTORY/.sv_files_copied ]; then
    echo "Server files already set up!"
else
    echo "Setting up server files from local game files at $GAME_FILES_DIR..."

    if [ ! -d "$GAME_FILES_DIR/zone" ]; then
        echo "ERROR: '$GAME_FILES_DIR/zone' not found."
        echo "Make sure your merged game files (base game + DLCs) are mounted read-only at $GAME_FILES_DIR."
        exit 1
    fi

    echo "Copying game files into Multiplayer mode folder..."
    if ! mkdir -p "$SERVER_DIRECTORY/Multiplayer" || ! cp -r "$GAME_FILES_DIR"/. "$SERVER_DIRECTORY/Multiplayer/"; then
        fail "could not copy game files into $SERVER_DIRECTORY/Multiplayer - is the drive full or read-only?"
    fi
    rm -rf "$SERVER_DIRECTORY/Multiplayer/zone"
    mkdir -p "$SERVER_DIRECTORY/Multiplayer/main"

    echo "Copying game files into Zombie mode folder..."
    if ! mkdir -p "$SERVER_DIRECTORY/Zombie" || ! cp -r "$GAME_FILES_DIR"/. "$SERVER_DIRECTORY/Zombie/"; then
        fail "could not copy game files into $SERVER_DIRECTORY/Zombie - is the drive full or read-only?"
    fi
    rm -rf "$SERVER_DIRECTORY/Zombie/zone"
    mkdir -p "$SERVER_DIRECTORY/Zombie/main"

    echo "Linking shared zone (fastfiles) folder..."
    if ! ln -sfn "$GAME_FILES_DIR/zone" "$SERVER_DIRECTORY/zone"; then
        fail "could not symlink $GAME_FILES_DIR/zone into $SERVER_DIRECTORY/zone"
    fi

    echo "Server files set up successfully from local game files!"
    touch $STATUS_DIRECTORY/.sv_files_copied
fi


################################################################################
#                             Updater Provisioning                             #
################################################################################

echo "Running updater..."
# Use checkupdater.sh to download the latest updater and run it
if ! bash /t6server/check_updater.sh; then
    fail "the Plutonium updater (check_updater.sh) failed - see the messages above"
fi
echo "Updater finished!"


################################################################################
#                   Server Configuration Files Provisioning                    #
################################################################################

# Download the Server Configuration Files
CONFIG_URL="https://github.com/xerxes-at/T6ServerConfigs/archive/master.zip"
if [ -e $STATUS_DIRECTORY/.sv_cfg_files_downloaded ]; then
    echo "Server config files already downloaded!"
else
    echo "Downloading server config files..."
    download "$CONFIG_URL" "$DOWNLOAD_DIRECTORY/server_configs.zip" -q --show-progress
    touch $STATUS_DIRECTORY/.sv_cfg_files_downloaded
fi

# Extract the Server Config Files
if [ -e $STATUS_DIRECTORY/.sv_cfg_files_extracted ]; then
    echo "Server config files already extracted!"
else
    echo "Extracting server config files..."
    extract "$DOWNLOAD_DIRECTORY/server_configs.zip" "$DOWNLOAD_DIRECTORY/server_configs/"
    touch $STATUS_DIRECTORY/.sv_cfg_files_extracted
fi

# Copy the Server Config Files
if [ -e $STATUS_DIRECTORY/.sv_cfg_files_copied ]; then
    echo "Server config files already copied!"
else
    echo "Copying server config files..."

    # Locate config files
    t6_path=$(find "$DOWNLOAD_DIRECTORY/server_configs/" -type d -name "t6")
    mp_cfg="$t6_path/dedicated.cfg"
    zm_cfg="$t6_path/dedicated_zm.cfg"
    gs_path="$t6_path/gamesettings/"

    # Copy Multiplayer config file
    if [ -z "$mp_cfg" ]; then
        echo "File not found: '$mp_cfg'"
    else
        # Copy the file to the destination directory
        cp "$mp_cfg" "/t6server/server/Multiplayer/main/dedicated.cfg"
        echo "File '$mp_cfg' found and copied to: '/t6server/server/Multiplayer/main/dedicated.cfg'"
    fi

    # Copy Zombie config file
    if [ -z "$zm_cfg" ]; then
        echo "File not found: '$zm_cfg'"
    else
        # Copy the file to the destination directory
        cp "$zm_cfg" "/t6server/server/Zombie/main/dedicated_zm.cfg"
        echo "File '$zm_cfg' found and copied to: '/t6server/server/Zombie/main/dedicated_zm.cfg'"
    fi

    # Copy Game Settings files
    if [ -z "$gs_path" ]; then
        echo "Directory not found: '$gs_path'"
    else
        # Copy the file to the destination directory
        cp -r "$gs_path" "/t6server/plutonium/storage/t6/gamesettings/"
        echo "Directory '$gs_path' found and copied to: '/t6server/plutonium/storage/t6/'"
    fi

    touch $STATUS_DIRECTORY/.sv_cfg_files_copied
fi


################################################################################
#                             Wine Provisioning                                #
################################################################################

# Output Current Wine Version
echo "Current Wine Version:"
wine --version

# rm -rf /root/.wine
# If .wine directory doesn't exist, copy backup
if [ ! -d /root/.wine ];  then
    echo "Wineprefix not found, initialiizing wine" && winecfg && /usr/sbin/winetricks
    echo "Configured Succesfully"
else
    winecfg
fi;


################################################################################
#                             Server Provisioning                              #
################################################################################

MODE_PATH=""
MODE=""
CFG=""

# Define Server Mode
# Default Mode is Zombie ('t6mp' -> Multiplayer | 't6zm' -> Zombie)
if [ "$SERVER_MODE" = "Multiplayer" ]; then
    echo "Server mode is Multiplayer!"
    MODE_PATH="/t6server/server/Multiplayer"
    MODE="t6mp"
    CFG="dedicated.cfg"
    CFG_PATH="$MODE_PATH/main/$CFG"
    ln -sfn /t6server/server/zone /t6server/server/Multiplayer/zone
else
    if [ "$SERVER_MODE" != "Zombie" ]; then
        echo "Invalid Server Mode! Defaulting to Zombie"
    else
        echo "Server mode is Zombie!"
    fi
    MODE="t6zm"
    MODE_PATH="/t6server/server/Zombie"
    CFG="dedicated_zm.cfg"
    CFG_PATH="$MODE_PATH/main/$CFG"
    ln -sfn /t6server/server/zone /t6server/server/Zombie/zone
fi

# Define if server will run in LAN mode
if [ "$LAN_MODE" = "true" ]; then
    LAN="-lan"
else
    LAN=""
fi

# Apply specific configs from environment variables to the dedicated configuration file.
#
# These seds are idempotent, so run them on EVERY boot (no once-only status
# flag). The old one-shot flags meant .env edits were ignored on existing
# servers, e.g. SERVER_RCON_PASSWORD or SERVER_MAX_CLIENTS "took" only on the
# very first boot.

# Set max clients of the server
if [ ! -z "$SERVER_MAX_CLIENTS" ]; then
    echo "Setting server max clients to: '$SERVER_MAX_CLIENTS'"
    sed -i "s/\(sv_maxclients \)[0-9]*/\1$SERVER_MAX_CLIENTS/" "$CFG_PATH"
fi

# Set server RCON password
if [ ! -z "$SERVER_RCON_PASSWORD" ]; then
    echo "Setting server rcon password to: '$SERVER_RCON_PASSWORD'"
    sed -i "s/\(rcon_password \)\"[^\"]*\"/\1\"$SERVER_RCON_PASSWORD\"/" "$CFG_PATH"
fi

# Set server map rotation (replaces the active sv_maprotation line; the
# commented-out //sv_maprotation alternates are left alone)
if [ ! -z "$SERVER_MAP_ROTATION" ]; then
    echo "Setting server rotation to: '$SERVER_MAP_ROTATION'"
    sed -i "s/^sv_maprotation \"[^\"]*\"/$SERVER_MAP_ROTATION/" "$CFG_PATH"
fi

# Set server password
if [ ! -z "$SERVER_PASSWORD" ]; then
    echo "Setting server password to: '$SERVER_PASSWORD'"
    sed -i "s/\(g_password \)\"[^\"]*\"/\1\"$SERVER_PASSWORD\"/" "$CFG_PATH"
fi


################################################################################
#                             IW4Admin Provisioning                            #
################################################################################

# Define IW4Admin Logs Directory
LOGS_DIR="$PLUTONIUM_DIRECTORY/storage/t6/logs/"

echo "Checking IW4Admin files..."

# Download IW4Admin
IW4ADMIN_API="https://api.github.com/repos/RaidMax/IW4M-Admin/releases"
if [ -e $STATUS_DIRECTORY/.admin_files_downloaded ]; then
    echo "IW4Admin files already downloaded!"
else
    echo "Downloading IW4Admin files..."
    release_url=$(curl -sfL "$IW4ADMIN_API" \
        | grep -m 1 "browser_download_url" \
        | cut -d : -f 2,3 \
        | tr -d \" || true)
    if [ -z "$release_url" ]; then
        fail "failed to access $IW4ADMIN_API - GitHub may be unreachable, or the repository may have been moved or renamed"
    fi
    download_to_dir "$release_url" "$DOWNLOAD_DIRECTORY" -q --show-progress
    touch $STATUS_DIRECTORY/.admin_files_downloaded
fi

# Extract IW4Admin
if [ -e $STATUS_DIRECTORY/.admin_files_extracted ]; then
    echo "IW4Admin files already extracted!"
else
    echo "Extracting IW4Admin files..."
    extract "$DOWNLOAD_DIRECTORY/IW4MAdmin-*.zip" "$IW4ADMIN_DIRECTORY"
    touch $STATUS_DIRECTORY/.admin_files_extracted
fi

# Give execute permissions to IW4Admin
chmod +x $IW4ADMIN_DIRECTORY/StartIW4MAdmin.sh

################################################################################
#                             Server Launching                                #
################################################################################

# Remove deleted screen sessions
screen -wipe

# Launch Plutonium BO2 Server
if [ -e $PLUTONIUM_DIRECTORY/bin/plutonium-bootstrapper-win32.exe ]; then
    echo "Plutonium files exist!"
    echo "Starting server..."
    # Replace Startup Variables
    STARTUP="$PLUTONIUM_DIRECTORY/bin/plutonium-bootstrapper-win32.exe $MODE $MODE_PATH -dedicated $LAN +exec $CFG +map_rotate +set key $SERVER_KEY +set net_port $SERVER_PORT"
    echo "Running ${STARTUP}"

    # Run the Server (detached on a screen named plutonium-server)
    start_game() {
        ( cd $PLUTONIUM_DIRECTORY && pkill Xvfb || true && screen -S plutonium-server -L -Logfile /t6server/status/plutonium-server.log -dm bash -c "exec xvfb-run wine ${STARTUP}" )
    }
    start_game
else
    echo "Missing Plutonium files!! Add them manually!"
    exit 1
fi

# Launch IW4Admin
if [ -e $IW4ADMIN_DIRECTORY/StartIW4MAdmin.sh ]; then
    echo "IW4Admin files exist!"
    echo "Starting IW4Admin..."
    # Replace Startup Variables
    echo "Running $IW4ADMIN_DIRECTORY/StartIW4MAdmin.sh"

    # Run IW4Admin (detached on a screen named admin-panel)
    ( cd $IW4ADMIN_DIRECTORY && screen -S admin-panel -dm bash -c "$IW4ADMIN_DIRECTORY/StartIW4MAdmin.sh" )
else
    echo "Missing IW4Admin files!! Add them manually!"
    exit 1
fi

# Keep the container alive and watch the game server.
#
# Plutonium T6 dedicated servers are known to go unresponsive after a while or
# under repeated RCON/map-switch commands (still listed, no join, RCON silent)
# without ever exiting - so a plain "wait for the screen to die" loop is not
# enough. Watchdog: restart the game if its screen is gone OR RCON stops
# answering the `status` probe twice in a row. Same probe the community uses
# for the same problem.
# ponytail: 30s cadence, 2-strike dead check; per-port/game if this ever needs
# to supervise more than one server.
wine_probe_rcon() {
    timeout 3 bash -c \
        'exec 3<>/dev/udp/127.0.0.1/$1; \
         printf "\377\377\377\377rcon %s status\000\346\352" "$2" >&3; \
         head -c 512 <&3' _ "$SERVER_PORT" "${SERVER_RCON_PASSWORD:-admin}" 2>/dev/null \
        | grep -q .
}

game_stopped() {
    ([ -n "$(screen -ls | grep plutonium-server)" ] \
        && wine_probe_rcon) \
        && return 1
    return 0
}

watchdog_failure_count=0
game_started_at=$(date +%s)
while true; do
    sleep 30

    if game_stopped; then
        # Respect the initial boot: the game can take a few minutes to answer RCON.
        if [ $(( $(date +%s) - game_started_at )) -lt 180 ]; then
            watchdog_failure_count=0
            continue
        fi
        watchdog_failure_count=$((watchdog_failure_count + 1))
    else
        watchdog_failure_count=0
    fi

    if [ "$watchdog_failure_count" -ge 2 ]; then
        echo "$(date) game server unresponsive or crashed - restarting..."
        screen -S plutonium-server -X quit 2>/dev/null
        pkill -f plutonium-bootstrapper-win32.exe 2>/dev/null
        sleep 5
        start_game
        watchdog_failure_count=0
        game_started_at=$(date +%s)
    fi
done
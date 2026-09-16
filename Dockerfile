FROM ubuntu:jammy

LABEL author="João Carlos Palma"


################################################################################
#                             Environment Variables                            #
################################################################################
ENV PLUTONIUM_DIRECTORY="/t6server/plutonium"
ENV SERVER_DIRECTORY="/t6server/server"
ENV IW4ADMIN_DIRECTORY="/t6server/admin"
ENV UPDATER_DIRECTORY="/t6server/updater"
ENV DOWNLOAD_DIRECTORY="/t6server/downloaded_files"
ENV STATUS_DIRECTORY="/t6server/status"

ENV WINEPREFIX="/root/.wine"
ENV WINEDEBUG="fixme-all"
ENV WINEARCH="win64"

ENV SERVER_KEY="YOUR_KEY_HERE"
ENV SERVER_PORT="4976"
ENV SERVER_MODE="Zombie"
ENV LAN_MODE="false"

ENV SERVER_MAX_CLIENTS=""
ENV SERVER_RCON_PASSWORD="admin"
ENV SERVER_MAP_ROTATION=""
ENV SERVER_PASSWORD=""

ENV ADMIN_PORT="1624"

################################################################################
#                            Container Provisioning                            #
################################################################################

# Create needed directories
RUN mkdir -p $PLUTONIUM_DIRECTORY \
			 $SERVER_DIRECROTY \
			 $IW4ADMIN_DIRECTORY \
			 $UPDATER_DIRECTORY \
			 $DOWNLOAD_DIRECTORY \
			 $STATUS_DIRECTORY

# Update the system
RUN apt-get update

# Installing needed packages
RUN apt-get install -y \
	wget \
	curl \
	zip \
	screen \
	gnupg2 \
	software-properties-common \
	xvfb \
	aria2 \
	apt-transport-https \
	dotnet6 \
	dotnet-sdk-6.0 \
	aspnetcore-runtime-6.0 \
	avahi-daemon \
	avahi-utils

# Update the system
RUN apt-get upgrade -y


################################################################################
#                               Installing WINE                                #
################################################################################

COPY resources/install_wine.sh /t6server/install_wine.sh 
RUN chmod +x /t6server/install_wine.sh 
# [TODO] Run installer of the script in the server-launch.sh
RUN bash /t6server/install_wine.sh  && rm /t6server/install_wine.sh 


################################################################################
#                             Installing Updater                               #
################################################################################

COPY resources/check_updater.sh /t6server/check_updater.sh
#Make sure the script is executable by anyone
RUN chmod ugo+x /t6server/check_updater.sh


################################################################################
#                             Installing IW4MAdmin                             #
################################################################################

# Installing dotnet
RUN wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
  dpkg -i packages-microsoft-prod.deb && \
  rm packages-microsoft-prod.deb

# IW4MAdmin's current releases require the .NET 10 runtime (fresh installs
# track the latest GitHub release, which has moved on from .NET 6).
# The apt package (aspnetcore-runtime-10.0) is not published for 22.04, so
# fetch the runtime tarball via the official installer script instead.
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --runtime aspnetcore --channel 10.0 --install-dir /usr/lib/dotnet \
    && rm /tmp/dotnet-install.sh


################################################################################



# Prepare server launch
WORKDIR /t6server
COPY resources/server-launch.sh .
RUN chmod +x server-launch.sh

CMD ["./server-launch.sh"]

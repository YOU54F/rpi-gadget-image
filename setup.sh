#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "Root privileges required."
    exit 1
fi
# print welcome message
echo "This script will create a Raspberry Pi gadget image with the following settings:"

BACKUP=true
if [ $# -eq 3 ]; then
  HOSTNAME=$1
  USERNAME=$2
  PASSWORD=$3
  echo "Using supplied hostname, username and password"
elif [ $# -eq 4 ]; then
  HOSTNAME=$1
  USERNAME=$2
  PASSWORD=$3
  BACKUP=false
  echo "Using supplied hostname, username and password, no backup"
else
  read -rp "Please enter hostname: " HOSTNAME
  read -rp "Please enter username: " USERNAME
  read -rsp "Please enter password for $USERNAME user: " PASSWORD
fi

if [ ! -x "$(command -v curl)" ]; then
  echo "Could not find curl. Installing curl..."
  apt-get install -y curl
fi


# RASPIOS_OS_VERSION=$(curl -s https://downloads.raspberrypi.org/raspios_lite_arm64/os.json | sed -n 's/.*"version": "\(.*\)"$/\1/p')
# RASPIOS_OS_RELEASE_DATE=$(curl -s https://downloads.raspberrypi.org/raspios_lite_arm64/os.json | sed -n 's/.*"release_date": "\(.*\)",$/\1/p')

RASPIOS_OS_VERSION="bookworm"
RASPIOS_OS_RELEASE_DATE="2024-11-19"

if [[ -z "$RASPIOS_OS_VERSION" || -z "$RASPIOS_OS_RELEASE_DATE" ]]; then
  echo "Could not determine latest Raspios OS version."
  exit 1
fi

RASPIOS_OS_FILE="$RASPIOS_OS_RELEASE_DATE-raspios-$RASPIOS_OS_VERSION-arm64-lite.img"

if [ ! -f "$RASPIOS_OS_FILE" ]; then
  echo "Could not find latest Raspios OS image locally."
  if [ ! -f "$RASPIOS_OS_FILE.bak" ]; then
    echo "Could not find backup of latest Raspios OS image."
    echo "Downloading $RASPIOS_OS_FILE.xz from https://downloads.raspberrypi.org/."
    curl -s "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-$RASPIOS_OS_RELEASE_DATE/$RASPIOS_OS_FILE.xz" -o "$RASPIOS_OS_FILE.xz"
    echo "Unpacking $RASPIOS_OS_FILE.xz"
    xz -d "$RASPIOS_OS_FILE.xz"

    if  $BACKUP; then
      cp "$RASPIOS_OS_FILE" "$RASPIOS_OS_FILE.bak"
    fi
  else
    echo "Using backup of Raspios OS image."
    cp "$RASPIOS_OS_FILE.bak" "$RASPIOS_OS_FILE"
  fi
fi

if [ ! -x "$(command -v qemu-img)" ]; then
  echo "Could not find qemu-img. Installing qemu-utils..."
  apt-get install -y qemu-utils
fi

if [ ! -x "$(command -v parted)" ]; then
  echo "Could not find parted. Installing parted..."
  apt-get install -y parted
fi

CURRENT_SIZE=$(qemu-img info "$RASPIOS_OS_FILE" | grep 'virtual size' | awk '{print $3}')
IMG_SIZE_POW_2=$(echo "x=l($CURRENT_SIZE)/l(2); scale=0; 2^((x+1)/1)" | bc -l;)

echo "Resizing $RASPIOS_OS_FILE to $IMG_SIZE_POW_2 GB."
qemu-img resize "$RASPIOS_OS_FILE" "${IMG_SIZE_POW_2}G"

echo "Resizing root partition to fill new space."
parted -s "$RASPIOS_OS_FILE" resizepart 2 100%

echo "Mounting $RASPIOS_OS_FILE"
OFFSET=$(fdisk -l "$RASPIOS_OS_FILE" | awk '/^[^ ]*1/{ print $2*512; exit }')
mkdir boot
echo "Mounting $RASPIOS_OS_FILE at offset $OFFSET"
sudo mount -o loop,offset="$OFFSET" "$RASPIOS_OS_FILE" boot

PASS=$(echo "$PASSWORD" |  openssl passwd -6 -stdin)
echo "$USERNAME:$PASS" > userconf.txt

sudo cp userconf.txt boot/userconf.txt
sudo sync

sudo umount boot
rmdir boot

export HOSTNAME
export USERNAME
export PASSWORD


if [ ! -x "$(command -v expect)" ]; then
  echo "Installing expect"
  apt-get install -y expect
fi

./create-image "$RASPIOS_OS_FILE"
./pishrink -aZ "$RASPIOS_OS_FILE"
mv "$RASPIOS_OS_FILE.xz" "raspios.img.xz"

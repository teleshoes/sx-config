SD_FAT_UUID=`blkid -l -s UUID -o value -t LABEL=SD_FAT`
SD_DATA_UUID=`blkid -l -s UUID -o value -t LABEL=SD_DATA`
SD_DEB_UUID=`blkid -l -s UUID -o value -t LABEL=SD_DEB`

ANDROID_MNT_DIR="/mnt/media_rw"
DEBIAN_MNT_DIR="$ANDROID_MNT_DIR/$SD_DEB_UUID/mnt"

set -x

#binds
mkdir -p "$DEBIAN_MNT_DIR/android-data"
mount --bind "/data" "$DEBIAN_MNT_DIR/android-data";

mkdir -p "$DEBIAN_MNT_DIR/android-sdcard"
mount --bind "/sdcard" "$DEBIAN_MNT_DIR/android-sdcard";

for UUID in $SD_FAT_UUID $SD_DATA_UUID $SD_DEB_UUID; do
  mkdir -p "$DEBIAN_MNT_DIR/$UUID"
  mount --bind "$ANDROID_MNT_DIR/$UUID" "$DEBIAN_MNT_DIR/$UUID";
done

#symlinks
for DIR in /storage /mnt/media_rw $DEBIAN_MNT_DIR; do
  rm -f $DIR/sd-*
  ln -s $SD_FAT_UUID $DIR/sd-fat
  ln -s $SD_DATA_UUID $DIR/sd-data
  ln -s $SD_DEB_UUID $DIR/sd-deb
done

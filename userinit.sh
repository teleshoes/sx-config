ANDROID_MNT_DIR="/mnt/media_rw"
DEBIAN_MNT_DIR="$ANDROID_MNT_DIR/a253ae8b-ee66-4e4b-a737-faa1d54f8337/mnt"

mkdir "$DEBIAN_MNT_DIR/android-data"
mount --bind "/data" "$DEBIAN_MNT_DIR/android-data";

mkdir "$DEBIAN_MNT_DIR/android-sdcard"
mount --bind "/sdcard" "$DEBIAN_MNT_DIR/android-sdcard";

for x in `ls $ANDROID_MNT_DIR`; do
  mkdir "$DEBIAN_MNT_DIR/$x"
  mount --bind "$ANDROID_MNT_DIR/$x" "$DEBIAN_MNT_DIR/$x";
done

#symlinks
for x in `cd $DEBIAN_MNT_DIR && ls sd*`; do
  rm /storage/$x
  ln -s `readlink $DEBIAN_MNT_DIR/$x` /storage/$x
done

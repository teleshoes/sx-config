DIR=/data/user/0/x1125io.initdlight
LOGOUT=$DIR/out
LOGERR=$DIR/err

rm -f $LOGOUT $LOGERR

sh /sdcard/userinit/userinit-adb-over-network.sh >>$LOGOUT 2>>$LOGERR
sh /sdcard/userinit/userinit-linuxdeploy.sh >>$LOGOUT 2>>$LOGERR
sh /sdcard/userinit/userinit-mount.sh >>$LOGOUT 2>>$LOGERR

# If this user has same uid as a running systemd user session
# then this script will copy enviroment variables from it

CURRENT_UID="$(id -u)"
if [ $CURRENT_UID -ne 0 ]; then
# There are some values that we don't want to change or copy
# Then there are values that we want to copy
# Each value should be either in white or in black list
# We notify console if we come up with new value that is not
# in either of the lists

# (These must have newline as separator)
    BLACKLIST_VALUES=$(sed -e 's/^/-e ^/' -e 's/$/=/' <<-EOF
	AG_PROVIDERS
	AG_SERVICES
	AG_SERVICE_TYPES
	board_id
	BOOT_IMAGE
	bootmode
	bootreason
	BOOTSTATE
	bootup_reason
	crashkernel
	dbi-size
	dbi-type
	dbi-uid
	dbi-vendor
	do_fsck
	emmc_wp_size
	G_BROKEN_FILENAMES
	HOME
	hwid
	imei
	LANG
	LC_COLLATE
	LOGNAME
	mem_issw
	NGF_FFMEMLESS_SETTINGS
	nolo
	NOTIFY_SOCKET
	OLDPWD
	INVOCATION_ID
	JOURNAL_STREAM
	PATH
	product_model
	product_name
	PWD
	pwr_on_status
	QT_WAYLAND_COMPOSITOR_NO_THROTTLE
	QTCONTACTS_MANAGER_OVERRIDE
	Qunlock
	serialnumber
	SESSION_TARGET
	SHELL
	SHLVL
	TERM
	USER
	vga
	vhash
	wifibin
	wlanmac
	XDG_SEAT
	XDG_SESSION_ID
	XDG_VTNR
	EOF
)

    WHITELIST_VALUES=$(sed -e 's/^/-e ^/' -e 's/$/=/' <<-EOF
	LIPSTICK2VNC_OPTS
	BROWSER
	DBUS_SESSION_BUS_ADDRESS
	DISPLAY
	EGL_DRIVER
	EGL_PLATFORM
	FF_MEMLESS_SETTINGS
	GSETTINGS_BACKEND
	HYBRIS_LD_LIBRARY_PATH
	M_DECORATED
	MOZ_GMP_PATH
	OPTIONS
	QMLSCENE_DEVICE
	QML_FIXED_ANIMATION_STEP
	QSG_FIXED_ANIMATION_STEP
	QT_DEFAULT_RUNTIME_SYSTEM
	QT_GRAPHICSSYSTEM
	QT_IM_MODULE
	QT_QPA_PLATFORM
	QT_USE_DRAG_DISTANCE
	QT_WAYLAND_DISABLE_WINDOWDECORATION
	QT_GSTREAMER_CAMERABIN_SRC
	QT_GSTREAMER_CAMERABIN_FLAGS
	QT_GSTREAMER_PLAYBIN_FLAGS
	QT_MESSAGE_PATTERN
	QT_DF_BASE
	QT_DF_BASEDEVIATION
	QT_DF_SCALEFORMAXDEV
	QT_DF_SCALEFORNODEV
	QT_DF_RANGE
	QT_OPENGL_NO_BGRA
	QT_WAYLAND_RESIZE_AFTER_SWAP
	QT_WAYLAND_FORCE_DPI
	WAYLAND_DISPLAY
	XDG_RUNTIME_DIR
	EOF
)

    SESSION_PID=""
    for PID in $(/sbin/pidof systemd)
    do
        if [ $CURRENT_UID -eq $(ls -ldn /proc/$PID | tr -s ' ' | cut -d' ' -f3) ]
        then
            SESSION_PID=$PID
            break
        fi
    done

    if [ -n "$SESSION_PID" ]; then
        # Pick up env variables that
        # a) are not blacklisted
        # b) are whitelisted
        # FIXME: The FOO='BAR BAR' escaping could be more robust...
        eval "$(tr '\0' '\n' < /proc/$SESSION_PID/environ |
        grep -v $BLACKLIST_VALUES |
        grep $WHITELIST_VALUES |
        sed -e 's/^/export /' -e 's/=/='\''/' -e 's/$/'\''/')"
        # Report env variables that
        # a) are not blacklisted
        # b) are not whitelisted
        tr '\0' '\n' < /proc/$SESSION_PID/environ |
        grep -v $BLACKLIST_VALUES |
        grep -v $WHITELIST_VALUES |
        sed -e 's/^/NOTICE: Env value ignored: /'

    else
        # No session running for this user
        echo "NOTICE: There is no systemd user session running"
    fi
fi

# Unset local variables to not pollute the environment
unset SESSION_PID CURRENT_UID BLACKLIST_VALUES WHITELIST_VALUES

#!/usr/bin/python
#vibrate.py
#Copyright 2018 Elliot Wolk
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

from PyQt5.QtCore import *
from PyQt5.QtQuick import *
from PyQt5.QtWidgets import *

import os
import re
import sys
import tempfile

DEFAULT_DURATION_MILLIS = 200

usage = """Usage:
  %(exec)s [DURATION_MILLIS]
""" % {"exec": sys.argv[0]}

def main():
  if len(sys.argv) == 1:
    durationMillis = DEFAULT_DURATION_MILLIS
  elif len(sys.argv) == 2 and re.match("^\d+$", sys.argv[1]):
    durationMillis = int(sys.argv[1])
  else:
    print >> sys.stderr, usage
    sys.exit(2)

  os.environ['QT_QPA_PLATFORM']='wayland'
  os.environ['XDG_RUNTIME_DIR']='/run/user/100000'
  os.environ['WAYLAND_DISPLAY']='../../display/wayland-0'

  app = QApplication([])

  qml = """
      import QtQuick 2.3
      import QtFeedback 5.0

      Rectangle {
        HapticsEffect {
          duration: %(durationMillis)d
          running: true
        }
      }
  """ % {"durationMillis": durationMillis}

  fd, qmlFile = tempfile.mkstemp(prefix="vib_", suffix=".qml")
  fh = open(qmlFile, 'w')
  fh.write(qml)
  fh.close()

  mainWindow = QQuickView()
  mainWindow.setSource(QUrl(qmlFile))
  QTimer.singleShot(durationMillis, lambda: [
    os.remove(qmlFile),
    QCoreApplication.instance().quit()
  ])

  app.exec_()

if __name__ == "__main__":
  sys.exit(main())

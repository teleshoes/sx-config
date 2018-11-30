/*
  Copyright (C) 2013 Jolla Ltd.
  Contact: Thomas Perl <thomas.perl@jollamobile.com>
  All rights reserved.

  You may use this file under the terms of BSD license as follows:

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Jolla Ltd nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow
{
    property variant currentDirectoryView: null

    property var dirPage: Qt.createComponent(Qt.resolvedUrl("pages/DirectoryPage.qml")).createObject(this)
    property var shortcutsPage: Qt.createComponent(Qt.resolvedUrl("pages/dirView/ShortcutsView.qml")).createObject(this)

    property var getDirectoryPage: function() {
      return dirPage
    }
    property var getShortcutsPage: function() {
      return shortcutsPage
    }

    property var openDir: function(dir) {
      pageStack.push(dirPage, null, PageStackAction.Immediate)
      if(dirPage.currentView != null){
        dirPage.currentView.destroy()
      }
      dirPage.openDirectory(dir)
    }

    // Get the current directory view (eg. a list/grid of files)
    property var getDirectoryView: function() {
        return dirPage.currentView
    }

    // Get the current file page
    property var getFilePage: function() {
        return pageStack.find(function(page) { if ('isFilePage' in page) { return true; } else return false; })
    }

    // Get the file operation page
    property var getFileOperationPage: function() {
        return pageStack.find(function(page) { if ('isFileOperationPage' in page) { return true; } else return false; })
    }

    // Get the current file view (eg. audio/video/image/text view)
    property var getFileView: function() {
        var page = getFilePage()

        return page.currentView
    }

    property bool selectingItems: false

    id: mainWindow
    allowedOrientations: Orientation.All
    initialPage: shortcutsPage
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
}



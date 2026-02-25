/*
    Copyright (C) 2025 edp17 and chatGPT

    This file is part of harbour-fivinarow.

    The harbour-fivinarow is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    The harbour-fivinarow is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with the harbour-fivinarow. If not, see <http://www.gnu.org/licenses/>.
*/
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: aboutPage
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height

        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("About")
            }

            // App Title
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Five in a Row")
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
                color: "gold"
            }

            // Logo image
            Image {
                id: coverLogo
                source: "/usr/share/icons/hicolor/172x172/apps/harbour-fivinarow.png"
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.20
                height: width
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            // Version — optional manual entry
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Version 1.1")
                font.pixelSize: Theme.fontSizeMedium
                color: "white"
            }

            // Description
            Label {
                text: qsTr("A Sailfish OS implementation of the classic Five-in-a-Row game with AI and multiplayer options.")
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                width: parent.width - Theme.paddingLarge * 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: "white"
            }

            // Author
            Label {
                text: qsTr("Developed by: edp17")
                font.pixelSize: Theme.fontSizeSmall
                width: parent.width - Theme.paddingLarge * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                color: "#cccccc"
            }

            // Copyright / info
            Label {
                text: qsTr("This project is licensed under GNU GPL 3.0. Copyright (c) 2025 edp17.\nIcons and graphics created by edp17.")
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                width: parent.width - Theme.paddingLarge * 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#bbbbbb"
                horizontalAlignment: Text.AlignHCenter
            }

            Item { height: Theme.paddingLarge }
        }
    }
}
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

CoverBackground {
    id: cover

    property var boardMatrix: ([])
    property int boardSize: 15
    property var winningCells: []
    property bool gameOver: false
    property bool gameDraw: false
    property string winnerText: ""

    /* ---------------------------
       Background (OLD STYLE)
       --------------------------- */
    Rectangle {
        anchors.fill: parent
        color: "#202020"
        z: 0
    }

    /* ---------------------------
       App title (TOP) (OLD STYLE)
       --------------------------- */
    Label {
        id: titleLabel
        text: qsTr("Five in a Row")
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.paddingLarge

        font.pixelSize: Theme.fontSizeSmall
        font.bold: false
        color: "white"
        z: 10
    }

    /* ---------------------------
       Board area (CENTER) (OLD STYLE)
       --------------------------- */
    Item {
        id: boardArea
        width: parent.width * 0.85
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        z: 1

        Grid {
            id: boardGrid
            anchors.fill: parent
            rows: boardSize
            columns: boardSize
            spacing: 1

            Repeater {
                model: boardSize * boardSize

                Rectangle {
                    width: boardGrid.width / boardSize
                    height: width

                    property int r: Math.floor(index / boardSize)
                    property int c: index % boardSize

                    // Normalize null/undefined -> "" to avoid "Unable to assign null to QString"
                    property var raw: (boardMatrix && boardMatrix[r]) ? boardMatrix[r][c] : ""
                    property string cell: (raw === null || raw === undefined) ? "" : ("" + raw)

                    color: {
                        // highlight winning line
                        for (var i = 0; i < winningCells.length; i++) {
                            if (winningCells[i].r === r && winningCells[i].c === c)
                                return "gold"
                        }

                        if (cell === "X") return "#aaddff"
                        if (cell === "O") return "#ffccdd"
                        return "white"
                    }

                    border.color: "#000000"
                    border.width: 0.1

                    Text {
                        anchors.centerIn: parent
                        text: cell
                        font.pixelSize: parent.width
                        font.bold: true
                        color: cell === "X" ? "darkblue"
                             : cell === "O" ? "red"
                             : "transparent"
                    }
                }
            }
        }
    }

    /* ---------------------------
       Game Over overlay (OLD STYLE)
       --------------------------- */
    Rectangle {
        id: gameOverOverlay
        anchors.fill: boardArea
        color: "white"
        opacity: 0.60
        visible: gameOver
        z: 20

        Column {
            anchors.centerIn: parent
            spacing: Theme.paddingSmall

            Label {
                text: qsTr("Game Over")
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
                color: "red"
            }

            Label {
                text: gameDraw ? qsTr("Draw") : qsTr("Winner: %1").arg(winnerText)
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: "black"
            }
        }
    }
}

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
    id: settingsPage
    property var settings

    allowedOrientations: Orientation.All

    Connections {
        target: settings
        onGameModeChanged: {
            if (settings.gameMode === "Player vs AI") {
                deferExpandDifficulty.restart()
            } else {
                settings.difficultyExpanded = false
            }
        }
    }

    Timer {
        id: deferExpandDifficulty
        interval: 0
        repeat: false
        onTriggered: settings.difficultyExpanded = true
    }

    // -------------------------------
    // REUSABLE EXPAND/COLLAPSE HEADER
    // -------------------------------
    Component {
        id: expandingHeader

        BackgroundItem {
            id: header
            property bool externalExpanded: false
            property alias text: headerLabel.text
            property bool expanded: false
            signal toggled(bool state)

            width: parent.width
            height: Theme.itemSizeSmall

            onClicked: {
                if (!enabled) return
                var next = !expanded
                if (!externalExpanded) {
                    // normal sections (local control)
                    expanded = next
                }
                toggled(next)
            }

            Label {
                id: headerLabel
                anchors.left: parent.left
                anchors.leftMargin: Theme.paddingLarge
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }

            Image {
                id: arrow
                source: "image://theme/icon-m-left"
                anchors.right: parent.right
                anchors.rightMargin: Theme.paddingLarge
                anchors.verticalCenter: parent.verticalCenter
                rotation: expanded ? -90 : 0

                Behavior on rotation {
                    NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                }
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: qsTr("Settings") }

            // -------------------------------
            // 1. GAME MODE
            // -------------------------------

            Loader {
                id: gameModeHeaderLoader
                width: parent.width
                sourceComponent: expandingHeader
                onLoaded: {
                    item.text = qsTr("Game Mode")
                    item.expanded = settings.gameModeExpanded
                    item.toggled.connect(function(state) {
                        settings.gameModeExpanded = state
                    })
                }
            }

            Item {
                id: gameModeContainer
                width: parent.width
                clip: true

                property int targetHeight:
                    settings.gameModeExpanded ? gameModeContent.implicitHeight : 0

                height: targetHeight

                Behavior on height {
                    NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                }

                Column {
                    id: gameModeContent
                    width: parent.width
                    spacing: Theme.paddingSmall

                    // Player1 vs Player2
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Player1 vs Player2")
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: gmPVP
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            checked: settings.gameMode === "Player1 vs Player2"
                            onClicked: {
                                settings.gameMode = "Player1 vs Player2"
                                gmPvAI.checked = false
                            }
                        }
                    }

                    // Player vs AI
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Player vs AI")
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: gmPvAI
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            checked: settings.gameMode === "Player vs AI"
                            onClicked: {
                                settings.gameMode = "Player vs AI"
                                gmPVP.checked = false
                            }
                        }
                    }
                }
            }


            // -------------------------------
            // 2. AI DIFFICULTY
            // -------------------------------

            Loader {
                id: difficultyHeaderLoader
                width: parent.width
                sourceComponent: expandingHeader

                onLoaded: {
                    item.text = qsTr("AI Difficulty")

                    item.externalExpanded = true
                    item.expanded = Qt.binding(function() { return settings.difficultyExpanded })

                    item.enabled = Qt.binding(function() { return settings.gameMode === "Player vs AI" })
                    item.opacity = Qt.binding(function() { return item.enabled ? 1.0 : 0.4 })

                    item.toggled.connect(function(state) {
                        if (item.enabled) settings.difficultyExpanded = state
                    })
                }
            }

            Item {
                id: difficultyContainer
                width: parent.width
                clip: true

                property int targetHeight:
                    (settings.difficultyExpanded && settings.gameMode === "Player vs AI")
                    ? difficultyContent.implicitHeight : 0

                height: targetHeight

                Behavior on height { NumberAnimation { duration: 200 } }

                Column {
                    id: difficultyContent
                    width: parent.width
                    spacing: Theme.paddingSmall

                    // Easy
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall
                        Label {
                            text: qsTr("Easy")
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        Switch {
                            id: diffEasy
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Theme.paddingMedium
                            checked: settings.aiDifficulty === "Easy"
                            onClicked: {
                                settings.aiDifficulty = "Easy"
                                diffMed.checked = false
                                diffHard.checked = false
                                diffUnbeatable.checked = false
                            }
                        }
                    }

                    // Medium
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Medium")
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: diffMed
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            checked: settings.aiDifficulty === "Medium"
                            onClicked: {
                                settings.aiDifficulty = "Medium"
                                diffEasy.checked = false
                                diffHard.checked = false
                                diffUnbeatable.checked = false
                            }
                        }
                    }

                    // Hard
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Hard")
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: diffHard
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Theme.paddingMedium
                            checked: settings.aiDifficulty === "Hard"
                            onClicked: {
                                settings.aiDifficulty = "Hard"
                                diffEasy.checked = false
                                diffMed.checked = false
                                diffUnbeatable.checked = false
                            }
                        }
                    }

                    // Unbeatable
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Unbeatable")
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: diffUnbeatable
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: Theme.paddingMedium
                            checked: settings.aiDifficulty === "Unbeatable"
                            onClicked: {
                                settings.aiDifficulty = "Unbeatable"
                                diffEasy.checked = false
                                diffMed.checked = false
                                diffHard.checked = false
                            }
                        }
                    }
                }
            }


            // -------------------------------
            // 3. PLAYER SYMBOL
            // -------------------------------

            Loader {
                id: symbolHeaderLoader
                width: parent.width
                sourceComponent: expandingHeader
                onLoaded: {
                    item.text = qsTr("Player Symbol")
                    item.expanded = settings.symbolExpanded
                    item.toggled.connect(function(state) {
                        settings.symbolExpanded = state
                    })
                }
            }

            Item {
                id: symbolContainer
                width: parent.width
                clip: true

                property int targetHeight:
                    settings.symbolExpanded ? symbolContent.implicitHeight : 0

                height: targetHeight

                Behavior on height { NumberAnimation { duration: 200 } }

                Column {
                    id: symbolContent
                    width: parent.width
                    spacing: Theme.paddingSmall

                    // Play as X
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Play as X")
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: symX
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            checked: settings.playerSymbol === "X"

                            onClicked: {
                                settings.playerSymbol = "X"
                                settings.aiSymbol = "O"
                                symO.checked = false
                            }
                        }
                    }

                    // Play as O
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Play as O")
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: symO
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            checked: settings.playerSymbol === "O"

                            onClicked: {
                                settings.playerSymbol = "O"
                                settings.aiSymbol = "X"
                                symX.checked = false
                            }
                        }
                    }
                }
            }


            // -------------------------------
            // 4. WHO STARTS
            // -------------------------------

            Loader {
                id: startHeaderLoader
                width: parent.width
                sourceComponent: expandingHeader
                onLoaded: {
                    item.text = qsTr("Who Starts")
                    item.expanded = settings.startExpanded
                    item.toggled.connect(function(state) {
                        settings.startExpanded = state
                    })
                }
            }

            Item {
                id: startContainer
                width: parent.width
                clip: true

                property int targetHeight:
                    settings.startExpanded ? startContent.implicitHeight : 0

                height: targetHeight

                Behavior on height { NumberAnimation { duration: 200 } }

                Column {
                    id: startContent
                    width: parent.width
                    spacing: Theme.paddingSmall

                    // Player starts
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("Player starts")
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: stPlayer
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            checked: settings.startingPlayer === settings.playerSymbol

                            onClicked: {
                                settings.startingPlayer = settings.playerSymbol
                                stAI.checked = false
                            }
                        }
                    }

                    // AI starts
                    Item {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Label {
                            text: qsTr("AI starts")
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Switch {
                            id: stAI
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            checked: settings.startingPlayer === settings.aiSymbol

                            onClicked: {
                                settings.startingPlayer = settings.aiSymbol
                                stPlayer.checked = false
                            }
                        }
                    }
                }
            }


            // -------------------------------
            // 5. PLAYER NAMES
            // -------------------------------

            Loader {
                id: namesHeaderLoader
                width: parent.width
                sourceComponent: expandingHeader
                onLoaded: {
                    item.text = qsTr("Player Names")
                    item.expanded = settings.namesExpanded
                    item.toggled.connect(function(state) {
                        settings.namesExpanded = state
                    })
                }
            }

            Item {
                id: namesContainer
                width: parent.width
                clip: true

                property int targetHeight:
                    settings.namesExpanded ? namesContent.implicitHeight : 0

                height: targetHeight

                Behavior on height { NumberAnimation { duration: 200 } }

                Column {
                    id: namesContent
                    width: parent.width
                    spacing: Theme.paddingSmall

                    TextField {
                        width: parent.width - 2 * Theme.paddingLarge
                        anchors.horizontalCenter: parent.horizontalCenter
                        label: qsTr("Player 1 name")
                        text: settings.player1Name
                        onTextChanged: settings.player1Name = text
                    }

                    TextField {
                        width: parent.width - 2 * Theme.paddingLarge
                        anchors.horizontalCenter: parent.horizontalCenter
                        label: qsTr("Player 2 name")
                        text: settings.player2Name
                        onTextChanged: settings.player2Name = text
                    }
                }
            }


            // -------------------------------
            // RESET BUTTON
            // -------------------------------

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Reset to defaults")

                onClicked: {
                    settings.gameMode = "Player vs AI"
                    settings.aiDifficulty = "Medium"
                    settings.playerSymbol = "X"
                    settings.aiSymbol = "O"
                    settings.startingPlayer = "X"
                    settings.player1Name = "Player 1"
                    settings.player2Name = "Player 2"

                    settings.gameModeExpanded = true
                    settings.difficultyExpanded = true
                    settings.symbolExpanded = false
                    settings.startExpanded = false
                    settings.namesExpanded = false
                }
            }

        }
    }
}

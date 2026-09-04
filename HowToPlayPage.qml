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
    id: page
    allowedOrientations: Orientation.All

    Component {
        id: boardDiagram
        Item {
            id: diagram
            property int gridSize: 7
            property var stones: []
            property var marked: []
            width: page.width * 0.76
            height: width

            function stoneAt(row, column) {
                for (var i = 0; i < stones.length; i++)
                    if (stones[i].r === row && stones[i].c === column)
                        return stones[i].s
                return ""
            }
            function isMarked(row, column) {
                for (var i = 0; i < marked.length; i++)
                    if (marked[i].r === row && marked[i].c === column) return true
                return false
            }

            Grid {
                anchors.fill: parent
                rows: diagram.gridSize
                columns: diagram.gridSize
                Repeater {
                    model: diagram.gridSize * diagram.gridSize
                    Rectangle {
                        width: diagram.width / diagram.gridSize
                        height: width
                        property int row: Math.floor(index / diagram.gridSize)
                        property int column: index % diagram.gridSize
                        property string symbol: diagram.stoneAt(row, column)
                        color: diagram.isMarked(row, column) ? "gold" : "white"
                        border.color: "black"
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: parent.symbol
                            font.bold: true
                            font.pixelSize: parent.width * 0.72
                            color: text === "X" ? "darkblue" : "red"
                        }
                    }
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
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("How to Play") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                text: qsTr("Take turns placing X and O on empty cells. Complete an unbroken line horizontally, vertically, or diagonally before your opponent.")
            }

            SectionHeader { text: qsTr("Make a row") }
            Loader {
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: boardDiagram
                onLoaded: {
                    item.stones = [
                        {r:3,c:1,s:"X"}, {r:3,c:2,s:"X"}, {r:3,c:3,s:"X"},
                        {r:3,c:4,s:"X"}, {r:3,c:5,s:"X"}
                    ]
                    item.marked = [{r:3,c:1},{r:3,c:2},{r:3,c:3},{r:3,c:4},{r:3,c:5}]
                }
            }

            SectionHeader { text: qsTr("Block threats") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                text: qsTr("If your opponent has four in a row, occupy the open end immediately.")
            }
            Loader {
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: boardDiagram
                onLoaded: {
                    item.stones = [
                        {r:3,c:1,s:"O"}, {r:3,c:2,s:"X"}, {r:3,c:3,s:"X"},
                        {r:3,c:4,s:"X"}, {r:3,c:5,s:"X"}, {r:3,c:6,s:"O"}
                    ]
                    item.marked = [{r:3,c:6}]
                }
            }

            SectionHeader { text: qsTr("Create a fork") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                text: qsTr("A fork creates two threats at once. Your opponent can block only one of them.")
            }
            Loader {
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: boardDiagram
                onLoaded: {
                    item.stones = [
                        {r:3,c:2,s:"X"}, {r:3,c:3,s:"X"}, {r:3,c:4,s:"X"},
                        {r:2,c:3,s:"X"}, {r:4,c:3,s:"X"}
                    ]
                    item.marked = [{r:3,c:3}]
                }
            }

            SectionHeader { text: qsTr("Rule variants") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                text: qsTr("Five or more accepts longer lines. Exactly five requires a line of precisely five symbols; six or more is not a win.")
            }
            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}

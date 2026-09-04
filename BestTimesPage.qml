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

    RemorsePopup { id: remorse }

    // Pass SettingsStore in when pushing the page:
    // pageStack.push("BestTimesPage.qml", { settings: settings })
    property var settings

    function parseList(jsonStr) {
        try {
            var a = JSON.parse(jsonStr || "[]")
            return Array.isArray(a) ? a : []
        } catch (e) {
            return []
        }
    }

    function msOf(e) {
        return (e && e.ms !== undefined) ? Number(e.ms) : 0
    }

    function whoOf(e) {
        return (e && e.name && e.name.length > 0) ? e.name : qsTr("Player")
    }

    function fmtMs(ms) {
        ms = (ms || 0)
        var totalSec = Math.floor(ms / 1000)
        var min = Math.floor(totalSec / 60)
        var sec = totalSec % 60
        var mm = (min < 10 ? "0" : "") + min
        var ss = (sec < 10 ? "0" : "") + sec
        return mm + ":" + ss
    }

    function forCurrentBoard(entries) {
        if (!settings) return []
        return entries.filter(function(entry) {
            var size = entry.boardSize || 15
            var rule = entry.winRule || "Freestyle"
            return size === settings.boardSize && rule === settings.winRule
        })
    }

    function timesEasy() {
        var out = settings ? forCurrentBoard(parseList(settings.bestTimesEasyJson)) : []
        out.sort(function(a, b) { return msOf(a) - msOf(b) })
        if (out.length > 6) out = out.slice(0, 6)
        return out
    }

    function timesMedium() {
        var out = settings ? forCurrentBoard(parseList(settings.bestTimesMediumJson)) : []
        out.sort(function(a, b) { return msOf(a) - msOf(b) })
        if (out.length > 6) out = out.slice(0, 6)
        return out
    }

    function timesHard() {
        var out = settings ? forCurrentBoard(parseList(settings.bestTimesHardJson)) : []
        out.sort(function(a, b) { return msOf(a) - msOf(b) })
        if (out.length > 6) out = out.slice(0, 6)
        return out
    }

    function timesExpert() {
        var out = settings ? forCurrentBoard(parseList(settings.bestTimesUnbeatableJson)) : []
        out.sort(function(a, b) { return msOf(a) - msOf(b) })
        if (out.length > 6) out = out.slice(0, 6)
        return out
    }

    readonly property var easyList: timesEasy()
    readonly property var mediumList: timesMedium()
    readonly property var hardList: timesHard()
    readonly property var expertList: timesExpert()
    readonly property bool hasAny: (easyList.length + mediumList.length + hardList.length + expertList.length) > 0

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            visible: settings !== null &&
                     (parseList(settings.bestTimesEasyJson).length > 0 ||
                      parseList(settings.bestTimesMediumJson).length > 0 ||
                      parseList(settings.bestTimesHardJson).length > 0 ||
                      parseList(settings.bestTimesUnbeatableJson).length > 0)

            MenuItem {
                text: qsTr("Clear best times")
                onClicked: {
                    remorse.execute(qsTr("Clearing best times"), function() {
                        settings.bestTimesEasyJson = "[]"
                        settings.bestTimesMediumJson = "[]"
                        settings.bestTimesHardJson = "[]"
                        settings.bestTimesUnbeatableJson = "[]"
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: qsTr("Best times") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                color: Theme.highlightColor
                text: qsTr("%1 × %1 · %2").arg(settings ? settings.boardSize : 15)
                      .arg(settings && settings.winRule === "ExactFive"
                           ? qsTr("Exactly five") : qsTr("Five or more"))
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                visible: !hasAny
                text: qsTr("Win a game against the AI to record a time.")
            }

            // Header row helper: SectionHeader line + right-aligned "subtitle"
            // (keeps navalbattle look but shows difficulty on the right)
            function headerRow(titleRight) {
                return null
            }

            // EASY
            Column {
                width: parent.width
                visible: easyList.length > 0
                spacing: Theme.paddingSmall

                Item {
                    width: parent.width
                    height: Theme.itemSizeSmall

                    SectionHeader {
                        anchors.fill: parent
                        text: qsTr("Easy")
                    }
                }

                Repeater {
                    model: easyList
                    delegate: Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        text: "#" + (index + 1) + ". " + whoOf(modelData) + "  " + fmtMs(msOf(modelData))
                    }
                }

                Item { width: 1; height: Theme.paddingMedium }
            }

            // MEDIUM
            Column {
                width: parent.width
                visible: mediumList.length > 0
                spacing: Theme.paddingSmall

                Item {
                    width: parent.width
                    height: Theme.itemSizeSmall

                    SectionHeader {
                        anchors.fill: parent
                        text: qsTr("Medium")
                    }
                }

                Repeater {
                    model: mediumList
                    delegate: Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        text: "#" + (index + 1) + ". " + whoOf(modelData) + "  " + fmtMs(msOf(modelData))
                    }
                }

                Item { width: 1; height: Theme.paddingMedium }
            }

            // HARD
            Column {
                width: parent.width
                visible: hardList.length > 0
                spacing: Theme.paddingSmall

                Item {
                    width: parent.width
                    height: Theme.itemSizeSmall

                    SectionHeader {
                        anchors.fill: parent
                        text: qsTr("Hard")
                    }
                }

                Repeater {
                    model: hardList
                    delegate: Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        text: "#" + (index + 1) + ". " + whoOf(modelData) + "  " + fmtMs(msOf(modelData))
                    }
                }

                Item { width: 1; height: Theme.paddingMedium }
            }

            // EXPERT
            Column {
                width: parent.width
                visible: expertList.length > 0
                spacing: Theme.paddingSmall

                Item {
                    width: parent.width
                    height: Theme.itemSizeSmall

                    SectionHeader {
                        anchors.fill: parent
                        text: qsTr("Expert")
                    }
                }

                Repeater {
                    model: expertList
                    delegate: Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        text: "#" + (index + 1) + ". " + whoOf(modelData) + "  " + fmtMs(msOf(modelData))
                    }
                }

                Item { width: 1; height: Theme.paddingMedium }
            }
        }
    }
}

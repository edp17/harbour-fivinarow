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
    property var settings
    allowedOrientations: Orientation.All

    RemorsePopup { id: remorse }

    function statistics() {
        var value
        try { value = JSON.parse(settings ? settings.statisticsJson : "{}") }
        catch (e) { value = ({}) }
        if (!value || typeof value !== "object") value = ({})
        value.byDifficulty = value.byDifficulty || ({})
        return value
    }

    function number(value) { return Number(value) || 0 }

    function bucket(name) {
        var item = statistics().byDifficulty[name] || ({})
        return qsTr("%1 won · %2 lost · %3 drawn")
                .arg(number(item.wins)).arg(number(item.losses)).arg(number(item.draws))
    }

    function difficultyLabel(name) {
        if (name === "Easy") return qsTr("Easy")
        if (name === "Medium") return qsTr("Medium")
        if (name === "Hard") return qsTr("Hard")
        return qsTr("Expert")
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Clear statistics")
                onClicked: remorse.execute(qsTr("Clearing statistics"), function() {
                    settings.statisticsJson = "{}"
                })
            }
        }

        Column {
            id: content
            width: parent.width

            PageHeader { title: qsTr("Statistics") }
            SectionHeader { text: qsTr("Overall") }

            DetailItem { label: qsTr("Games"); value: number(statistics().games) }
            DetailItem { label: qsTr("Wins"); value: number(statistics().wins) }
            DetailItem { label: qsTr("Losses"); value: number(statistics().losses) }
            DetailItem { label: qsTr("Draws"); value: number(statistics().draws) }
            DetailItem { label: qsTr("Current win streak"); value: number(statistics().currentStreak) }
            DetailItem { label: qsTr("Longest win streak"); value: number(statistics().bestStreak) }

            SectionHeader { text: qsTr("By difficulty") }

            Repeater {
                model: ["Easy", "Medium", "Hard", "Expert"]
                delegate: Column {
                    width: parent.width
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        color: Theme.highlightColor
                        text: difficultyLabel(modelData)
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        color: Theme.secondaryColor
                        text: bucket(modelData)
                    }
                    Item { width: 1; height: Theme.paddingMedium }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                text: qsTr("Statistics are recorded for games against the AI.")
            }
            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}

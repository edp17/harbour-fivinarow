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
//pragma Singleton
import QtQuick 2.0
import Nemo.Configuration 1.0

ConfigurationGroup {
    id: settings
    path: "/apps/harbour-fivinarow/settings"

    // all your settings
    property string gameMode: "Player vs AI"
    property string aiDifficulty: "Medium"
    property string playerSymbol: "X"
    property string aiSymbol: "O"
    property string startingPlayer: "X"
    property string player1Name: qsTr("Player 1")
    property string player2Name: qsTr("Player 2")
    property string settingsVersion: "1.3"

    // UI state for SettingsPage expand/collapse
    property bool gameModeExpanded: true
    property bool difficultyExpanded: true
    property bool symbolExpanded: false
    property bool startExpanded: false
    property bool namesExpanded: false
    property bool boardExpanded: false
    property bool accessibilityExpanded: false
    property string bestTimesEasyJson: "[]"
    property string bestTimesMediumJson: "[]"
    property string bestTimesHardJson: "[]"
    property string bestTimesUnbeatableJson: "[]"

    // Board, rules and accessibility
    property int boardSize: 15
    property string winRule: "Freestyle"
    property bool showCoordinates: false
    property int boardZoomPercent: 100
    property bool hapticFeedback: true

    // Persistent session and aggregate results. The Expert table retains its
    // old key so upgrades do not discard RC1/RC2 scores.
    property string savedGameJson: ""
    property string statisticsJson: "{}"

    // Timing/UI behaviour
    property int aiThinkDelayMs: 300     // controls aiTimer.interval
}

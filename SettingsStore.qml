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
    property string player1Name: "Player 1"
    property string player2Name: "Player 2"
    property string settingsVersion: "1.0"

    // UI state for SettingsPage expand/collapse
    property bool gameModeExpanded: true
    property bool difficultyExpanded: true
    property bool symbolExpanded: false
    property bool startExpanded: false
    property bool namesExpanded: false
    property string bestTimesEasyJson: "[]"
    property string bestTimesMediumJson: "[]"
    property string bestTimesHardJson: "[]"

    // Forward-compatible knobs (safe defaults)
    property int boardSize: 15           // future: 9/13/15
    property int aiThinkDelayMs: 300     // controls aiTimer.interval
}
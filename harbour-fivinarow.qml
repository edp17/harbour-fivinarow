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
import Nemo.Configuration 1.0

ApplicationWindow {
    id: app
    
     SettingsStore { id: settings }
    property var appSettingsCopy: settings
    
    // Expose board and size to CoverPage
    property var liveBoard: []
    property int liveBoardSize: 0
    property bool liveGameOver: false
    property string liveWinnerText: ""
    property var liveWinningCells: []

    // Settings page component – pass the SAME settings object into it
    Component {
        id: settingsPageComponent
        SettingsPage { settings: appSettingsCopy }
    }
    
    Component {
        id: aboutPageComponent
        AboutPage { }
    }

    // Initial page – also receives the same settings object
    initialPage: Component {
        GameView { 
            id: gameView
            settings: appSettingsCopy 

            onCoverSnapshot: {
                app.liveBoard = boardMatrix
                app.liveBoardSize = boardSize
                app.liveGameOver = gameOver
                app.liveWinnerText = winnerText
                app.liveWinningCells = winningCells
            }
        }
    }

    // Cover page
    cover: Component {
        CoverPage {
            boardMatrix: liveBoard
            boardSize: liveBoardSize
            gameOver: liveGameOver
            winnerText: liveWinnerText
            winningCells: liveWinningCells
        }
    }
}

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
    
    property var appSettingsCopy: settings
    
    // Expose board and size to CoverPage
    property var liveBoard: []
    property int liveBoardSize: 0
    property bool liveGameOver: false
    property string liveWinnerText: ""

    ConfigurationGroup {
        id: settings

        // location in ~/.config/<org>/<app>.ini
        path: "/apps/harbour-fivinarow/settings"

        property string gameMode: "Player vs AI"
        property string aiDifficulty: "Medium"
        property string playerSymbol: "X"
        property string aiSymbol: "O"
        property string startingPlayer: "X"
        property string player1Name: "Player 1"
        property string player2Name: "Player 2"
        property string settingsVersion: "1.0"
        
        property bool gameModeExpanded: true
        property bool difficultyExpanded: true
        property bool symbolExpanded: false
        property bool startExpanded: false
        property bool namesExpanded: false
    }

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

        // whenever the board changes, update the cover snapshot
        onBoardChanged: {
            // shallow copy to decouple (optional but safer)
            app.liveBoard = board
            app.liveBoardSize = boardSize
            app.liveGameOver = gameOver
            app.liveWinnerText = winnerText
        }

        Component.onCompleted: {
            app.liveBoard = board
            app.liveBoardSize = boardSize
            app.liveGameOver = gameOver
            app.liveWinnerText = winnerText
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
        }
    }
}

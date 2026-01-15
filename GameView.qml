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
import QtQuick.Layouts 1.0
import Sailfish.Silica 1.0

Page {
    id: page

    // Settings object passed from ApplicationWindow
    property var settings

    // Dynamic automatic board scaling
    property real availableWidth: width
    property real availableHeight: height - pageHeader.height

    property real dynamicCellSize: Math.floor(
        Math.min(
            availableWidth / boardSize,
            availableHeight / boardSize,
            72       // Maximum size on big phones/tablets
        )
    )

    allowedOrientations: Orientation.All

    property int boardSize: 15
    property int cellSize: 72
    property var board: (function() {
        var b = []
        for (var i = 0; i < boardSize; i++) {
            b[i] = []
            for (var j = 0; j < boardSize; j++) b[i][j] = null
        }
        return b
    })()

    property string currentPlayer: "X"
    property bool gameOver: false
    property var winningCells: []
    property var undoStack: []
    property var redoStack: []
    property bool newGameStarted: false

    // -------------------------------
    // Utilities
    // -------------------------------
    function cloneBoard(src) {
        var out = []
        for (var r = 0; r < src.length; r++) {
            var row = []
            for (var c = 0; c < src[r].length; c++) row.push(src[r][c])
            out.push(row)
        }
        return out
    }

    function restartGame() {
        for (var i = 0; i < boardSize; i++)
            for (var j = 0; j < boardSize; j++) board[i][j] = null

        currentPlayer = settings ? settings.startingPlayer : "X"
        gameOver = false
        winningCells = []
        undoStack = []
        redoStack = []
        board = board

        // If AI should start, trigger move
        if (settings && settings.gameMode === "Player vs AI" &&
                currentPlayer === settings.aiSymbol) {
            aiTimer.start()
        }
        newGameStarted = true
        publishBoardToCover()
    }

    function declareWinner(player, cells) {
        winningCells = cells
        gameOver = true

        publishBoardToCover()
    }

    function checkWin(r, c) {
        var player = board[r][c]
        if (!player) return false

        function count(dx, dy) {
            var cnt = 0, x = r, y = c
            while (x >= 0 && x < boardSize && y >= 0 && y < boardSize &&
                   board[x][y] === player) {
                cnt++
                x += dx
                y += dy
            }
            return cnt - 1
        }

        var directions = [[1,0],[0,1],[1,1],[1,-1]]
        for (var i = 0; i < directions.length; i++) {
            var dx = directions[i][0], dy = directions[i][1]
            var len = count(dx, dy) + count(-dx, -dy) + 1
            if (len >= 5) {
                var cells = [], startX = r, startY = c
                while (startX - dx >= 0 && startX - dx < boardSize &&
                       startY - dy >= 0 && startY - dy < boardSize &&
                       board[startX - dx][startY - dy] === player) {
                    startX -= dx
                    startY -= dy
                }
                for (var j = 0; j < len; j++)
                    cells.push({ r: startX + j*dx, c: startY + j*dy })
                return cells
            }
        }
        return false
    }

    function getWinnerName(symbol) {
        if (!settings) return symbol

        if (settings.gameMode === "Player vs AI") {
            return (symbol === "X" && settings.playerSymbol === "X") ||
                   (symbol === "O" && settings.playerSymbol === "O")
                   ? "Player" : "AI"
        } else {
            // Player1 vs Player2: X = Player1, O = Player2
            if (symbol === "X")
                return settings.player1Name
            else
                return settings.player2Name
        }
    }

    function countLine(r, c, dr, dc, player) {
        var cnt = 0, x = r, y = c
        while (x >= 0 && x < boardSize && y >= 0 && y < boardSize &&
               board[x][y] === player) {
            cnt++
            x += dr
            y += dc
        }
        return cnt - 1
    }

    // -------------------------------
    // Heuristic used by Medium/Hard
    // -------------------------------
    function scoreCell(r, c, player) {
        var score = 0
        var dirs = [[1,0],[0,1],[1,1],[1,-1]]
        for (var d = 0; d < dirs.length; d++) {
            var dx = dirs[d][0], dy = dirs[d][1]
            var countF = 0
            var x = r + dx, y = c + dy
            while (x >= 0 && x < boardSize && y >= 0 && y < boardSize &&
                   board[x][y] === player) {
                countF++
                x += dx
                y += dy
            }
            var countB = 0
            x = r - dx
            y = c - dy
            while (x >= 0 && x < boardSize && y >= 0 && y < boardSize &&
                   board[x][y] === player) {
                countB++
                x -= dx
                y -= dy
            }
            var line = countF + countB + 1
            if (line >= 5) return 10000   // immediate win
            score += line * line          // weight longer lines more strongly
        }
        return score
    }

    // -------------------------------
    // MINIMAX helpers for HARD (Balanced)
    // -------------------------------
    function generateCandidatesForPlayer(emptyMoves, player, limit) {
        var ai = settings.aiSymbol
        var pl = settings.playerSymbol
        var opponent = (player === ai ? pl : ai)

        var scored = []
        for (var i = 0; i < emptyMoves.length; i++) {
            var m = emptyMoves[i]
            var s = 0

            // how good for this player
            s += scoreCell(m.r, m.c, player)

            // how good for opponent (slightly discounted)
            s += scoreCell(m.r, m.c, opponent) * 0.5

            // slight center preference
              var cd = Math.abs(m.r - boardSize/2) + 
                       Math.abs(m.c - boardSize/2)
            s -= cd * 0.02
            scored.push({ move: m, score: s })
        }
        scored.sort(function(a,b){ return b.score - a.score })
        var out = []
        for (var j = 0; j < Math.min(limit, scored.length); j++)
            out.push(scored[j].move)
        return out
    }

    // minimax with alpha-beta; depth counts plies remaining
    function minimax(depth, maximizingPlayer, alpha, beta) {
        var ai = settings.aiSymbol
        var pl = settings.playerSymbol

        if (depth === 0)
            return evaluateBoardForAI()

        // gather empties
        var empties = []
        for (var r = 0; r < boardSize; r++)
            for (var c = 0; c < boardSize; c++)
                if (!board[r][c]) empties.push({ r:r, c:c })

        if (empties.length === 0)
            return evaluateBoardForAI()

        if (maximizingPlayer) {
            // AI to move
            var candidates = generateCandidatesForPlayer(empties, ai, 6)
            var value = -1e12
            for (var i = 0; i < candidates.length; i++) {
                var m = candidates[i]
                board[m.r][m.c] = ai
                if (checkWin(m.r, m.c)) {
                    board[m.r][m.c] = null
                    return 1000000
                }
                var score = minimax(depth - 1, false, alpha, beta)
                board[m.r][m.c] = null
                if (score > value) value = score
                if (value > alpha) alpha = value
                if (alpha >= beta) break
            }
            return value
        } else {
            // opponent (Player) to move
            var candidatesOpp = generateCandidatesForPlayer(empties, pl, 6)
            var value2 = 1e12
            for (var j = 0; j < candidatesOpp.length; j++) {
                var mo = candidatesOpp[j]
                board[mo.r][mo.c] = pl
                if (checkWin(mo.r, mo.c)) {
                    board[mo.r][mo.c] = null
                    return -1000000
                }
                var score2 = minimax(depth - 1, true, alpha, beta)
                board[mo.r][mo.c] = null
                if (score2 < value2) value2 = score2
                if (value2 < beta) beta = value2
                if (alpha >= beta) break
            }
            return value2
        }
    }


    // -------------------------------
    // Helpers for Live preview on Cover page
    // -------------------------------
    function publishBoardToCover() {
        if (!pageStack || !Qt.application) return

        // Make a shallow copy so CoverPage doesn't bind to live board internals
        var copy = []
        for (var r = 0; r < boardSize; r++) {
            copy[r] = board[r].slice(0)
        }

        // Walk up to ApplicationWindow safely
        var root = page
        while (root && !root.liveBoard) {
            root = root.parent
        }

        if (root) {
            root.liveBoardSize = boardSize
            root.liveGameOver = gameOver ? gameOver : false
            var winnerText = getWinnerName(currentPlayer)
            root.liveWinnerText = winnerText

            if (!newGameStarted) {
                root.liveBoard = copy
            }
            else {
                root.liveBoard = []
                newGameStarted = false
            }
        }
    }

    // -------------------------------
    // selectAIMove() - dynamic symbols (AI = settings.aiSymbol)
    // Easy := light heuristic
    // Medium := depth-2 lookahead
    // Hard := depth-3 minimax
    // -------------------------------
    function selectAIMove() {
        var ai = settings.aiSymbol
        var pl = settings.playerSymbol
        var empty = []
        for (var r = 0; r < boardSize; r++)
            for (var c = 0; c < boardSize; c++)
                if (!board[r][c]) empty.push({ r: r, c: c })

        if (empty.length === 0) return null

        // --- EASY ---
        if (settings.aiDifficulty === "Easy") {
            // 1) immediate win for AI
            for (var i3 = 0; i3 < empty.length; i3++) {
                var m3 = empty[i3]
                board[m3.r][m3.c] = ai
                if (checkWin(m3.r, m3.c)) { board[m3.r][m3.c] = null; return m3 }
                board[m3.r][m3.c] = null
            }
            // 2) immediate block against player
            for (var i4 = 0; i4 < empty.length; i4++) {
                var m4 = empty[i4]
                board[m4.r][m4.c] = pl
                if (checkWin(m4.r, m4.c)) { board[m4.r][m4.c] = null; return m4 }
                board[m4.r][m4.c] = null
            }
            // 3) heuristic choice
            var bestScore = -1
            var bestMoves = []
            for (var i5 = 0; i5 < empty.length; i5++) {
                var mm = empty[i5]
                var s = scoreCell(mm.r, mm.c, ai) + scoreCell(mm.r, mm.c, pl) * 0.8
                var centerDist2 = Math.abs(mm.r - boardSize/2) + Math.abs(mm.c - boardSize/2)
                s -= centerDist2 * 0.1
                if (s > bestScore) {
                    bestScore = s
                    bestMoves = [mm]
                } else if (s === bestScore) {
                    bestMoves.push(mm)
                }
            }
            if (bestMoves.length > 0)
                return bestMoves[Math.floor(Math.random()*bestMoves.length)]
            return empty[Math.floor(Math.random()*empty.length)]
        }

        // --- MEDIUM: depth-2 lookahead (AI -> Opp) ---
        if (settings.aiDifficulty === "Medium") {
            // 1) immediate win
            for (var ii = 0; ii < empty.length; ii++) {
                var mm0 = empty[ii]
                board[mm0.r][mm0.c] = ai
                if (checkWin(mm0.r, mm0.c)) { board[mm0.r][mm0.c] = null; return mm0 }
                board[mm0.r][mm0.c] = null
            }
            // 2) immediate block
            for (var jj = 0; jj < empty.length; jj++) {
                var mm1 = empty[jj]
                board[mm1.r][mm1.c] = pl
                if (checkWin(mm1.r, mm1.c)) { board[mm1.r][mm1.c] = null; return mm1 }
                board[mm1.r][mm1.c] = null
            }

            // heuristic scoring of candidates
            var scored = []
            for (var sidx = 0; sidx < empty.length; sidx++) {
                var eee = empty[sidx]
                var s0 = scoreCell(eee.r, eee.c, ai) + scoreCell(eee.r, eee.c, pl) * 0.6
                var cd = Math.abs(eee.r - boardSize/2) + Math.abs(eee.c - boardSize/2)
                s0 -= cd * 0.05
                scored.push({ move: eee, score: s0 })
            }
            scored.sort(function(a,b){ return b.score - a.score })

            var N = Math.min(8, scored.length)
            var opponentCandidatesLimit = Math.min(8, scored.length)

            var bestMove = null
            var bestMoveValue = -1e9

            for (var ci = 0; ci < N; ci++) {
                var cand = scored[ci].move
                board[cand.r][cand.c] = ai
                if (checkWin(cand.r, cand.c)) { board[cand.r][cand.c] = null; return cand }

                // opponent replies
                var oppScored = []
                for (var oi = 0; oi < empty.length; oi++) {
                    var om = empty[oi]
                    if (om.r === cand.r && om.c === cand.c) continue
                    var s1 = scoreCell(om.r, om.c, pl) + scoreCell(om.r, om.c, ai) * 0.5
                    oppScored.push({ move: om, score: s1 })
                }
                oppScored.sort(function(a,b){ return b.score - a.score })
                var M = Math.min(opponentCandidatesLimit, oppScored.length)

                if (M === 0) {
                    var valOnly = evaluateBoardForAI()
                    board[cand.r][cand.c] = null
                    if (valOnly > bestMoveValue) {
                        bestMoveValue = valOnly
                        bestMove = cand
                    }
                    continue
                }

                var worstForAI = 1e9
                for (var oj = 0; oj < M; oj++) {
                    var opp = oppScored[oj].move
                    board[opp.r][opp.c] = pl
                    var val
                    if (checkWin(opp.r, opp.c)) {
                        val = -10000
                    } else {
                        val = evaluateBoardForAI()
                    }
                    board[opp.r][opp.c] = null
                    if (val < worstForAI) worstForAI = val
                    if (worstForAI <= bestMoveValue) break
                }

                board[cand.r][cand.c] = null

                if (worstForAI > bestMoveValue) {
                    bestMoveValue = worstForAI
                    bestMove = cand
                }
            }

            if (bestMove) return bestMove
            return scored[Math.floor(Math.random()*scored.length)].move
        }

        // --- HARD: depth-3 minimax with heuristics ---
        if (settings.aiDifficulty === "Hard") {
            // 1) immediate win
            for (var ii2 = 0; ii2 < empty.length; ii2++) {
                var mm2 = empty[ii2]
                board[mm2.r][mm2.c] = ai
                if (checkWin(mm2.r, mm2.c)) { board[mm2.r][mm2.c] = null; return mm2 }
                board[mm2.r][mm2.c] = null
            }
            // 2) immediate block
            for (var jj2 = 0; jj2 < empty.length; jj2++) {
                var mm3 = empty[jj2]
                board[mm3.r][mm3.c] = pl
                if (checkWin(mm3.r, mm3.c)) { board[mm3.r][mm3.c] = null; return mm3 }
                board[mm3.r][mm3.c] = null
            }

            var scored2 = []
            for (var sidx2 = 0; sidx2 < empty.length; sidx2++) {
                var e2 = empty[sidx2]
                var s02 = scoreCell(e2.r, e2.c, ai) + scoreCell(e2.r, e2.c, pl) * 0.6
                var cd2 = Math.abs(e2.r - boardSize/2) + Math.abs(e2.c - boardSize/2)
                s02 -= cd2 * 0.05
                scored2.push({ move: e2, score: s02 })
            }
            scored2.sort(function(a,b){ return b.score - a.score })

            var rootCandidates = Math.min(6, scored2.length)
            var bestMove2 = null
            var bestValue = -1e12
            var DEPTH = 3

            for (var ci2 = 0; ci2 < rootCandidates; ci2++) {
                var cand2 = scored2[ci2].move
                board[cand2.r][cand2.c] = ai
                if (checkWin(cand2.r, cand2.c)) { board[cand2.r][cand2.c] = null; return cand2 }
                var val2 = minimax(DEPTH - 1, false, -1e12, 1e12)
                board[cand2.r][cand2.c] = null
                if (val2 > bestValue) {
                    bestValue = val2
                    bestMove2 = cand2
                }
            }

            if (bestMove2) return bestMove2
            return scored2[Math.floor(Math.random()*scored2.length)].move
        }

        // fallback generic
        return empty[Math.floor(Math.random()*empty.length)]
    }

    // evaluateBoardForAI: heuristic evaluation from AI perspective
    function evaluateBoardForAI() {
        var ai = settings.aiSymbol
        var pl = settings.playerSymbol
        var scoreO = 0
        var scoreX = 0
        for (var r = 0; r < boardSize; r++) {
            for (var c = 0; c < boardSize; c++) {
                if (!board[r][c]) {
                    scoreO += scoreCell(r, c, ai)
                    scoreX += scoreCell(r, c, pl)
                } else {
                    if (board[r][c] === ai) scoreO += 3
                    if (board[r][c] === pl) scoreX += 3
                }
            }
        }
        return scoreO - scoreX * 0.9
    }

    Timer {
        id: aiTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (gameOver) return
            if (!settings || settings.gameMode !== "Player vs AI") return
            var ai = settings.aiSymbol
            var pl = settings.playerSymbol
            var move = selectAIMove()
            if (!move) return
            undoStack.push({ board: cloneBoard(board), player: currentPlayer })
            redoStack = []
            board[move.r][move.c] = ai
            board = board
            publishBoardToCover()
            var cells = checkWin(move.r, move.c)
            if (cells) declareWinner(ai, cells)
            else currentPlayer = pl
        }
    }

    // -------------------------------
    // Game board and Pulley
    // -------------------------------
    SilicaFlickable {
        id: flick
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width

        contentWidth: boardSize * dynamicCellSize
        contentHeight: boardSize * dynamicCellSize

        PullDownMenu {
            MenuItem { text: qsTr("New Game"); onClicked: restartGame() }
            MenuItem { text: qsTr("Undo"); onClicked: undoMove() }
            MenuItem { text: qsTr("Redo"); onClicked: redoMove() }
            MenuItem {
                text: qsTr("Settings")
                onClicked: {
                    var s = settings;
                    pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { settings: s })
                }
            }
            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(aboutPageComponent)
            }
            MenuItem { text: qsTr("Quit"); onClicked: Qt.quit() }
        }

        // PAGE HEADER
        PageHeader {
            id: pageHeader
            title: qsTr("Five in a Row")
            leftMargin: Theme.itemSizeMedium
        }

        // -------------------------------
        // Unified Top Bar (Two Rows)
        // -------------------------------
        Item {
            id: unifiedTopBar
            anchors.top: pageHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.itemSizeLarge * 1.4
            anchors.topMargin: Theme.paddingSmall

            Rectangle {
                anchors.fill: parent
                color: "#40404080"
                radius: Theme.roundingSmall
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.paddingMedium
                spacing: Theme.paddingSmall

                // Row 1: Game Mode
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.paddingSmall

                    Text {
                        text: "Mode:"
                        font.pixelSize: Theme.fontSizeMedium
                        color: "white"
                    }

                    Text {
                        text: settings.gameMode
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        color: "white"
                    }
                }

                // Row 2: Turn indicator
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.paddingSmall

                    Text {
                        text: "Turn:"
                        font.pixelSize: Theme.fontSizeMedium
                        color: "white"
                    }

                    Text {
                        id: turnValueText
                        text: {
                            if (settings.gameMode === "Player vs AI")
                                return currentPlayer === settings.playerSymbol ? "Player" : "AI"
                            else
                                return currentPlayer === "X" ? settings.player1Name : settings.player2Name
                        }
                        font.bold: true
                        font.pixelSize: Theme.fontSizeMedium
                        color: "white"
                    }
                }
            }
        }
        
        // -------------------------------
        // Board Area
        // -------------------------------
        Item {
            id: boardArea
            anchors.top: unifiedTopBar.bottom
            anchors.topMargin: Theme.paddingMedium
            width: flick.contentWidth
            height: flick.contentHeight

            Repeater {
                model: boardSize * boardSize

                Rectangle {
                    width: dynamicCellSize
                    height: dynamicCellSize
                    x: (index % boardSize) * dynamicCellSize
                    y: Math.floor(index / boardSize) * dynamicCellSize
                    border.color: "black"

                    color: {
                        var r = Math.floor(index / boardSize)
                        var c = index % boardSize
                        for (var i = 0; i < winningCells.length; i++)
                            if (winningCells[i].r === r &&
                                winningCells[i].c === c)
                                return "gold"
                        if (board[r][c] === "X") return "#aaddff"
                        if (board[r][c] === "O") return "#ffccdd"
                        return "white"
                    }

                    Text {
                        id: cellText
                        anchors.centerIn: parent
                        text: {
                            var r = Math.floor(index / boardSize)
                            var c = index % boardSize
                            return board[r][c] || ""
                        }
                        font.bold: true
                        font.pixelSize: dynamicCellSize * 0.7
                        color: {
                            var r = Math.floor(index / boardSize)
                            var c = index % boardSize
                            if (board[r][c] === "X") return "darkblue"
                            if (board[r][c] === "O") return "red"
                            return "black"
                        }

                        scale: 1
                        opacity: 1

                        Behavior on scale {
                            NumberAnimation { duration: 250; easing.type: Easing.OutBounce }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
                        }

                        onTextChanged: {
                            if (text !== "") {
                                scale = 0
                                opacity = 0
                                scale = 1
                                opacity = 1
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (gameOver) return
                            var r = Math.floor(index / boardSize)
                            var c = index % boardSize
                            if (!board[r][c]) {
                                undoStack.push({ board: cloneBoard(board), player: currentPlayer })
                                redoStack = []
                                board[r][c] = currentPlayer
                                board = board
                                publishBoardToCover()
                                var cells = checkWin(r, c)
                                if (cells) {
                                    declareWinner(currentPlayer, cells)
                                } else {
                                    currentPlayer = (currentPlayer === "X") ? "O" : "X"
                                    if (settings && settings.gameMode === "Player vs AI" &&
                                            currentPlayer === settings.aiSymbol)
                                        aiTimer.start()
                                }
                            }
                        }
                    }
                }
            }
        }

        // Difficulty indicator under the board
        Rectangle {
            id: difficultyBanner
            anchors.top: boardArea.bottom
            anchors.topMargin: Theme.paddingSmall
            anchors.horizontalCenter: parent.horizontalCenter

            width: parent.width * 0.6
            height: Theme.itemSizeSmall
            radius: Theme.paddingSmall
            color: "#40404080"
            visible: settings && (settings.gameMode === "Player vs AI")

            Row {
                anchors.centerIn: parent
                spacing: Theme.paddingMedium

                Label {
                    text: qsTr("Difficulty:")
                    font.bold: false
                    font.pixelSize: Theme.fontSizeMedium
                    color: "white"
                }

                Label {
                    text: settings ? settings.aiDifficulty : ""
                    font.bold: true
                    font.pixelSize: Theme.fontSizeMedium
                    color: "white"
                }
            }
        }

        // GAME OVER banner directly under difficulty
        Label {
            id: gameOverLabel
            anchors.top: difficultyBanner.bottom
            anchors.topMargin: Theme.paddingLarge
            anchors.horizontalCenter: parent.horizontalCenter

            visible: gameOver
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.RichText
            font.pixelSize: Theme.fontSizeLarge

            property string winnerText: {
                if (!gameOver) return ""
                var winnerName = getWinnerName(currentPlayer)
                return "<b><font color='gold'>Game Over!</font></b><br>" +
                       "<font color='white'>Winner: </font>" +
                       "<b><font color='gold'>" + winnerName + "</font></b>"
            }

            text: winnerText

            // OPTIONAL: cute bounce animation
            Behavior on opacity { NumberAnimation { duration: 250 } }
            opacity: gameOver ? 1 : 0
        }
    }

    // -------------------------------
    // Undo/Redo
    // -------------------------------
    function undoMove() {
        if (undoStack.length === 0) return
        var last = undoStack.pop()
        redoStack.push({ board: cloneBoard(board), player: currentPlayer })
        board = last.board.map(function(r) {
            var a = []
            for (var i = 0; i < r.length; i++) a.push(r[i])
            return a
        })
        currentPlayer = last.player
        winningCells = []
        gameOver = false
    }

    function redoMove() {
        if (redoStack.length === 0) return
        var next = redoStack.pop()
        undoStack.push({ board: cloneBoard(board), player: currentPlayer })
        board = next.board.map(function(r) {
            var a = []
            for (var i = 0; i < r.length; i++) a.push(r[i])
            return a
        })
        currentPlayer = next.player
        winningCells = []
        gameOver = false
    }

    // Make sure we pick up startingPlayer once settings is actually set
    Component.onCompleted: {
        if (settings)
            currentPlayer = settings.startingPlayer
        else
            currentPlayer = "X"
    }
}

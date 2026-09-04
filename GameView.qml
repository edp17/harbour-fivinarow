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
import QtFeedback 5.0
import Sailfish.Silica 1.0
import harbour.fivinarow 1.0

Page {
    id: page

    // Settings object passed from ApplicationWindow
    property var settings
    signal coverSnapshot(var boardMatrix, int boardSize, bool gameOver, bool gameDraw,
                         string winnerText, var winningCells)

    // Dynamic automatic board scaling
    property real availableWidth: width
    property real availableHeight: height - pageHeader.height

    property real fitCellSize: Math.floor(
        Math.min(
            availableWidth / boardSize,
            availableHeight / boardSize,
            72       // Maximum size on big phones/tablets
        )
    )
    property real dynamicCellSize: Math.max(20, Math.floor(
        fitCellSize * (settings ? settings.boardZoomPercent : 100) / 100))
    property real coordinateMargin: settings && settings.showCoordinates
                                    ? Theme.itemSizeExtraSmall : 0

    property int lastMoveR: -1
    property int lastMoveC: -1
    property int hardMinThinkMs: (settings ? settings.aiThinkDelayMs : 250)
    property double hardThinkStartMs: 0
    property var pendingAiMove: null
    property bool aiThinking: false
    property var hardRoot: []
    property var hardEvaluated: []
    property int hardIndex: 0
    property var hardBestMove: null
    property real hardBestVal: -1e18
    // Hard
    property int hardK: 14                 // number of root moves to examine
    property int hardOppLimit: 18          // opponent reply candidates (bounded)
    property int hardCandLimit: 80         // near-stone candidates (bounded)
    // aiRandomness: 0  - off/deterministic, 
    // aiRandomness: 1  - small, 
    // aiRandomness: 2  - normal/human-feeling variety without obvious blunders, 
    // aiRandomness: 3  - more
    // aiRandomness: 5+ - starts to get sloppy
    property int aiRandomness: 2
    // Expert fallback search (the compiled engine is the normal path)
    property int unbeatableDepth: 8          // 6 plies forcing search (try 8 if still fast)
    property int unbeatableNodeBudget: 4000  // per root eval, keeps it responsive
    property int unbeatableK: 14             // evaluate more root moves than Hard

    property double aiRandomState: 1
    property int gameSequence: 0
    property int aiRequestSerial: 0
    property int activeAiRequest: 0
    property int lastAiDepth: 0
    property double lastAiNodes: 0
    property bool initializationComplete: false

    Connections {
        target: settings
        onBoardSizeChanged: {
            if (initializationComplete && moveCount() === 0) restartGame()
        }
        onWinRuleChanged: {
            if (initializationComplete && moveCount() === 0) restartGame()
        }
    }

    GomokuAI {
        id: nativeAI

        onMoveReady: {
            if (requestId !== activeAiRequest) return
            if (gameOver || !settings || settings.gameMode !== "Player vs AI" ||
                    currentPlayer !== settings.aiSymbol) {
                aiThinking = false
                return
            }

            lastAiDepth = completedDepth
            lastAiNodes = nodes
            var move = { r: row, c: column }
            if (!isValidMoveObj(move) || !inBounds(move.r, move.c) ||
                    board[move.r][move.c] !== null) {
                console.warn("[AI] Native engine returned invalid move:", row, column)
                move = selectAIMove()
            }

            if (isValidMoveObj(move)) commitHardMove(move)
            else aiThinking = false
        }
    }

    function reseedAI() {
        gameSequence++
        var timePart = Date.now() & 0x7fffffff
        var enginePart = Math.floor(Math.random() * 0x7fffffff)
        aiRandomState = (timePart ^ enginePart ^ (gameSequence * 2654435761)) >>> 0
        if (aiRandomState === 0) aiRandomState = 0x6d2b79f5
    }

    function randomUnit() {
        var x = Math.floor(aiRandomState) | 0
        x ^= x << 13
        x ^= x >>> 17
        x ^= x << 5
        aiRandomState = x >>> 0
        return aiRandomState / 4294967296
    }

    function randInt(n) {
        return n > 0 ? Math.floor(randomUnit() * n) : 0
    }

    ThemeEffect {
        id: placementHaptic
        effect: ThemeEffect.Press
    }

    function playHapticFeedback() {
        if (!settings || !settings.hapticFeedback) return
        try {
            if (placementHaptic.supported)
                placementHaptic.play()
        } catch (error) {
            console.warn("Could not play haptic feedback:", error)
        }
    }

    function chooseVariedMove(scored, maxChoices, relativeTolerance, minimumTolerance) {
        if (!scored || scored.length === 0) return null

        var ordered = scored.slice(0)
        ordered.sort(function(a, b) { return b.s - a.s })

        var best = ordered[0].s
        var tolerance = Math.max(minimumTolerance || 0,
                                 Math.abs(best) * (relativeTolerance || 0))
        var band = []
        var count = Math.min(maxChoices || 1, ordered.length)
        for (var i = 0; i < count; i++) {
            if (best - ordered[i].s <= tolerance) band.push(ordered[i].m)
        }
        if (band.length === 0) band.push(ordered[0].m)

        // Favour the stronger end of the band without replaying one fixed line.
        var totalWeight = 0
        for (var w = 0; w < band.length; w++) totalWeight += band.length - w
        var pick = randomUnit() * totalWeight
        for (var j = 0; j < band.length; j++) {
            pick -= band.length - j
            if (pick <= 0) return band[j]
        }
        return band[0]
    }

    property bool gameTimerRunning: false
    property double gameStartMs: 0
    property int elapsedMs: 0
    property bool timerStartedThisGame: false
    property var tssCache: ({})   // simple JS object cache
    property int tssCacheMax: 4000
    property int unbeatableProofTopN: 5   // only run forced-win proof on first 5 root moves

    property var profitSelfEasy:   [0, 2, 12, 80, 1200]
    property var profitSelfHard:   [0, 3, 50, 200, 6000]   // like 0v.hu computer
    property var profitOppHard:    [0, 2, 49, 199, 50000]  // like getOpponentProfitValue()
    property var profitSelfMedium: [0, 3, 25, 140, 3500]
    property var profitOppMedium:  [0, 2, 35, 160, 30000]

    Timer {
        id: gameTimer
        interval: 200   // smoother display than 1000; cheap enough
        repeat: true
        running: gameTimerRunning
        onTriggered: {
            elapsedMs = Math.max(0, Date.now() - gameStartMs)
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: !gameOver && moveCount() > 0
        onTriggered: saveGameState()
    }

    Timer {
        id: hardThinkTimer
        interval: 1        // 1–5ms; 1 yields fastest
        repeat: true
        running: false
        onTriggered: hardThinkStep()
    }

    Timer {
        id: hardApplyDelayTimer
        interval: 0
        repeat: false
        onTriggered: {
            var m = pendingAiMove
            pendingAiMove = null
            aiThinking = false
            if (m && m.r !== undefined && m.c !== undefined)
                applyMove(m.r, m.c)
        }
    }

    function boardKey(side) {
        // side: "X"/"O"
        var s = side + "|"
        for (var r=0; r<boardSize; r++) {
            for (var c=0; c<boardSize; c++) {
                var v = board[r][c]
                s += (v === null ? "." : v)
            }
            s += "/"
        }
        return s
    }

    function mustResponses(opp, sym, limit) {
        // opp is to move; sym is the attacker we are responding to
        var cand = generateCandidates(2, 120, opp)
        if (!cand || cand.length === 0) return []

        var out = []
        for (var i=0;i<cand.length;i++) {
            var m = cand[i]
            if (!m) continue
            var tOpp = moveThreats(m.r, m.c, opp)
            if (tOpp && tOpp.win) { out.push(m); continue }

            // block attacker open-four / fork
            var tSym = moveThreats(m.r, m.c, sym)
            if (tSym && (tSym.openFour > 0 || tSym.win)) { out.push(m); continue }
        }

        out.sort(function(a,b){
            return tacticalScoreMove(b.r,b.c,opp,sym) - tacticalScoreMove(a.r,a.c,opp,sym)
        })
        if (limit && out.length > limit) out.length = limit
        return out
    }

    function profitBestMove(aiSym, oppSym, profitSelf, profitOpp,
                            maxChoices, relativeTolerance, minimumTolerance) {
        var n = boardSize
        // matrix[y][x]
        var pm = []
        for (var y = 0; y < n; y++) {
            pm[y] = []
            for (var x = 0; x < n; x++) pm[y][x] = 0
        }

        function addWindow(points) {
            var a = 0, o = 0
            for (var k = 0; k < 5; k++) {
                var p = points[k]
                var v = board[p.r][p.c]
                if (v === aiSym) a++
                else if (v === oppSym) o++
            }
            if (a > 0 && o > 0) return  // mixed => dead window

            var r = 0
            if (a > 0) r = profitSelf[a]
            else if (o > 0) r = profitOpp[o]
            else r = 0

            if (r === 0) return
            for (var k2 = 0; k2 < 5; k2++) {
                var p2 = points[k2]
                pm[p2.r][p2.c] += r
            }
        }

        // Horizontal
        for (var r = 0; r < n; r++) {
            for (var c = 0; c <= n - 5; c++) {
                addWindow([{r:r,c:c},{r:r,c:c+1},{r:r,c:c+2},{r:r,c:c+3},{r:r,c:c+4}])
            }
        }
        // Vertical
        for (var c2 = 0; c2 < n; c2++) {
            for (var r2 = 0; r2 <= n - 5; r2++) {
                addWindow([{r:r2,c:c2},{r:r2+1,c:c2},{r:r2+2,c:c2},{r:r2+3,c:c2},{r:r2+4,c:c2}])
            }
        }
        // Diagonal down-right
        for (var r3 = 0; r3 <= n - 5; r3++) {
            for (var c3 = 0; c3 <= n - 5; c3++) {
                addWindow([{r:r3,c:c3},{r:r3+1,c:c3+1},{r:r3+2,c:c3+2},{r:r3+3,c:c3+3},{r:r3+4,c:c3+4}])
            }
        }
        // Diagonal up-right
        for (var r4 = 4; r4 < n; r4++) {
            for (var c4 = 0; c4 <= n - 5; c4++) {
                addWindow([{r:r4,c:c4},{r:r4-1,c:c4+1},{r:r4-2,c:c4+2},{r:r4-3,c:c4+3},{r:r4-4,c:c4+4}])
            }
        }

        // Select from a narrow score band. This keeps tactical priorities while
        // avoiding the same positional reply in every repeated game.
        var scoredMoves = []
        for (var rr = 0; rr < n; rr++) {
            for (var cc = 0; cc < n; cc++) {
                if (board[rr][cc] !== null) continue
                var centerDistance = Math.abs(rr - (n - 1) / 2) +
                                     Math.abs(cc - (n - 1) / 2)
                var centerBias = Math.max(0, n - centerDistance) * 0.25
                scoredMoves.push({ m: { r: rr, c: cc }, s: pm[rr][cc] + centerBias })
            }
        }
        if (scoredMoves.length === 0) return firstEmptyFallback()
        return chooseVariedMove(scoredMoves, maxChoices || 1,
                                relativeTolerance || 0, minimumTolerance || 0)
    }

    function profitMatrixScores(aiSym, oppSym, profitSelf, profitOpp) {
        var n = boardSize
        var pm = []
        for (var y = 0; y < n; y++) {
            pm[y] = []
            for (var x = 0; x < n; x++) pm[y][x] = 0
        }

        function addWindow(points) {
            var a = 0, o = 0
            for (var k = 0; k < 5; k++) {
                var p = points[k]
                var v = board[p.r][p.c]
                if (v === aiSym) a++
                else if (v === oppSym) o++
            }
            if (a > 0 && o > 0) return

            var r = 0
            if (a > 0) r = profitSelf[a]
            else if (o > 0) r = profitOpp[o]
            if (r === 0) return

            for (var k2 = 0; k2 < 5; k2++) {
                var p2 = points[k2]
                pm[p2.r][p2.c] += r
            }
        }

        // Horizontal
        for (var r0 = 0; r0 < n; r0++)
            for (var c0 = 0; c0 <= n - 5; c0++)
                addWindow([{r:r0,c:c0},{r:r0,c:c0+1},{r:r0,c:c0+2},{r:r0,c:c0+3},{r:r0,c:c0+4}])

        // Vertical
        for (var c1 = 0; c1 < n; c1++)
            for (var r1 = 0; r1 <= n - 5; r1++)
                addWindow([{r:r1,c:c1},{r:r1+1,c:c1},{r:r1+2,c:c1},{r:r1+3,c:c1},{r:r1+4,c:c1}])

        // Diagonal down-right
        for (var r2 = 0; r2 <= n - 5; r2++)
            for (var c2 = 0; c2 <= n - 5; c2++)
                addWindow([{r:r2,c:c2},{r:r2+1,c:c2+1},{r:r2+2,c:c2+2},{r:r2+3,c:c2+3},{r:r2+4,c:c2+4}])

        // Diagonal up-right
        for (var r3 = 4; r3 < n; r3++)
            for (var c3 = 0; c3 <= n - 5; c3++)
                addWindow([{r:r3,c:c3},{r:r3-1,c:c3+1},{r:r3-2,c:c3+2},{r:r3-3,c:c3+3},{r:r3-4,c:c3+4}])

        return pm
    }

    function resetGameTimer() {
        elapsedMs = 0
        gameStartMs = Date.now()
    }

    function stopGameTimer() {
        gameTimerRunning = false
    }

    function formatMs(ms) {
        var totalSec = Math.floor(ms / 1000)
        var min = Math.floor(totalSec / 60)
        var sec = totalSec % 60
        var mm = (min < 10 ? "0" : "") + min
        var ss = (sec < 10 ? "0" : "") + sec
        return mm + ":" + ss
    }

    function gameModeLabel(mode) {
        if (mode === "Player vs AI") return qsTr("Player vs AI")
        if (mode === "Player1 vs Player2") return qsTr("Player 1 vs Player 2")
        return mode || ""
    }

    function difficultyLabel(difficulty) {
        if (difficulty === "Easy") return qsTr("Easy")
        if (difficulty === "Medium") return qsTr("Medium")
        if (difficulty === "Hard") return qsTr("Hard")
        if (difficulty === "Expert" || difficulty === "Unbeatable") return qsTr("Expert")
        return difficulty || ""
    }

    function bestTimesKeyForDifficulty() {
        var d = settings ? settings.aiDifficulty : "Easy"
        if (d === "Expert" || d === "Unbeatable") return "bestTimesUnbeatableJson"
        if (d === "Hard") return "bestTimesHardJson"
        if (d === "Medium") return "bestTimesMediumJson"
        return "bestTimesEasyJson"
    }

    function loadBestTimesArray(jsonStr) {
        try {
            var arr = JSON.parse(jsonStr || "[]")
            return Array.isArray(arr) ? arr : []
        } catch (e) {
            return []
        }
    }

    function saveBestTimesArray(key, arr) {
        var json = JSON.stringify(arr)
        if (key === "bestTimesEasyJson") settings.bestTimesEasyJson = json
        else if (key === "bestTimesMediumJson") settings.bestTimesMediumJson = json
        else if (key === "bestTimesHardJson") settings.bestTimesHardJson = json
        else if (key === "bestTimesUnbeatableJson") settings.bestTimesUnbeatableJson = json
    }

    function recordBestTime(ms) {
        if (!settings) return
        var key = bestTimesKeyForDifficulty()
        var arr = loadBestTimesArray(settings[key])

        // add entry
        arr.push({
            name: settings.player1Name,
            ms: ms,
            at: Date.now(),
            boardSize: boardSize,
            winRule: activeWinRule
        })

        // sort ascending by time
        arr.sort(function(a,b){ return a.ms - b.ms })

        // Keep six results for every board/rule combination. Old records did
        // not have metadata and are treated as 15x15 freestyle results.
        var kept = [], counts = ({})
        for (var i = 0; i < arr.length; i++) {
            var size = arr[i].boardSize || 15
            var rule = arr[i].winRule || "Freestyle"
            var configKey = size + "|" + rule
            counts[configKey] = counts[configKey] || 0
            if (counts[configKey] < 6) {
                kept.push(arr[i])
                counts[configKey]++
            }
        }

        saveBestTimesArray(key, kept)
    }

    function commitHardMove(m) {
        hardThinkTimer.stop()
        if (!m || m.r === undefined || m.c === undefined) {
            aiThinking = false
            return
        }

        pendingAiMove = { r: m.r, c: m.c }

        var elapsed = Date.now() - hardThinkStartMs
        var remaining = hardMinThinkMs - elapsed
        if (remaining > 0) {
            hardApplyDelayTimer.interval = remaining
            hardApplyDelayTimer.start()
        } else {
            hardApplyDelayTimer.interval = 0
            hardApplyDelayTimer.start()
        }
    }

    allowedOrientations: Orientation.All

    property int boardSize: 15
    property var board: createEmptyBoard(boardSize)
    property string activeWinRule: "Freestyle"

    property string currentPlayer: "X"
    property bool gameOver: false
    property bool gameDraw: false
    property var winningCells: []
    property var undoStack: []
    property var redoStack: []
    property bool newGameStarted: false
    readonly property bool aiBusy: aiThinking || aiTimer.running ||
                                   hardThinkTimer.running || hardApplyDelayTimer.running

    RemorsePopup { id: newGameRemorse }

    // -------------------------------
    // Utilities
    // -------------------------------
    function forcingMovesFor(sym, opp, limit) {
        // Forcing = win, open-four, block open-four, fork (double open-three)
        var cand = generateCandidates(2, 120, sym)
        if (!cand || cand.length === 0) return []

        var out = []
        for (var i = 0; i < cand.length; i++) {
            var m = cand[i]
            if (!m) continue
            var tS = moveThreats(m.r, m.c, sym)
            var tO = moveThreats(m.r, m.c, opp)

            if (!tS || !tO) continue

            if (tS.win ||
                tS.openFour > 0 ||
                tO.openFour > 0 ||
                tS.openThree >= 2 ||
                tO.openThree >= 2) {
                out.push(m)
            }
        }

        // Order by tactical score (good for pruning)
        out.sort(function(a,b){
            return tacticalScoreMove(b.r, b.c, sym, opp) - tacticalScoreMove(a.r, a.c, sym, opp)
        })

        if (limit && out.length > limit) out.length = limit
        return out
    }

    function proveForcedWin(sym, opp, depth, budgetObj) {
        if (depth <= 0 || budgetObj.n <= 0) return false

        var key = boardKey(sym) + "|d" + depth
        if (tssCache[key] !== undefined) return tssCache[key]

        // keep cache bounded
        if (Object.keys(tssCache).length > tssCacheMax) tssCache = ({})

        var fm = forcingMovesFor(sym, opp, 8)
        if (fm.length === 0) { tssCache[key] = false; return false }

        for (var i=0; i<fm.length; i++) {
            if (budgetObj.n-- <= 0) break
            var m = fm[i]

            board[m.r][m.c] = sym
            var tNow = moveThreats(m.r, m.c, sym)
            if (tNow && tNow.win) { board[m.r][m.c] = null; tssCache[key] = true; return true }

            // opponent must-responses only
            var replies = mustResponses(opp, sym, 6)

            var ok = true
            for (var j=0; j<replies.length; j++) {
                if (budgetObj.n-- <= 0) { ok = false; break }
                var o = replies[j]
                board[o.r][o.c] = opp

                var tOpp = moveThreats(o.r, o.c, opp)
                if (tOpp && tOpp.win) ok = false
                else ok = proveForcedWin(sym, opp, depth-2, budgetObj)

                board[o.r][o.c] = null
                if (!ok) break
            }

            board[m.r][m.c] = null
            if (ok) { tssCache[key] = true; return true }
        }

        tssCache[key] = false
        return false
    }

    function proveForcedWinFromOppTurn(ai, pl, depth, budgetObj) {
        // Board state is AFTER AI has played, and it is now player's (pl) turn.
        // We want to know: can AI still force a win no matter how player responds?

        if (depth <= 0 || budgetObj.n <= 0) return false

        // Opponent replies (must-responses only)
        var replies = mustResponses(pl, ai, 6)

        // If no forcing replies exist, we can't "prove" via threat space;
        // fall back to "not proven" (false). (Your normal eval still handles the quiet case.)
        if (!replies || replies.length === 0) return false

        for (var j = 0; j < replies.length; j++) {
            if (budgetObj.n-- <= 0) return false
            var o = replies[j]
            if (!o) continue

            board[o.r][o.c] = pl
            // After opponent response, it's AI's turn and we can try to prove a forced win for AI.
            var ok = proveForcedWin(ai, pl, depth - 1, budgetObj)
            board[o.r][o.c] = null

            if (!ok) return false   // opponent found a reply that stops the forced win
        }
        return true
    }

    function startHardAI() {
        // Don't start if already running
        if (aiThinking) return
        if (gameOver) return
        if (!settings || settings.gameMode !== "Player vs AI") return
        if (currentPlayer !== settings.aiSymbol) return

        // Cancel any previous pending hard AI work (safety)
        hardThinkTimer.stop()
        hardApplyDelayTimer.stop()
        pendingAiMove = null

        // Start timing and lock UI
        hardThinkStartMs = Date.now()
        aiThinking = true

        var ai = settings.aiSymbol
        var pl = settings.playerSymbol

        if (settings.aiDifficulty === "Unbeatable") {
            hardK = unbeatableK
            hardOppLimit = 18
            hardCandLimit = 90
        } else {
            hardK = 10
            hardOppLimit = 14
            hardCandLimit = 60
        }

        // Must-win / must-block (fast)
        var winNow = findImmediateWinMove(ai)
        if (winNow) { commitHardMove(winNow); return }

        var blockNow = findImmediateWinMove(pl)
        if (blockNow) { commitHardMove(blockNow); return }

        // Build candidate list once
        var cand = generateCandidates(2, hardCandLimit, ai)
        if (!cand || cand.length === 0) {
            var fb = firstEmptyFallback()
            if (fb) { commitHardMove(fb); return }
            aiThinking = false
            return
        }

        // Score root moves cheaply first, then only keep top K
        var scored = []
        for (var i = 0; i < cand.length; i++) {
            var m = cand[i]
            if (!m) continue
            var base = tacticalScoreMove(m.r, m.c, ai, pl)
            var modifier = (randomUnit() - 0.5) * aiRandomness
            scored.push({ m: m, s: base + modifier })
        }
        scored.sort(function(a,b){ return b.s - a.s })
        scored.length = Math.min(hardK, scored.length)

        if (scored.length === 0) {
            var fb2 = firstEmptyFallback()
            if (fb2) { commitHardMove(fb2); return }
            aiThinking = false
            return
        }

        hardRoot = scored          // store {m,s}
        hardEvaluated = []
        hardIndex = 0
        hardBestMove = scored[0].m
        hardBestVal = -1e18

        hardThinkTimer.start()
    }

    function hardThinkStep() {
        if (!aiThinking) { hardThinkTimer.stop(); return }

        if (!hardRoot || hardIndex >= hardRoot.length) {
            hardThinkTimer.stop()

            if (hardEvaluated.length > 0) {
                if (settings.aiDifficulty === "Unbeatable") {
                    hardBestMove = chooseVariedMove(hardEvaluated, 3, 0.0001, 1500)
                } else {
                    hardBestMove = chooseVariedMove(hardEvaluated, 4, 0.015, 5000)
                }
            }

            if (!isValidMoveObj(hardBestMove))
                hardBestMove = firstEmptyFallback()

            if (hardBestMove) commitHardMove(hardBestMove)
            else aiThinking = false
            return
        }

        var ai = settings.aiSymbol
        var pl = settings.playerSymbol

        var item = hardRoot[hardIndex++]
        if (!item || !item.m) return
        var m2 = item.m

        // 2-ply bounded evaluation for this root move
        board[m2.r][m2.c] = ai

        var val
        var tNow = moveThreats(m2.r, m2.c, ai)
        if (tNow && tNow.win) {
            val = 1e15
        } else {
            var oppBest = bestOpponentReplyScore(ai, pl, hardOppLimit)
            val = item.s - 0.95 * oppBest

            // bounded fork penalty
            if (opponentHasForkAfterBounded(m2.r, m2.c, hardOppLimit))
                val -= 5e10
        }
        // tiny modifier to break near-ties
        if (Math.abs(val - hardBestVal) < 2000)
            val += (randomUnit() - 0.5) * aiRandomness

        // If this root move is forcing, look one more ply deeper (AI -> Opp -> AI forcing response)
        // This is cheap because it only considers forcing AI replies.
        if (isForcingMoveForAI(m2.r, m2.c) && val < 1e15) {
            // simulate opponent best reply already implicitly in oppBest, now see if AI has a forcing follow-up
            // after opponent's strongest tactical reply.
            // approximate: check if AI has an immediate forcing move on the resulting position.

            // Build a small AI forcing candidate list and take best forcing score
            var aiFollow = generateCandidates(2, 40, ai)
            var bestFollow = -1e18
            for (var f = 0; f < aiFollow.length; f++) {
                var fm = aiFollow[f]
                if (!fm) continue
                if (board[fm.r][fm.c] !== null) continue
                var tt = moveThreats(fm.r, fm.c, ai)
                if (tt && (tt.win || tt.openFour > 0 || tt.openThree >= 2)) {
                    var fs = tacticalScoreMove(fm.r, fm.c, ai, pl)
                    if (fs > bestFollow) bestFollow = fs
                }
            }
            if (bestFollow > -1e18) {
                // boost value if we have a strong forcing continuation
                val += 0.25 * bestFollow
            }
        }

        var rootRank = hardIndex - 1
        if (settings.aiDifficulty === "Unbeatable" && rootRank < unbeatableProofTopN) {

            // After placing AI move, it's player’s turn now.
            var budget = { n: unbeatableNodeBudget }
            var forcedWin = proveForcedWinFromOppTurn(ai, pl, unbeatableDepth, budget)
            if (forcedWin) {
                val = 1e16
            } else {
                // Opponent forced win check is correct to start from opponent-to-move position:
                var budget2 = { n: unbeatableNodeBudget }
                var oppForced = proveForcedWin(pl, ai, unbeatableDepth - 1, budget2)
                if (oppForced) val -= 1e15
            }
        }

        board[m2.r][m2.c] = null

        hardEvaluated = hardEvaluated.concat([{ m: m2, s: val }])

        if (val > hardBestVal) {
            hardBestVal = val
            hardBestMove = m2
        }
    }

    function startUnbeatableAI() {
        // single-owner: don't overlap
        if (aiThinking) return
        if (gameOver) return
        if (!settings || settings.gameMode !== "Player vs AI") return
        if (currentPlayer !== settings.aiSymbol) return

        // Cancel pending timers (safety)
        hardThinkTimer.stop()
        hardApplyDelayTimer.stop()
        pendingAiMove = null

        // Use Unbeatable tuning
        hardK = unbeatableK
        hardOppLimit = 18
        hardCandLimit = 90

        hardThinkStartMs = Date.now()
        aiThinking = true

        var ai = settings.aiSymbol
        var pl = settings.playerSymbol

        // Must-win / must-block (fast, deterministic)
        var winNow = findImmediateWinMove(ai)
        if (winNow) { commitHardMove(winNow); return }

        var blockNow = findImmediateWinMove(pl)
        if (blockNow) { commitHardMove(blockNow); return }

        // Candidate list (near-stone, wider than Hard)
        var cand = generateCandidates(2, hardCandLimit, ai)
        if (!cand || cand.length === 0) {
            var fb = firstEmptyFallback()
            if (fb) commitHardMove(fb)
            else aiThinking = false
            return
        }

        // Score root moves using PROFIT MATRIX (strong positional baseline)
        // We build a score per candidate by calling profitBestMove-style matrix once.
        // Simple way: approximate by tacticalScoreMove + tiny jitter,
        // but better: use the profit matrix score at each (r,c).
        //
        // We'll compute profit matrix scores in-place:
        var pm = profitMatrixScores(ai, pl, profitSelfHard, profitOppHard)

        var scored = []
        for (var i = 0; i < cand.length; i++) {
            var m = cand[i]
            if (!m) continue
            var base = pm[m.r][m.c]
            var jitter = (randomUnit() - 0.5) * aiRandomness
            scored.push({ m: m, s: base + jitter })
        }

        scored.sort(function(a,b){ return b.s - a.s })
        scored.length = Math.min(hardK, scored.length)

        if (scored.length === 0) {
            var fb2 = firstEmptyFallback()
            if (fb2) commitHardMove(fb2)
            else aiThinking = false
            return
        }

        hardRoot = scored
        hardEvaluated = []
        hardIndex = 0
        hardBestMove = scored[0].m
        hardBestVal = -1e18

        hardThinkTimer.start()
    }

    function inBounds(r, c) {
        return r >= 0 && r < boardSize && c >= 0 && c < boardSize
    }

    function hasNeighbor(r, c, dist) {
        for (var dr = -dist; dr <= dist; dr++) {
            for (var dc = -dist; dc <= dist; dc++) {
                if (dr === 0 && dc === 0) continue
                var rr = r + dr, cc = c + dc
                if (inBounds(rr, cc) && board[rr][cc] !== null) return true
            }
        }
        return false
    }

    function generateCandidates(dist, limit, forPlayer) {
        var moves = []
        var anyStone = false
        for (var r = 0; r < boardSize; r++) {
            for (var c = 0; c < boardSize; c++) {
                if (board[r][c] !== null) { anyStone = true; break }
            }
            if (anyStone) break
        }

        // opening: play center
        if (!anyStone) {
            var mid = Math.floor(boardSize / 2)
            var opening = []
            for (var dr = -1; dr <= 1; dr++) {
                for (var dc = -1; dc <= 1; dc++) {
                    if (inBounds(mid + dr, mid + dc))
                        opening.push({ r: mid + dr, c: mid + dc })
                }
            }
            return opening
        }

        for (var r2 = 0; r2 < boardSize; r2++) {
            for (var c2 = 0; c2 < boardSize; c2++) {
                if (board[r2][c2] !== null) continue
                if (!hasNeighbor(r2, c2, dist)) continue
                moves.push({ r: r2, c: c2 })
            }
        }

        var sym = forPlayer ? forPlayer : (settings ? settings.aiSymbol : "O")
        moves.sort(function(a, b) {
            return scoreCell(b.r, b.c, sym) - scoreCell(a.r, a.c, sym)
        })

        if (limit && moves.length > limit) moves.length = limit
        return moves
    }

    function lineInfo(r, c, sym, dx, dy) {
        // assumes (r,c) is empty; evaluates as if sym is placed there
        var f = 0, x = r + dx, y = c + dy
        while (inBounds(x, y) && board[x][y] === sym) { f++; x += dx; y += dy }
        var fOpen = (inBounds(x, y) && board[x][y] === null) ? 1 : 0

        var b = 0; x = r - dx; y = c - dy
        while (inBounds(x, y) && board[x][y] === sym) { b++; x -= dx; y -= dy }
        var bOpen = (inBounds(x, y) && board[x][y] === null) ? 1 : 0

        return { len: f + b + 1, open: fOpen + bOpen }
    }

    function moveThreats(r, c, sym) {
        // Callers evaluate both empty candidates and a just-placed trial stone.
        if (board[r][c] !== null && board[r][c] !== sym) return null
        var dirs = [[1,0],[0,1],[1,1],[1,-1]]

        var win = false
        var openFour = 0
        var closedFour = 0
        var openThree = 0
        var closedThree = 0

        for (var i = 0; i < dirs.length; i++) {
            var dx = dirs[i][0], dy = dirs[i][1]
            var li = lineInfo(r, c, sym, dx, dy)
            if (typeof activeWinRule !== "undefined" && activeWinRule === "ExactFive"
                    ? li.len === 5 : li.len >= 5) win = true
            else if (li.len === 4 && li.open === 2) openFour++
            else if (li.len === 4 && li.open === 1) closedFour++
            else if (li.len === 3 && li.open === 2) openThree++
            else if (li.len === 3 && li.open === 1) closedThree++
        }

        return {
            win: win,
            openFour: openFour,
            closedFour: closedFour,
            openThree: openThree,
            closedThree: closedThree
        }
    }

    function isForcingMoveForAI(r, c) {
        var t = moveThreats(r, c, settings.aiSymbol)
        return t && (t.win || t.openFour > 0 || t.openThree >= 2)
    }

    function tacticalScoreMove(r, c, ai, pl) {
        // Returns a big score where larger is better for AI.
        // Fast, threat-based, no search.
        if (board[r][c] !== null) return -1e18

        var tAI = moveThreats(r, c, ai)
        var tPL = moveThreats(r, c, pl)

        // 1) immediate win / block immediate loss
        if (tAI.win) return 1e15
        if (tPL.win) return 1e14

        // 2) open-four creation and block
        if (tAI.openFour > 0) return 1e13
        if (tPL.openFour > 0) return 1e12

        // 3) forks (double open-three) and block forks
        if (tAI.openThree >= 2) return 1e11
        if (tPL.openThree >= 2) return 1e10

        // 4) other strong threats
        var s = 0
        s += tAI.openThree * 5e8
        s += tAI.closedFour * 2e8
        s += tAI.closedThree * 5e6

        // defend
        s += tPL.openThree * 2e8
        s += tPL.closedFour * 1e8
        s += tPL.closedThree * 2e6

        // mild center bias
        var cd = Math.abs(r - (boardSize-1)/2) + Math.abs(c - (boardSize-1)/2)
        s += (boardSize - cd) * 1000

        return s
    }

    function createEmptyBoard(size) {
        var result = []
        for (var r = 0; r < size; r++) {
            result[r] = []
            for (var c = 0; c < size; c++) result[r][c] = null
        }
        return result
    }

    function moveCount() {
        var count = 0
        for (var r = 0; r < boardSize; r++)
            for (var c = 0; c < boardSize; c++)
                if (board[r][c] !== null) count++
        return count
    }

    function boardIsFull() {
        return moveCount() === boardSize * boardSize
    }

    function normalizeBoardSize(value) {
        value = Number(value)
        return value === 9 || value === 13 || value === 15 ? value : 15
    }

    function normalizeWinRule(value) {
        return value === "ExactFive" ? "ExactFive" : "Freestyle"
    }

    function cloneBoard(src) {
        var out = []
        for (var r = 0; r < src.length; r++) {
            var row = []
            for (var c = 0; c < src[r].length; c++) row.push(src[r][c])
            out.push(row)
        }
        return out
    }

    function saveGameState() {
        if (!settings) return
        if (gameOver || moveCount() === 0) {
            settings.savedGameJson = ""
            return
        }
        settings.savedGameJson = JSON.stringify({
            version: 1,
            board: cloneBoard(board),
            boardSize: boardSize,
            currentPlayer: currentPlayer,
            lastMoveR: lastMoveR,
            lastMoveC: lastMoveC,
            elapsedMs: elapsedMs,
            timerStarted: timerStartedThisGame,
            gameMode: settings.gameMode,
            aiDifficulty: settings.aiDifficulty,
            playerSymbol: settings.playerSymbol,
            aiSymbol: settings.aiSymbol,
            startingPlayer: settings.startingPlayer,
            player1Name: settings.player1Name,
            player2Name: settings.player2Name,
            winRule: activeWinRule
        })
    }

    function restoreSavedGame() {
        if (!settings || !settings.savedGameJson) return false
        try {
            var state = JSON.parse(settings.savedGameJson)
            var size = normalizeBoardSize(state.boardSize)
            if (!state || state.version !== 1 || !Array.isArray(state.board) ||
                    state.board.length !== size) throw "invalid board"
            for (var r = 0; r < size; r++) {
                if (!Array.isArray(state.board[r]) || state.board[r].length !== size)
                    throw "invalid row"
                for (var c = 0; c < size; c++) {
                    var value = state.board[r][c]
                    if (value !== null && value !== "X" && value !== "O")
                        throw "invalid cell"
                }
            }
            if (state.currentPlayer !== "X" && state.currentPlayer !== "O")
                throw "invalid player"

            settings.gameMode = state.gameMode === "Player1 vs Player2"
                                ? "Player1 vs Player2" : "Player vs AI"
            var savedDifficulty = state.aiDifficulty === "Unbeatable"
                                ? "Expert" : state.aiDifficulty
            settings.aiDifficulty = ["Easy", "Medium", "Hard", "Expert"]
                                    .indexOf(savedDifficulty) >= 0
                                  ? savedDifficulty : "Medium"
            settings.playerSymbol = state.playerSymbol === "O" ? "O" : "X"
            settings.aiSymbol = settings.playerSymbol === "X" ? "O" : "X"
            settings.startingPlayer = state.startingPlayer === "O" ? "O" : "X"
            settings.player1Name = state.player1Name || qsTr("Player 1")
            settings.player2Name = state.player2Name || qsTr("Player 2")
            settings.boardSize = size
            settings.winRule = normalizeWinRule(state.winRule)

            boardSize = size
            activeWinRule = settings.winRule
            board = cloneBoard(state.board)
            currentPlayer = state.currentPlayer
            lastMoveR = Number(state.lastMoveR)
            lastMoveC = Number(state.lastMoveC)
            if (isNaN(lastMoveR)) lastMoveR = -1
            if (isNaN(lastMoveC)) lastMoveC = -1
            elapsedMs = Math.max(0, Number(state.elapsedMs) || 0)
            timerStartedThisGame = !!state.timerStarted
            if (timerStartedThisGame && settings.gameMode === "Player vs AI") {
                gameStartMs = Date.now() - elapsedMs
                gameTimerRunning = true
            }
            gameOver = false
            gameDraw = false
            winningCells = []
            undoStack = []
            redoStack = []
            return moveCount() > 0
        } catch (e) {
            console.warn("Could not restore saved game:", e)
            settings.savedGameJson = ""
            return false
        }
    }

    function loadStatistics() {
        var stats
        try { stats = JSON.parse(settings ? settings.statisticsJson : "{}") }
        catch (e) { stats = ({}) }
        if (!stats || typeof stats !== "object") stats = ({})
        stats.games = Number(stats.games) || 0
        stats.wins = Number(stats.wins) || 0
        stats.losses = Number(stats.losses) || 0
        stats.draws = Number(stats.draws) || 0
        stats.currentStreak = Number(stats.currentStreak) || 0
        stats.bestStreak = Number(stats.bestStreak) || 0
        stats.byDifficulty = stats.byDifficulty || ({})
        return stats
    }

    function recordResult(result) {
        if (!settings || settings.gameMode !== "Player vs AI") return
        var stats = loadStatistics()
        stats.games++
        if (result === "win") {
            stats.wins++
            stats.currentStreak++
            stats.bestStreak = Math.max(stats.bestStreak, stats.currentStreak)
        } else if (result === "loss") {
            stats.losses++
            stats.currentStreak = 0
        } else {
            stats.draws++
            stats.currentStreak = 0
        }
        var key = settings.aiDifficulty === "Unbeatable" ? "Expert" : settings.aiDifficulty
        var bucket = stats.byDifficulty[key] || { games: 0, wins: 0, losses: 0, draws: 0 }
        bucket.games = (Number(bucket.games) || 0) + 1
        bucket.wins = (Number(bucket.wins) || 0) + (result === "win" ? 1 : 0)
        bucket.losses = (Number(bucket.losses) || 0) + (result === "loss" ? 1 : 0)
        bucket.draws = (Number(bucket.draws) || 0) + (result === "draw" ? 1 : 0)
        stats.byDifficulty[key] = bucket
        settings.statisticsJson = JSON.stringify(stats)
    }

    function requestNewGame() {
        if (!gameOver && moveCount() > 0) {
            newGameRemorse.execute(qsTr("Starting a new game"), function() {
                restartGame()
            })
        } else {
            restartGame()
        }
    }

    function restartGame() {
        activeAiRequest = ++aiRequestSerial
        hardThinkTimer.stop()
        hardApplyDelayTimer.stop()
        aiTimer.stop()
        pendingAiMove = null
        aiThinking = false
        reseedAI()

        boardSize = settings ? normalizeBoardSize(settings.boardSize) : 15
        activeWinRule = settings ? normalizeWinRule(settings.winRule) : "Freestyle"
        board = createEmptyBoard(boardSize)

        currentPlayer = settings ? settings.startingPlayer : "X"
        gameOver = false
        gameDraw = false
        winningCells = []
        undoStack = []
        redoStack = []
        board = board
        lastMoveR = -1
        lastMoveC = -1
        timerStartedThisGame = false
        gameTimerRunning = false
        elapsedMs = 0
        if (settings) settings.savedGameJson = ""

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
        stopGameTimer()

        // Record time only for PvAI human wins
        if (settings && settings.gameMode === "Player vs AI") {
            var humanSym = settings.playerSymbol
            if (player === humanSym) {
                recordBestTime(elapsedMs)
                recordResult("win")
            } else {
                recordResult("loss")
            }
        }
        if (settings) settings.savedGameJson = ""
        lastMoveR = -1;
        lastMoveC = -1
        publishBoardToCover()
    }

    function declareDraw() {
        gameDraw = true
        gameOver = true
        winningCells = []
        stopGameTimer()
        recordResult("draw")
        if (settings) settings.savedGameJson = ""
        lastMoveR = -1
        lastMoveC = -1
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
            var wins = activeWinRule === "ExactFive"
                       ? len === 5 : len >= 5
            if (wins) {
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
                   ? settings.player1Name : qsTr("AI")
        } else {
            // Player1 vs Player2: X = Player1, O = Player2
            if (symbol === "X")
                return settings.player1Name
            else
                return settings.player2Name
        }
    }

    function nameForSymbol(sym) {
        if (!settings) return sym

        // PvAI: human = player1Name, AI = "AI" (or a setting later)
        if (settings.gameMode === "Player vs AI") {
            if (sym === settings.playerSymbol) return settings.player1Name
            if (sym === settings.aiSymbol)     return qsTr("AI")
            return sym
        }

        // PvP: use both names
        if (sym === "X") return settings.player1Name
        if (sym === "O") return settings.player2Name
        return sym
    }

    function currentPlayerName() {
        return nameForSymbol(currentPlayer)
    }

    function applyMove(r, c) {
        if (gameOver) return
        if (!inBounds(r, c)) return
        if (board[r][c] !== null) return

        // Save undo snapshot
        undoStack = undoStack.concat([{
            board: cloneBoard(board),
            player: currentPlayer,
            lastR: lastMoveR,
            lastC: lastMoveC
        }])
        redoStack = []

        if (!timerStartedThisGame && settings && settings.gameMode === "Player vs AI") {
            timerStartedThisGame = true
            resetGameTimer()
            gameTimerRunning = true
        }

        // Place
        board[r][c] = currentPlayer
        board = board
        playHapticFeedback()
        publishBoardToCover()

        // Win?
        var cells = checkWin(r, c)
        if (cells) {
            declareWinner(currentPlayer, cells)
            return
        }

        if (boardIsFull()) {
            declareDraw()
            return
        }

        // Next turn
        currentPlayer = (currentPlayer === "X") ? "O" : "X"

        // If AI should play next, schedule it (not immediate, to keep UI responsive)
        if (settings && settings.gameMode === "Player vs AI" && currentPlayer === settings.aiSymbol) {
            aiTimer.start()
        }
        lastMoveR = r
        lastMoveC = c
        saveGameState()
    }

    function findImmediateWinMove(forSym) {
        // Use near-stone candidates, sorted for the symbol we're testing.
        // Use a generous limit so we don't miss a critical block square.
        var cand = generateCandidates(2, 120, forSym)
        if (!cand || cand.length === 0) return null

        var wins = []
        for (var i = 0; i < cand.length; i++) {
            var m = cand[i]
            if (!m) continue
            var t = moveThreats(m.r, m.c, forSym)
            if (t && t.win) wins.push({ r: m.r, c: m.c })
        }
        return wins.length > 0 ? wins[randInt(wins.length)] : null
    }

    // -------------------------------
    // Helpers for EASY (depth-3 minimax)
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


    // -------------------------------
    // Helpers for HARD
    // -------------------------------
    function scoreCell(r, c, player) {
        if (board[r][c] !== null) return -1e9

        var score = 0
        var dirs = [[1,0],[0,1],[1,1],[1,-1]]

        // small center bias (helps openings)
        var cd = Math.abs(r - (boardSize-1)/2) + Math.abs(c - (boardSize-1)/2)
        score += (boardSize - cd) * 0.2

        for (var d = 0; d < dirs.length; d++) {
            var dx = dirs[d][0], dy = dirs[d][1]

            // count contiguous stones forward/backward
            var f = 0, x = r + dx, y = c + dy
            while (inBounds(x,y) && board[x][y] === player) { f++; x += dx; y += dy }
            var fOpen = (inBounds(x,y) && board[x][y] === null) ? 1 : 0

            var b = 0; x = r - dx; y = c - dy
            while (inBounds(x,y) && board[x][y] === player) { b++; x -= dx; y -= dy }
            var bOpen = (inBounds(x,y) && board[x][y] === null) ? 1 : 0

            var len = f + b + 1
            var openEnds = fOpen + bOpen

            // Winning move
            if (activeWinRule === "ExactFive"
                    ? len === 5 : len >= 5) return 1e9

            // Threat weights (tuned for Gomoku-like play)
            if (len === 4) {
                if (openEnds === 2) score += 1e7     // open four
                else if (openEnds === 1) score += 1e6 // closed four
            } else if (len === 3) {
                if (openEnds === 2) score += 1e5     // open three
                else if (openEnds === 1) score += 1e4
            } else if (len === 2) {
                if (openEnds === 2) score += 1e3
                else if (openEnds === 1) score += 200
            } else if (len === 1) {
                score += 10
            }
        }

        return score
    }

    function opponentHasForkAfterBounded(aiMoveR, aiMoveC, oppLimit) {
        var ai = settings.aiSymbol
        var pl = settings.playerSymbol

        var previous = board[aiMoveR][aiMoveC]
        board[aiMoveR][aiMoveC] = ai

        var cand = generateCandidates(2, oppLimit || 14, pl)
        var forkExists = false
        for (var i = 0; i < cand.length; i++) {
            var m = cand[i]
            if (!m) continue
            var t = moveThreats(m.r, m.c, pl)
            if (t && (t.win || t.openFour > 0 || t.openThree >= 2)) { forkExists = true; break }
        }

        board[aiMoveR][aiMoveC] = previous
        return forkExists
    }

    function bestOpponentReplyScore(ai, pl, oppLimit) {
        var opp = generateCandidates(2, oppLimit || 14, pl)
        if (!opp || opp.length === 0) return 0

        var best = -1e18
        for (var i = 0; i < opp.length; i++) {
            var m = opp[i]
            if (!m) continue
            var s = tacticalScoreMove(m.r, m.c, pl, ai) // opponent perspective
            if (s > best) best = s
        }
        return best
    }

    function firstEmptyFallback() {
        for (var r = 0; r < boardSize; r++) {
            for (var c = 0; c < boardSize; c++) {
                if (board[r][c] === null)
                    return { r: r, c: c }
            }
        }
        return null
    }

    function isValidMoveObj(m) {
        return m && m.r !== undefined && m.c !== undefined
    }

    // -------------------------------
    // Helpers for Live preview on Cover page
    // -------------------------------
    function publishBoardToCover() {
        var copy = []
        for (var r = 0; r < boardSize; r++)
            copy[r] = board[r].slice(0)

        var wt = gameOver && !gameDraw ? getWinnerName(currentPlayer) : ""
        coverSnapshot(copy, boardSize, gameOver, gameDraw, wt, winningCells)
    }

    // -------------------------------
    // selectAIMove() - dynamic symbols (AI = settings.aiSymbol)
    // -------------------------------
    function selectAIMove() {
        var ai = settings.aiSymbol
        var pl = settings.playerSymbol

        var candMed  = generateCandidates(2, 24, ai)
        // fallback if somehow empty
        if (!candMed || candMed.length === 0) return firstEmptyFallback()

        // --- EASY ---
        if (settings.aiDifficulty === "Easy") {
            // Easy always takes a win, but occasionally misses a forced block.
            var winNowM = findImmediateWinMove(ai)
            if (winNowM) return winNowM
            var blockNowM = findImmediateWinMove(pl)
            if (blockNowM && randomUnit() < 0.8) return blockNowM

            // 2) candidates
            var cand = candMed
            if (!cand || cand.length === 0) return firstEmptyFallback()

            // 3) base scoring
            var scored = []
            for (var i = 0; i < cand.length; i++) {
                var m = cand[i]
                if (!m) continue
                scored.push({ m: m, s: tacticalScoreMove(m.r, m.c, ai, pl) })
            }
            if (scored.length === 0) return firstEmptyFallback()
            scored.sort(function(a,b){ return b.s - a.s })

            if (blockNowM) {
                var withoutForcedBlock = []
                for (var e = 0; e < scored.length; e++) {
                    if (scored[e].m.r !== blockNowM.r || scored[e].m.c !== blockNowM.c)
                        withoutForcedBlock.push(scored[e])
                }
                if (withoutForcedBlock.length > 0) scored = withoutForcedBlock
            }
            return chooseVariedMove(scored, 8, 0.40, 12000)
        }

        // --- MEDIUM ---
        if (settings.aiDifficulty === "Medium") {
            // must-win / must-block
            var winNow = findImmediateWinMove(ai)
            if (winNow) return winNow
            var blockNow = findImmediateWinMove(pl)
            if (blockNow) return blockNow

            // Primary move: profit matrix (fast, strong positional play)
            var m = profitBestMove(ai, pl, profitSelfMedium, profitOppMedium,
                                   5, 0.05, 120)
            if (!m) return firstEmptyFallback()

            // Cheap blunder check: if this move allows an immediate opponent win, pick next best.
            // We only do this when needed, and it’s bounded so it stays fast.
            board[m.r][m.c] = ai
            var losing = false
            var oppCand = generateCandidates(2, 40, pl)  //make more responsive change 40 -> 24
            for (var j = 0; j < oppCand.length; j++) {
                var o = oppCand[j]
                if (!o) continue
                var tOpp = moveThreats(o.r, o.c, pl)
                if (tOpp && tOpp.win) { losing = true; break }
            }
            board[m.r][m.c] = null

            if (!losing) return m

            // If it was a blunder, fall back to the HARD weights profit move (still fast)
            var m2 = profitBestMove(ai, pl, profitSelfHard, profitOppHard,
                                    2, 0.01, 20)
            return m2 ? m2 : firstEmptyFallback()
        }

        // --- HARD ---
        if (settings.aiDifficulty === "Hard") {
            // must win / must block
            var winNowH = findImmediateWinMove(ai)
            if (winNowH) return winNowH
            var blockNowH = findImmediateWinMove(pl)
            if (blockNowH) return blockNowH

            // Native C++ is the normal path; this is only the fallback move.
            return profitBestMove(ai, pl, profitSelfHard, profitOppHard,
                                  2, 0.01, 20)
        }

        // --- EXPERT ---
        // Native C++ is the normal path; retain a legal fallback.

        // fallback generic
        var fb = firstEmptyFallback()
        return fb
    }

    Timer {
        id: aiTimer
        interval: settings ? settings.aiThinkDelayMs : 300
        repeat: false
        onTriggered: {
            if (gameOver) return
            if (!settings || settings.gameMode !== "Player vs AI") return
            if (currentPlayer !== settings.aiSymbol) return

            hardThinkStartMs = Date.now()
            aiThinking = true
            activeAiRequest = ++aiRequestSerial
            var seed = Math.floor(randomUnit() * 4294967295)
            nativeAI.requestMove(board, boardSize, settings.aiSymbol,
                                 settings.playerSymbol, settings.aiDifficulty,
                                 activeWinRule, seed, activeAiRequest)
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

        contentWidth: coordinateMargin + boardSize * dynamicCellSize
        contentHeight: boardArea.y + boardArea.height + Theme.itemSizeLarge * 2

        PullDownMenu {
            MenuItem { text: qsTr("New Game"); onClicked: requestNewGame() }
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
                radius: (Theme.roundingSmall !== undefined ? Theme.roundingSmall : 6)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.paddingMedium
                spacing: Theme.paddingSmall

                // Row 1: Game Mode (left) + Timer (right)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: (Theme.paddingSmall !== undefined ? Theme.paddingSmall : 6)

                    Text {
                        text: qsTr("Mode:")
                        font.pixelSize: Theme.fontSizeMedium
                        color: "white"
                    }

                    Text {
                        text: settings ? gameModeLabel(settings.gameMode) : ""
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        color: "white"
                    }

                    // spacer pushes timer to the right
                    Item { Layout.fillWidth: true }

                    Text {
                        visible: settings && settings.gameMode === "Player vs AI"
                        text: qsTr("Time: %1").arg(formatMs(elapsedMs))
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: false
                        color: "white"
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Row 2: Turn indicator
                RowLayout {
                    Layout.fillWidth: true
                    spacing: (Theme.paddingSmall !== undefined ? Theme.paddingSmall : 6)

                    Text {
                        text: qsTr("Turn:")
                        font.pixelSize: Theme.fontSizeMedium
                        color: "white"
                    }

                    Text {
                        id: turnValueText
                        text: {
                            if (settings.gameMode === "Player vs AI")
                                return currentPlayer === settings.playerSymbol
                                        ? currentPlayerName()
                                        : (aiThinking ? qsTr("AI is thinking…") : qsTr("AI"))
                            else
                                return currentPlayer === "X" ? settings.player1Name : settings.player2Name
                        }
                        font.bold: true
                        font.pixelSize: Theme.fontSizeMedium
                        color: "white"
                    }

                    Item { Layout.fillWidth: true }

                    IconButton {
                        Layout.preferredWidth: Theme.itemSizeSmall
                        Layout.preferredHeight: Theme.itemSizeSmall
                        icon.source: "image://theme/icon-m-back"
                        enabled: !page.aiBusy && !gameOver && undoStack.length > 0
                        opacity: enabled ? 1.0 : 0.35
                        onClicked: undoMove()
                    }

                    IconButton {
                        Layout.preferredWidth: Theme.itemSizeSmall
                        Layout.preferredHeight: Theme.itemSizeSmall
                        icon.source: "image://theme/icon-m-forward"
                        enabled: !page.aiBusy && !gameOver && redoStack.length > 0
                        opacity: enabled ? 1.0 : 0.35
                        onClicked: redoMove()
                    }
                }
            }
        }

        Item {
            id: columnCoordinates
            visible: settings && settings.showCoordinates
            anchors.top: unifiedTopBar.bottom
            anchors.topMargin: Theme.paddingMedium
            x: coordinateMargin
            width: boardSize * dynamicCellSize
            height: coordinateMargin

            Repeater {
                model: boardSize
                Label {
                    x: index * dynamicCellSize
                    width: dynamicCellSize
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Math.min(Theme.fontSizeExtraSmall,
                                             dynamicCellSize * 0.35)
                    color: Theme.secondaryColor
                    text: String.fromCharCode(65 + index)
                }
            }
        }

        Item {
            id: rowCoordinates
            visible: settings && settings.showCoordinates
            anchors.top: boardArea.top
            x: 0
            width: coordinateMargin
            height: boardSize * dynamicCellSize

            Repeater {
                model: boardSize
                Label {
                    y: index * dynamicCellSize
                    width: coordinateMargin
                    height: dynamicCellSize
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Math.min(Theme.fontSizeExtraSmall,
                                             dynamicCellSize * 0.35)
                    color: Theme.secondaryColor
                    text: index + 1
                }
            }
        }

        // -------------------------------
        // Board Area
        // -------------------------------
        Item {
            id: boardArea
            anchors.top: columnCoordinates.visible ? columnCoordinates.bottom
                                                   : unifiedTopBar.bottom
            anchors.topMargin: Theme.paddingMedium
            x: coordinateMargin
            width: boardSize * dynamicCellSize
            height: boardSize * dynamicCellSize

            Repeater {
                model: boardSize * boardSize

                Rectangle {
                    width: dynamicCellSize
                    height: dynamicCellSize
                    x: (index % boardSize) * dynamicCellSize
                    y: Math.floor(index / boardSize) * dynamicCellSize
                    border.color: "black"
                    property int r: Math.floor(index / boardSize)
                    property int c: index % boardSize

                    color: {
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

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: (r === lastMoveR && c === lastMoveC) ? 4 : 0
                        border.color: "gold"
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !page.aiBusy && (!settings ||
                                 settings.gameMode !== "Player vs AI" ||
                                 currentPlayer === settings.playerSymbol)
                        onClicked: {
                            if (gameOver) return
                            var r = Math.floor(index / boardSize)
                            var c = index % boardSize
                            if (!board[r][c])
                                applyMove(r, c)
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
                    text: settings ? difficultyLabel(settings.aiDifficulty) : ""
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
                if (gameDraw)
                    return "<b><font color='gold'>" + qsTr("Draw") + "</font></b>"
                return "<b><font color='gold'>" + qsTr("Game Over!") + "</font></b><br>" +
                       "<font color='white'>" + qsTr("Winner: ") + "</font>" +
                       "<b><font color='gold'>" + currentPlayerName() + "</font></b>"
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
        if (!settings) return
        activeAiRequest = ++aiRequestSerial
        aiTimer.stop()
        hardThinkTimer.stop()
        hardApplyDelayTimer.stop()
        pendingAiMove = null
        aiThinking = false

        if (settings.gameMode === "Player vs AI") {
            // Undo up to two plies, but only if possible.
            // This returns you to your turn in the common case.
            var ok1 = undoOnce()
            var ok2 = undoOnce()
            // If only one move existed, ok2 will be false and that’s fine.
            return (ok1 || ok2)
        } else {
            return undoOnce()
        }
    }

    function redoMove() {
        if (!settings) return
        activeAiRequest = ++aiRequestSerial
        aiTimer.stop()
        hardThinkTimer.stop()
        hardApplyDelayTimer.stop()
        pendingAiMove = null
        aiThinking = false

        if (settings.gameMode === "Player vs AI") {
            var ok1 = redoOnce()
            var ok2 = redoOnce()
            return (ok1 || ok2)
        } else {
            return redoOnce()
        }
    }

    function undoOnce() {
        if (undoStack.length === 0) return false

        var last = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, undoStack.length - 1)
        redoStack = redoStack.concat([{
            board: cloneBoard(board),
            player: currentPlayer,
            lastR: lastMoveR,
            lastC: lastMoveC
        }])

        board = last.board.map(function(r) {
            var a = []
            for (var i = 0; i < r.length; i++) a.push(r[i])
            return a
        })
        currentPlayer = last.player
        lastMoveR = (last.lastR !== undefined) ? last.lastR : -1
        lastMoveC = (last.lastC !== undefined) ? last.lastC : -1
        winningCells = []
        gameOver = false
        gameDraw = false
        publishBoardToCover()
        saveGameState()
        return true
    }

    function redoOnce() {
        if (redoStack.length === 0) return false

        var next = redoStack[redoStack.length - 1]
        redoStack = redoStack.slice(0, redoStack.length - 1)
        undoStack = undoStack.concat([{
            board: cloneBoard(board),
            player: currentPlayer,
            lastR: lastMoveR,
            lastC: lastMoveC
        }])

        board = next.board.map(function(r) {
            var a = []
            for (var i = 0; i < r.length; i++) a.push(r[i])
            return a
        })
        currentPlayer = next.player
        lastMoveR = (next.lastR !== undefined) ? next.lastR : -1
        lastMoveC = (next.lastC !== undefined) ? next.lastC : -1
        winningCells = []
        gameOver = false
        gameDraw = false
        publishBoardToCover()
        saveGameState()
        return true
    }

    // Make sure we pick up startingPlayer once settings is actually set
    Component.onCompleted: {
        reseedAI()
        // Reading supported once initializes the QtFeedback backend before
        // the first move, matching Sailfish Silica's own feedback handling.
        try {
            if (!placementHaptic.supported)
                console.warn("Haptic feedback is unavailable on this device")
        } catch (error) {
            console.warn("Could not initialize haptic feedback:", error)
        }
        var restored = false
        if (settings) {
            if (settings.aiDifficulty === "Unbeatable")
                settings.aiDifficulty = "Expert"
            settings.boardSize = normalizeBoardSize(settings.boardSize)
            settings.winRule = normalizeWinRule(settings.winRule)
            if (settings.boardZoomPercent !== 100 &&
                    settings.boardZoomPercent !== 125 &&
                    settings.boardZoomPercent !== 150)
                settings.boardZoomPercent = 100
            restored = restoreSavedGame()
            if (!restored) {
                boardSize = settings.boardSize
                activeWinRule = settings.winRule
                board = createEmptyBoard(boardSize)
                currentPlayer = settings.startingPlayer
            }
        } else {
            currentPlayer = "X"
        }
        initializationComplete = true
        publishBoardToCover()
        if (settings && settings.gameMode === "Player vs AI" &&
                currentPlayer === settings.aiSymbol) {
            aiTimer.start()
        }
    }

    Component.onDestruction: saveGameState()
}

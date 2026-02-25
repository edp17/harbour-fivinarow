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
    signal coverSnapshot(var boardMatrix, int boardSize, bool gameOver, string winnerText, var winningCells)

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

    property int lastMoveR: -1
    property int lastMoveC: -1
    property int hardMinThinkMs: (settings ? settings.aiThinkDelayMs : 250)
    property double hardThinkStartMs: 0
    property var pendingAiMove: null
    property bool aiThinking: false
    property var hardRoot: []
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
    // Unbeatable
    property int unbeatableDepth: 8          // 6 plies forcing search (try 8 if still fast)
    property int unbeatableNodeBudget: 4000  // per root eval, keeps it responsive
    property int unbeatableK: 14             // evaluate more root moves than Hard

    function randInt(n) { return Math.floor(Math.random() * n) }

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

    function profitBestMove(aiSym, oppSym, profitSelf, profitOpp) {
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

        // pick best empty (random among ties)
        var best = -1
        var bestMoves = []
        for (var rr = 0; rr < n; rr++) {
            for (var cc = 0; cc < n; cc++) {
                if (board[rr][cc] !== null) continue
                var s = pm[rr][cc]
                if (s > best) {
                    best = s
                    bestMoves = [{ r: rr, c: cc }]
                } else if (s === best) {
                    bestMoves.push({ r: rr, c: cc })
                }
            }
        }
        if (bestMoves.length === 0) return firstEmptyFallback()
        return bestMoves[Math.floor(Math.random() * bestMoves.length)]
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

    function bestTimesKeyForDifficulty() {
        var d = settings ? settings.aiDifficulty : "Easy"
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
    }

    function recordBestTime(ms) {
        if (!settings) return
        var key = bestTimesKeyForDifficulty()
        var arr = loadBestTimesArray(settings[key])

        // add entry
        arr.push({
            name: settings.player1Name,
            ms: ms,
            at: Date.now()
        })

        // sort ascending by time
        arr.sort(function(a,b){ return a.ms - b.ms })

        // keep top 6
        if (arr.length > 6) arr.length = 6

        saveBestTimesArray(key, arr)
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
//    property int cellSize: 72
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
            var modifier = (Math.random() - 0.5) * aiRandomness   // aiRandomness ~ 1..3
            scored.push({ m: m, s: base + modifier })
        }
        scored.sort(function(a,b){ return b.s - a.s })
        scored.length = Math.min(hardK, scored.length)

        // small shuffle among top 5 to reduce predictability without weakening much
        var top = Math.min(5, scored.length)
        for (var i = 0; i < top; i++) {
            var j = i + Math.floor(Math.random() * (top - i))
            var tmp = scored[i]; scored[i] = scored[j]; scored[j] = tmp
        }

        if (scored.length === 0) {
            var fb2 = firstEmptyFallback()
            if (fb2) { commitHardMove(fb2); return }
            aiThinking = false
            return
        }

        hardRoot = scored          // store {m,s}
        hardIndex = 0
        // Choose from near-best root moves to avoid deterministic openings
        var top = Math.min(5, scored.length)        // consider top 5
        var band = []

        // Define “near-best” as within X% of best score
        var bestS = scored[0].s
        var eps = Math.max(5000, Math.abs(bestS) * 0.01)  // 1% or at least 5000

        for (var i0 = 0; i0 < top; i0++) {
            if (bestS - scored[i0].s <= eps)
                band.push(scored[i0])
        }

        if (band.length === 0) band = scored.slice(0, top)
        hardBestMove = band[randInt(band.length)].m
        hardBestVal = -1e18

        hardThinkTimer.start()
    }

    function hardThinkStep() {
        if (!aiThinking) { hardThinkTimer.stop(); return }

        if (!hardRoot || hardIndex >= hardRoot.length) {
            hardThinkTimer.stop()

            if (!isValidMoveObj(hardBestMove))
                hardBestMove = firstEmptyFallback()

            // enforce minimum delay
            var elapsed = Date.now() - hardThinkStartMs
            var remaining = hardMinThinkMs - elapsed
            if (remaining > 0) {
                hardApplyDelayTimer.interval = remaining
                hardApplyDelayTimer.start()
                return
            }

            aiThinking = false
            if (hardBestMove) commitHardMove(hardBestMove)
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
            val += (Math.random() - 0.5) * aiRandomness

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
            var jitter = (Math.random() - 0.5) * aiRandomness
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
            return [{ r: mid, c: mid }]
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
        if (board[r][c] !== null) return null
        var dirs = [[1,0],[0,1],[1,1],[1,-1]]

        var win = false
        var openFour = 0
        var closedFour = 0
        var openThree = 0
        var closedThree = 0

        for (var i = 0; i < dirs.length; i++) {
            var dx = dirs[i][0], dy = dirs[i][1]
            var li = lineInfo(r, c, sym, dx, dy)
            if (li.len >= 5) win = true
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
        lastMoveR = -1
        lastMoveC = -1
        timerStartedThisGame = false
        gameTimerRunning = false
        elapsedMs = 0

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
            }
        }
        lastMoveR = -1;
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
        undoStack.push({ board: cloneBoard(board), player: currentPlayer, lastR: lastMoveR, lastC: lastMoveC })
        redoStack = []

        if (!timerStartedThisGame && settings && settings.gameMode === "Player vs AI") {
            timerStartedThisGame = true
            resetGameTimer()
            gameTimerRunning = true
        }

        // Place
        board[r][c] = currentPlayer
        board = board
        publishBoardToCover()

        // Win?
        var cells = checkWin(r, c)
        if (cells) {
            declareWinner(currentPlayer, cells)
            return
        }

        // Next turn
        currentPlayer = (currentPlayer === "X") ? "O" : "X"

        // If AI should play next, schedule it (not immediate, to keep UI responsive)
        if (settings && settings.gameMode === "Player vs AI" && currentPlayer === settings.aiSymbol) {
            if (settings.aiDifficulty === "Unbeatable") {
                startUnbeatableAI()
            } else {
                // Easy/Medium/Hard are synchronous via aiTimer -> selectAIMove()
                aiTimer.start()
            }
        }
        lastMoveR = r
        lastMoveC = c
    }

    function findImmediateWinMove(forSym) {
        // Use near-stone candidates, sorted for the symbol we're testing.
        // Use a generous limit so we don't miss a critical block square.
        var cand = generateCandidates(2, 120, forSym)
        if (!cand || cand.length === 0) return null

        for (var i = 0; i < cand.length; i++) {
            var m = cand[i]
            if (!m) continue
            var t = moveThreats(m.r, m.c, forSym)
            if (t && t.win) return { r: m.r, c: m.c }
        }
        return null
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
            if (len >= 5) return 1e9

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

        board[aiMoveR][aiMoveC] = ai

        var cand = generateCandidates(2, oppLimit || 14, pl)
        var forkExists = false
        for (var i = 0; i < cand.length; i++) {
            var m = cand[i]
            if (!m) continue
            var t = moveThreats(m.r, m.c, pl)
            if (t && (t.win || t.openFour > 0 || t.openThree >= 2)) { forkExists = true; break }
        }

        board[aiMoveR][aiMoveC] = null
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

        var wt = gameOver ? getWinnerName(currentPlayer) : ""
        coverSnapshot(copy, boardSize, gameOver, wt, winningCells)
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
            // 1) win now / block now (must)
            var winNowM = findImmediateWinMove(ai)
            if (winNowM) return winNowM
            var blockNowM = findImmediateWinMove(pl)
            if (blockNowM) return blockNowM

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

            // 4) evaluate only top K deeply
            var K = Math.min(12, scored.length)
            var bestMove = scored[0].m
            var bestVal = -1e18

            for (var k = 0; k < K; k++) {
                var m2 = scored[k].m
                if (!m2) continue

                board[m2.r][m2.c] = ai

                // immediate win after placing
                var tNow = moveThreats(m2.r, m2.c, ai)
                var val
                if (tNow && tNow.win) {
                    val = 1e15
                } else {
                    // If this move allows an immediate opponent win next, heavily penalize it.
                    // (Fast check: look for opponent immediate win in bounded candidate set.)
                    var losing = false
                    var oppCand = generateCandidates(2, 40, pl)
                    for (var j = 0; j < oppCand.length; j++) {
                        var o = oppCand[j]
                        if (!o) continue
                        var tOpp = moveThreats(o.r, o.c, pl)
                        if (tOpp && tOpp.win) { losing = true; break }
                    }

                    if (losing) {
                        val = -1e14
                    } else {
                        // opponent best reply (bounded)
                        var oppBest = bestOpponentReplyScore(ai, pl, 14)
                        val = scored[k].s - 0.95 * oppBest

                        // fork penalty (bounded)
                        if (opponentHasForkAfterBounded(m2.r, m2.c, 14))
                            val -= 5e10
                    }
                }

                board[m2.r][m2.c] = null

                if (val > bestVal) {
                    bestVal = val
                    bestMove = m2
                }
            }
            return bestMove
        }

        // --- MEDIUM ---
        if (settings.aiDifficulty === "Medium") {
            // must-win / must-block
            var winNow = findImmediateWinMove(ai)
            if (winNow) return winNow
            var blockNow = findImmediateWinMove(pl)
            if (blockNow) return blockNow

            // Primary move: profit matrix (fast, strong positional play)
            var m = profitBestMove(ai, pl, profitSelfMedium, profitOppMedium)
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
            var m2 = profitBestMove(ai, pl, profitSelfHard, profitOppHard)
            return m2 ? m2 : firstEmptyFallback()
        }

        // --- HARD ---
        if (settings.aiDifficulty === "Hard") {
            // must win / must block
            var winNowH = findImmediateWinMove(ai)
            if (winNowH) return winNowH
            var blockNowH = findImmediateWinMove(pl)
            if (blockNowH) return blockNowH

            // profit matrix
            return profitBestMove(ai, pl, profitSelfHard, profitOppHard)
        }

        // --- UNBEATABLE ---
        // real async Unbeatable is started from aiTimer

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

            if (settings.aiDifficulty === "Unbeatable") {
                startUnbeatableAI()
                return
            }

            // EASY/MEDIUM/HARD: synchronous move selection
            var move = selectAIMove()

            if (!isValidMoveObj(move)) {
                console.warn("[AI] selectAIMove returned invalid move:", move)
                move = firstEmptyFallback()
            }
            if (!isValidMoveObj(move)) {
                console.warn("[AI] No legal moves available")
                return
            }

            applyMove(move.r, move.c)
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
                text: qsTr("Best Times")
                onClicked: pageStack.push(Qt.resolvedUrl("BestTimesPage.qml"), { settings: settings })
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
                        text: "Turn:"
                        font.pixelSize: Theme.fontSizeMedium
                        color: "white"
                    }

                    Text {
                        id: turnValueText
                        text: {
                            if (settings.gameMode === "Player vs AI")
                                return currentPlayer === settings.playerSymbol ? currentPlayerName() : "AI"
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
                        enabled: !aiThinking
                        onClicked: {
                            if (gameOver) return
                            var r = Math.floor(index / boardSize)
                            var c = index % boardSize
                            if (!board[r][c]) {
                                applyMove(r, c)
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

        var last = undoStack.pop()
        redoStack.push({
            board: cloneBoard(board),
            player: currentPlayer,
            lastR: lastMoveR,
            lastC: lastMoveC
        })

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
        publishBoardToCover()
        return true
    }

    function redoOnce() {
        if (redoStack.length === 0) return false

        var next = redoStack.pop()
        undoStack.push({
            board: cloneBoard(board),
            player: currentPlayer,
            lastR: lastMoveR,
            lastC: lastMoveC
        })

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
        publishBoardToCover()
        return true
    }

    // Make sure we pick up startingPlayer once settings is actually set
    Component.onCompleted: {
        if (settings) {
            currentPlayer = settings.startingPlayer
        } else {
            currentPlayer = "X"
       }
       publishBoardToCover()
    }
}

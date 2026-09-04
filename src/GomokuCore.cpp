#include "GomokuCore.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <random>
#include <utility>

namespace Fivinarow {
namespace {

constexpr int WinScore = 1000000000;
constexpr std::array<std::array<int, 2>, 4> Directions{{
    {{1, 0}}, {{0, 1}}, {{1, 1}}, {{1, -1}}
}};

struct RankedMove {
    Move move;
    int orderScore = 0;
    int searchScore = std::numeric_limits<int>::min();
};

struct SearchConfig {
    int maxDepth = 1;
    int rootLimit = 8;
    int branchLimit = 8;
    int deepLimit = 6;
    std::uint64_t nodeBudget = 1000;
    int choiceCount = 1;
    int choiceTolerance = 0;
};

class Search
{
public:
    Search(const std::vector<std::int8_t> &cells, int size,
           Difficulty difficulty, std::uint64_t seed, WinRule winRule)
        : m_board(cells), m_size(size), m_difficulty(difficulty),
          m_winRule(winRule),
          m_random(seed ? seed : UINT64_C(0x9e3779b97f4a7c15))
    {
        if (static_cast<int>(m_board.size()) != m_size * m_size)
            m_board.assign(m_size * m_size, 0);
    }

    SearchResult run()
    {
        SearchResult result;
        if (m_size < 5) return result;

        const auto immediateWins = winningMoves(1);
        if (!immediateWins.empty()) {
            result.move = randomChoice(immediateWins);
            result.score = WinScore;
            return result;
        }

        const auto immediateBlocks = winningMoves(-1);
        if (!immediateBlocks.empty()) {
            if (m_difficulty != Difficulty::Easy || randomPercent() < 85) {
                result.move = randomChoice(immediateBlocks);
                result.score = WinScore / 2;
                return result;
            }
        }

        if (m_difficulty == Difficulty::Easy)
            return chooseEasy(immediateBlocks);

        // A compact opening book avoids spending the full search budget on a
        // nearly empty, highly symmetrical board. All choices stay close to
        // the first stone, but equivalent replies still vary between games.
        if (stoneCount() <= 1) {
            auto opening = candidates(1, 5, 0, false);
            if (!opening.empty()) {
                std::vector<Move> choices;
                for (const auto &candidate : opening) choices.push_back(candidate.move);
                result.move = randomChoice(choices);
                result.score = opening.front().orderScore;
            }
            return result;
        }

        const SearchConfig config = configuration();
        auto roots = candidates(1, config.rootLimit, 0);
        if (roots.empty()) return result;

        std::vector<RankedMove> lastComplete;
        for (int depth = 1; depth <= config.maxDepth; ++depth) {
            m_aborted = false;
            std::vector<RankedMove> iteration = roots;
            for (auto &candidate : iteration) {
                if (budgetReached(config)) {
                    m_aborted = true;
                    break;
                }

                place(candidate.move, 1);
                if (isWin(candidate.move, 1)) {
                    candidate.searchScore = WinScore;
                } else {
                    candidate.searchScore = -negamax(depth - 1, -1,
                                                     -WinScore, WinScore,
                                                     1, config);
                }
                unplace(candidate.move);
            }

            if (m_aborted) break;
            std::sort(iteration.begin(), iteration.end(), strongerSearchMove);
            lastComplete = iteration;
            roots = iteration;
            result.completedDepth = depth;
            if (!lastComplete.empty() && lastComplete.front().searchScore >= WinScore - 20)
                break;
        }

        if (lastComplete.empty()) {
            // The first iteration should fit every configured budget, but a
            // safe ordered move is preferable to returning no move.
            result.move = roots.front().move;
            result.score = roots.front().orderScore;
        } else {
            result.move = chooseFromBestBand(lastComplete, config);
            result.score = lastComplete.front().searchScore;
        }
        result.nodes = m_nodes;
        return result;
    }

private:
    static bool strongerSearchMove(const RankedMove &left, const RankedMove &right)
    {
        if (left.searchScore != right.searchScore)
            return left.searchScore > right.searchScore;
        return left.orderScore > right.orderScore;
    }

    bool inside(int row, int column) const
    {
        return row >= 0 && row < m_size && column >= 0 && column < m_size;
    }

    int index(int row, int column) const { return row * m_size + column; }

    std::int8_t at(int row, int column) const
    {
        return inside(row, column) ? m_board[index(row, column)] : 2;
    }

    void place(const Move &move, int player)
    {
        m_board[index(move.row, move.column)] = static_cast<std::int8_t>(player);
    }

    void unplace(const Move &move) { m_board[index(move.row, move.column)] = 0; }

    int countDirection(const Move &move, int player, int dr, int dc) const
    {
        int count = 0;
        int row = move.row + dr;
        int column = move.column + dc;
        while (inside(row, column) && at(row, column) == player) {
            ++count;
            row += dr;
            column += dc;
        }
        return count;
    }

    bool winningLength(int length) const
    {
        return m_winRule == WinRule::ExactFive ? length == 5 : length >= 5;
    }

    bool wouldWin(const Move &move, int player) const
    {
        if (!inside(move.row, move.column) || at(move.row, move.column) != 0)
            return false;
        for (const auto &direction : Directions) {
            const int length = 1
                + countDirection(move, player, direction[0], direction[1])
                + countDirection(move, player, -direction[0], -direction[1]);
            if (winningLength(length)) return true;
        }
        return false;
    }

    bool isWin(const Move &move, int player) const
    {
        if (!inside(move.row, move.column) || at(move.row, move.column) != player)
            return false;
        for (const auto &direction : Directions) {
            const int length = 1
                + countDirection(move, player, direction[0], direction[1])
                + countDirection(move, player, -direction[0], -direction[1]);
            if (winningLength(length)) return true;
        }
        return false;
    }

    std::vector<Move> winningMoves(int player) const
    {
        std::vector<Move> moves;
        for (int row = 0; row < m_size; ++row) {
            for (int column = 0; column < m_size; ++column) {
                Move move{row, column};
                if (wouldWin(move, player)) moves.push_back(move);
            }
        }
        return moves;
    }

    bool hasNeighbour(int row, int column, int distance) const
    {
        for (int dr = -distance; dr <= distance; ++dr) {
            for (int dc = -distance; dc <= distance; ++dc) {
                if (dr == 0 && dc == 0) continue;
                if (inside(row + dr, column + dc) && at(row + dr, column + dc) != 0)
                    return true;
            }
        }
        return false;
    }

    bool boardEmpty() const
    {
        return std::none_of(m_board.begin(), m_board.end(),
                            [](std::int8_t cell) { return cell != 0; });
    }

    int stoneCount() const
    {
        return static_cast<int>(std::count_if(m_board.begin(), m_board.end(),
                    [](std::int8_t cell) { return cell != 0; }));
    }

    int lineShapeScore(const Move &move, int player, int dr, int dc) const
    {
        const int forward = countDirection(move, player, dr, dc);
        const int backward = countDirection(move, player, -dr, -dc);
        const int length = forward + backward + 1;

        const int forwardRow = move.row + (forward + 1) * dr;
        const int forwardColumn = move.column + (forward + 1) * dc;
        const int backwardRow = move.row - (backward + 1) * dr;
        const int backwardColumn = move.column - (backward + 1) * dc;
        const int openEnds = (at(forwardRow, forwardColumn) == 0 ? 1 : 0)
            + (at(backwardRow, backwardColumn) == 0 ? 1 : 0);

        if (winningLength(length)) return WinScore;
        if (m_winRule == WinRule::ExactFive && length > 5) return 0;
        if (length == 4) return openEnds == 2 ? 30000000
                                              : (openEnds == 1 ? 3000000 : 0);
        if (length == 3) return openEnds == 2 ? 300000
                                              : (openEnds == 1 ? 18000 : 0);
        if (length == 2) return openEnds == 2 ? 5000
                                              : (openEnds == 1 ? 500 : 0);
        return openEnds == 2 ? 30 : 5;
    }

    int windowShapeScore(const Move &move, int player, int dr, int dc) const
    {
        int score = 0;
        for (int start = -4; start <= 0; ++start) {
            int stones = 0;
            bool blocked = false;
            for (int offset = 0; offset < 5; ++offset) {
                const int row = move.row + (start + offset) * dr;
                const int column = move.column + (start + offset) * dc;
                if (!inside(row, column)) {
                    blocked = true;
                    break;
                }
                int cell = at(row, column);
                if (row == move.row && column == move.column) cell = player;
                if (cell == -player) {
                    blocked = true;
                    break;
                }
                if (cell == player) ++stones;
            }
            if (blocked) continue;
            if (stones == 4) score += 600000;
            else if (stones == 3) score += 12000;
            else if (stones == 2) score += 500;
            else if (stones == 1) score += 15;
        }
        return score;
    }

    int shapeScore(const Move &move, int player) const
    {
        if (at(move.row, move.column) != 0) return -WinScore;
        if (wouldWin(move, player)) return WinScore;

        long long score = 0;
        for (const auto &direction : Directions) {
            score += lineShapeScore(move, player, direction[0], direction[1]);
            score += windowShapeScore(move, player, direction[0], direction[1]);
        }
        return static_cast<int>(std::min<long long>(score, WinScore - 1));
    }

    int moveOrderScore(const Move &move, int player) const
    {
        if (wouldWin(move, player)) return WinScore;
        if (wouldWin(move, -player)) return WinScore - 1;

        const long long attack = shapeScore(move, player);
        const long long defence = shapeScore(move, -player);
        const int middle = m_size / 2;
        const int distance = std::abs(move.row - middle) + std::abs(move.column - middle);
        const int centre = std::max(0, m_size - distance);
        const long long value = attack + defence * 11 / 10 + centre;
        return static_cast<int>(std::min<long long>(value, WinScore - 2));
    }

    std::vector<RankedMove> candidates(int player, int limit, int ply,
                                       bool forceTactics = true) const
    {
        std::vector<RankedMove> ranked;
        if (boardEmpty()) {
            const int middle = m_size / 2;
            for (int dr = -1; dr <= 1; ++dr) {
                for (int dc = -1; dc <= 1; ++dc) {
                    Move move{middle + dr, middle + dc};
                    if (inside(move.row, move.column))
                        ranked.push_back({move, moveOrderScore(move, player), 0});
                }
            }
        } else {
            for (int row = 0; row < m_size; ++row) {
                for (int column = 0; column < m_size; ++column) {
                    if (at(row, column) != 0 || !hasNeighbour(row, column, 2)) continue;
                    Move move{row, column};
                    ranked.push_back({move, moveOrderScore(move, player), 0});
                }
            }
        }

        std::sort(ranked.begin(), ranked.end(), [](const RankedMove &left,
                                                    const RankedMove &right) {
            return left.orderScore > right.orderScore;
        });

        if (forceTactics && !ranked.empty() && ranked.front().orderScore == WinScore) {
            ranked.erase(std::remove_if(ranked.begin(), ranked.end(),
                        [](const RankedMove &move) {
                            return move.orderScore != WinScore;
                        }), ranked.end());
        } else if (forceTactics) {
            const auto blocksEnd = std::stable_partition(ranked.begin(), ranked.end(),
                        [](const RankedMove &move) {
                            return move.orderScore == WinScore - 1;
                        });
            if (blocksEnd != ranked.begin()) ranked.erase(blocksEnd, ranked.end());
        }

        if (limit > 0 && static_cast<int>(ranked.size()) > limit)
            ranked.resize(limit);
        (void)ply;
        return ranked;
    }

    long long runValue(int length, int openEnds) const
    {
        if (winningLength(length)) return WinScore;
        if (m_winRule == WinRule::ExactFive && length > 5) return 0;
        if (length == 4) return openEnds == 2 ? 30000000
                                              : (openEnds == 1 ? 3000000 : 0);
        if (length == 3) return openEnds == 2 ? 250000
                                              : (openEnds == 1 ? 15000 : 0);
        if (length == 2) return openEnds == 2 ? 4000
                                              : (openEnds == 1 ? 400 : 0);
        return openEnds == 2 ? 20 : 3;
    }

    long long positionScore(int player) const
    {
        long long score = 0;
        for (const auto &direction : Directions) {
            const int dr = direction[0];
            const int dc = direction[1];
            for (int row = 0; row < m_size; ++row) {
                for (int column = 0; column < m_size; ++column) {
                    if (at(row, column) != player) continue;
                    if (at(row - dr, column - dc) == player) continue;

                    int length = 0;
                    int r = row;
                    int c = column;
                    while (inside(r, c) && at(r, c) == player) {
                        ++length;
                        r += dr;
                        c += dc;
                    }
                    const int openEnds = (at(row - dr, column - dc) == 0 ? 1 : 0)
                        + (at(r, c) == 0 ? 1 : 0);
                    score += runValue(length, openEnds);
                }
            }
        }

        // Five-cell windows also recognise useful broken shapes such as XX.X.
        for (const auto &direction : Directions) {
            const int dr = direction[0];
            const int dc = direction[1];
            for (int row = 0; row < m_size; ++row) {
                for (int column = 0; column < m_size; ++column) {
                    const int endRow = row + 4 * dr;
                    const int endColumn = column + 4 * dc;
                    if (!inside(endRow, endColumn)) continue;

                    int stones = 0;
                    bool blocked = false;
                    for (int offset = 0; offset < 5; ++offset) {
                        const int cell = at(row + offset * dr, column + offset * dc);
                        if (cell == -player) { blocked = true; break; }
                        if (cell == player) ++stones;
                    }
                    if (blocked) continue;
                    if (stones == 4) score += 350000;
                    else if (stones == 3) score += 8000;
                    else if (stones == 2) score += 250;
                }
            }
        }
        return score;
    }

    int evaluate(int player) const
    {
        long long own = positionScore(player);
        long long opponent = positionScore(-player);
        long long value = own - opponent * 11 / 10;
        value = std::max<long long>(-WinScore + 1000,
                                    std::min<long long>(WinScore - 1000, value));
        return static_cast<int>(value);
    }

    bool budgetReached(const SearchConfig &config) const
    {
        return m_nodes >= config.nodeBudget;
    }

    int negamax(int depth, int player, int alpha, int beta, int ply,
                const SearchConfig &config)
    {
        ++m_nodes;
        if (budgetReached(config)) {
            m_aborted = true;
            return evaluate(player);
        }
        if (depth <= 0) return evaluate(player);

        const int limit = ply <= 1 ? config.branchLimit : config.deepLimit;
        const auto moves = candidates(player, limit, ply);
        if (moves.empty()) return 0;

        int best = -WinScore;
        for (const auto &candidate : moves) {
            place(candidate.move, player);
            int score;
            if (isWin(candidate.move, player)) {
                score = WinScore - ply;
            } else {
                score = -negamax(depth - 1, -player, -beta, -alpha,
                                 ply + 1, config);
            }
            unplace(candidate.move);

            if (m_aborted) return best == -WinScore ? score : best;
            best = std::max(best, score);
            alpha = std::max(alpha, score);
            if (alpha >= beta) break;
        }
        return best;
    }

    SearchResult chooseEasy(const std::vector<Move> &immediateBlocks)
    {
        SearchResult result;
        auto ranked = candidates(1, 10, 0, false);
        if (!immediateBlocks.empty()) {
            ranked.erase(std::remove_if(ranked.begin(), ranked.end(),
                         [&immediateBlocks](const RankedMove &candidate) {
                             return std::find(immediateBlocks.begin(), immediateBlocks.end(),
                                              candidate.move) != immediateBlocks.end();
                         }), ranked.end());
        }
        if (ranked.empty()) return result;

        const int count = std::min<int>(8, ranked.size());
        int total = count * (count + 1) / 2;
        std::uniform_int_distribution<int> distribution(1, total);
        int pick = distribution(m_random);
        for (int i = 0; i < count; ++i) {
            pick -= count - i;
            if (pick <= 0) {
                result.move = ranked[i].move;
                result.score = ranked[i].orderScore;
                return result;
            }
        }
        result.move = ranked.front().move;
        result.score = ranked.front().orderScore;
        return result;
    }

    Move chooseFromBestBand(const std::vector<RankedMove> &ranked,
                            const SearchConfig &config)
    {
        const int best = ranked.front().searchScore;
        std::vector<Move> band;
        for (const auto &candidate : ranked) {
            if (static_cast<int>(band.size()) >= config.choiceCount) break;
            if (best - candidate.searchScore <= config.choiceTolerance)
                band.push_back(candidate.move);
        }
        return randomChoice(band.empty() ? std::vector<Move>{ranked.front().move} : band);
    }

    Move randomChoice(const std::vector<Move> &moves)
    {
        if (moves.empty()) return {};
        std::uniform_int_distribution<std::size_t> distribution(0, moves.size() - 1);
        return moves[distribution(m_random)];
    }

    int randomPercent()
    {
        std::uniform_int_distribution<int> distribution(0, 99);
        return distribution(m_random);
    }

    SearchConfig configuration() const
    {
        switch (m_difficulty) {
        case Difficulty::Medium:
            return {2, 10, 8, 6, 3500, 4, 1200};
        case Difficulty::Hard:
            if (stoneCount() < 6) return {3, 12, 9, 7, 16000, 3, 300};
            return {4, 14, 10, 8, 35000, 3, 300};
        case Difficulty::Expert:
            if (stoneCount() < 6) return {4, 14, 10, 8, 50000, 3, 40};
            return {6, 16, 12, 10, 180000, 3, 40};
        case Difficulty::Easy:
            break;
        }
        return {};
    }

    std::vector<std::int8_t> m_board;
    int m_size = 0;
    Difficulty m_difficulty = Difficulty::Medium;
    WinRule m_winRule = WinRule::Freestyle;
    std::mt19937_64 m_random;
    std::uint64_t m_nodes = 0;
    bool m_aborted = false;
};

} // namespace

Difficulty difficultyFromString(const std::string &name)
{
    if (name == "Easy") return Difficulty::Easy;
    if (name == "Hard") return Difficulty::Hard;
    // Keep accepting the RC1/RC2 value so existing settings migrate cleanly.
    if (name == "Expert" || name == "Unbeatable") return Difficulty::Expert;
    return Difficulty::Medium;
}

WinRule winRuleFromString(const std::string &name)
{
    return name == "ExactFive" ? WinRule::ExactFive : WinRule::Freestyle;
}

SearchResult GomokuCore::chooseMove(const std::vector<std::int8_t> &cells,
                                    int boardSize,
                                    Difficulty difficulty,
                                    std::uint64_t randomSeed,
                                    WinRule winRule)
{
    return Search(cells, boardSize, difficulty, randomSeed, winRule).run();
}

} // namespace Fivinarow

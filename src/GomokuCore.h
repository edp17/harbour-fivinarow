#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace Fivinarow {

enum class Difficulty {
    Easy,
    Medium,
    Hard,
    Expert
};

enum class WinRule {
    Freestyle,
    ExactFive
};

struct Move {
    int row = -1;
    int column = -1;

    bool valid() const { return row >= 0 && column >= 0; }
    bool operator==(const Move &other) const
    {
        return row == other.row && column == other.column;
    }
};

struct SearchResult {
    Move move;
    int score = 0;
    int completedDepth = 0;
    std::uint64_t nodes = 0;
};

Difficulty difficultyFromString(const std::string &name);
WinRule winRuleFromString(const std::string &name);

class GomokuCore
{
public:
    // Board cells use 1 for the side to move, -1 for its opponent and 0 for
    // empty. The returned move is always for side 1.
    static SearchResult chooseMove(const std::vector<std::int8_t> &cells,
                                   int boardSize,
                                   Difficulty difficulty,
                                   std::uint64_t randomSeed,
                                   WinRule winRule = WinRule::Freestyle);
};

} // namespace Fivinarow

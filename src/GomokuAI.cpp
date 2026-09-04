#include "GomokuAI.h"

#include "GomokuCore.h"

#include <QFutureWatcher>
#include <QtConcurrent>
#include <cstdint>
#include <vector>

GomokuAI::GomokuAI(QObject *parent)
    : QObject(parent)
{
}

void GomokuAI::requestMove(const QVariantList &rows,
                           int boardSize,
                           const QString &aiSymbol,
                           const QString &opponentSymbol,
                           const QString &difficulty,
                           const QString &winRule,
                           uint randomSeed,
                           int requestId)
{
    std::vector<std::int8_t> cells(boardSize * boardSize, 0);
    for (int row = 0; row < boardSize && row < rows.size(); ++row) {
        const QVariantList columns = rows.at(row).toList();
        for (int column = 0; column < boardSize && column < columns.size(); ++column) {
            const QString value = columns.at(column).toString();
            if (value == aiSymbol) cells[row * boardSize + column] = 1;
            else if (value == opponentSymbol) cells[row * boardSize + column] = -1;
        }
    }

    const Fivinarow::Difficulty level =
        Fivinarow::difficultyFromString(difficulty.toStdString());
    const Fivinarow::WinRule rule =
        Fivinarow::winRuleFromString(winRule.toStdString());
    auto *watcher = new QFutureWatcher<Fivinarow::SearchResult>(this);

    ++m_activeJobs;
    if (m_activeJobs == 1) emit busyChanged();

    connect(watcher, &QFutureWatcher<Fivinarow::SearchResult>::finished,
            this, [this, watcher, requestId]() {
        const Fivinarow::SearchResult result = watcher->result();
        watcher->deleteLater();

        --m_activeJobs;
        if (m_activeJobs == 0) emit busyChanged();
        emit moveReady(requestId, result.move.row, result.move.column,
                       result.completedDepth,
                       static_cast<int>(result.nodes));
    });

    watcher->setFuture(QtConcurrent::run([cells, boardSize, level, rule, randomSeed]() {
        return Fivinarow::GomokuCore::chooseMove(cells, boardSize, level,
                                                 static_cast<std::uint64_t>(randomSeed),
                                                 rule);
    }));
}

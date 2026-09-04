#pragma once

#include <QObject>
#include <QVariantList>

class GomokuAI : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit GomokuAI(QObject *parent = nullptr);

    bool busy() const { return m_activeJobs > 0; }

    Q_INVOKABLE void requestMove(const QVariantList &rows,
                                 int boardSize,
                                 const QString &aiSymbol,
                                 const QString &opponentSymbol,
                                 const QString &difficulty,
                                 const QString &winRule,
                                 uint randomSeed,
                                 int requestId);

signals:
    void busyChanged();
    void moveReady(int requestId, int row, int column,
                   int completedDepth, int nodes);

private:
    int m_activeJobs = 0;
};

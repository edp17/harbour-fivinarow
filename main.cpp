#include <sailfishapp.h>
#include <QGuiApplication>
#include <QLocale>
#include <QQuickView>
#include <QTranslator>
#include <QtQml>
#include "GomokuAI.h"

int main(int argc, char *argv[])
{
    QGuiApplication *app = SailfishApp::application(argc, argv);
    QQuickView *view = SailfishApp::createView();

    QTranslator translator;
    const QString translationDirectory = SailfishApp::pathTo(
        QStringLiteral("translations")).toLocalFile();
    if (translator.load(QLocale(), QStringLiteral("harbour-fivinarow"),
                        QStringLiteral("-"), translationDirectory)) {
        app->installTranslator(&translator);
    }

    qmlRegisterType<GomokuAI>("harbour.fivinarow", 1, 0, "GomokuAI");

    view->setSource(SailfishApp::pathTo("qml/harbour-fivinarow.qml"));
    view->show();
    return app->exec();
}

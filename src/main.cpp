#include <clocale>

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>

int main(int argc, char *argv[])
{
    // QQuickFramebufferObject + mpv's OpenGL render API require the OpenGL RHI
    // backend; pin it before the application is constructed.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("Chopstick Media Player"));

    // libmpv requires the C numeric locale; Qt may have switched it. Reset it
    // AFTER constructing QGuiApplication, or mpv_initialize misbehaves.
    std::setlocale(LC_NUMERIC, "C");

    // Optional file path from the command line, opened on startup by Main.qml.
    // Passed to mpv's loadfile as-is, which accepts local paths and URLs.
    QString startupFile;
    const QStringList args = QGuiApplication::arguments();
    if (args.size() > 1)
        startupFile = args.at(1);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("startupFile"),
                                             startupFile);

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    engine.loadFromModule("Chopstick", "Main");

    return app.exec();
}

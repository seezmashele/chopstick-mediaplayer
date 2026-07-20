#include <clocale>

#include <QGuiApplication>
#include <QIcon>
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
    // QSettings (used by the QML Settings type) needs an organization to derive
    // its storage path: ~/.config/Chopstick/Chopstick Media Player.conf
    QGuiApplication::setOrganizationName(QStringLiteral("Chopstick"));
    // Wayland compositors resolve the window icon via the .desktop file matched
    // to this name, so set it alongside the icon itself.
    QGuiApplication::setDesktopFileName(QStringLiteral("chopstick"));
    QGuiApplication::setWindowIcon(
        QIcon(QStringLiteral(":/qt/qml/Chopstick/assets/icons/chopstick-logo.svg")));

    // libmpv requires the C numeric locale; Qt may have switched it. Reset it
    // AFTER constructing QGuiApplication, or mpv_initialize misbehaves.
    std::setlocale(LC_NUMERIC, "C");

    // Optional file paths from the command line, opened on startup by Main.qml:
    // the first plays, the rest queue onto the playlist. Passed to mpv's
    // loadfile as-is, which accepts local paths and URLs.
    QStringList startupFiles = QGuiApplication::arguments();
    startupFiles.removeFirst(); // drop argv[0]

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("startupFiles"),
                                             startupFiles);

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

    engine.loadFromModule("Chopstick", "Main");

    return app.exec();
}

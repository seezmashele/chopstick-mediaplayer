#pragma once

#include <QtQuick/QQuickFramebufferObject>
#include <QList>
#include <QString>
#include <QUrl>
#include <QVariant>

#include <mpv/client.h>
#include <mpv/render_gl.h>

// MpvItem exposes libmpv to QML. It owns the mpv_handle and delegates GL
// compositing to a private MpvRenderer (see mpvitem.cpp), which Qt drives on
// the scene-graph render thread. The two share the mpv_handle, which is
// thread-safe by libmpv's own contract.
//
// Playback state (position, duration, codecs, ...) is surfaced as Q_PROPERTYs,
// kept up to date from mpv's event stream: mpv wakes us on its own thread, we
// hop to the GUI thread via a queued signal and drain events there.
class MpvItem : public QQuickFramebufferObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool paused READ paused NOTIFY pausedChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(QString videoCodec READ videoCodec NOTIFY videoCodecChanged)
    Q_PROPERTY(QString audioCodec READ audioCodec NOTIFY audioCodecChanged)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY videoSizeChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY videoSizeChanged)
    Q_PROPERTY(int audioTrackCount READ audioTrackCount NOTIFY audioTracksChanged)
    Q_PROPERTY(int audioTrackCurrent READ audioTrackCurrent NOTIFY audioTracksChanged)
    Q_PROPERTY(int subTrackCount READ subTrackCount NOTIFY subTracksChanged)
    Q_PROPERTY(int subTrackCurrent READ subTrackCurrent NOTIFY subTracksChanged)

public:
    explicit MpvItem(QQuickItem *parent = nullptr);
    ~MpvItem() override;

    Renderer *createRenderer() const override;

    mpv_handle *handle() const { return m_mpv; }

    double position() const { return m_position; }
    double duration() const { return m_duration; }
    bool paused() const { return m_paused; }
    bool muted() const { return m_muted; }
    double volume() const { return m_volume; }
    QString videoCodec() const { return m_videoCodec; }
    QString audioCodec() const { return m_audioCodec; }
    int videoWidth() const { return m_videoWidth; }
    int videoHeight() const { return m_videoHeight; }
    int audioTrackCount() const { return m_audioTrackCount; }
    int audioTrackCurrent() const { return m_audioTrackCurrent; }
    int subTrackCount() const { return m_subTrackCount; }
    int subTrackCurrent() const { return m_subTrackCurrent; }

    // Issue an mpv command from QML, e.g. command(["cycle", "pause"]).
    Q_INVOKABLE void command(const QVariant &args);
    // Convenience for the common case of opening a file.
    Q_INVOKABLE void loadFile(const QString &path);
    // Open dropped/selected files: the first replaces playback, the rest are
    // appended to mpv's playlist.
    Q_INVOKABLE void openUrls(const QList<QUrl> &urls);
    // Hand off to the compositor to move the window (required on Wayland, where
    // an app can't set its own position). Call while a mouse button is held.
    Q_INVOKABLE void beginWindowDrag();

    // libmpv callbacks (called from mpv's threads).
    static void onMpvRedraw(void *ctx);  // new video frame available
    static void onMpvEvents(void *ctx);  // events pending in the queue

signals:
    void redrawRequested();
    // Emitted once the mpv render context exists and it's safe to load a file.
    void ready();
    void mpvEventsPending();

    void positionChanged();
    void durationChanged();
    void pausedChanged();
    void mutedChanged();
    void volumeChanged();
    void videoCodecChanged();
    void audioCodecChanged();
    void videoSizeChanged();
    void audioTracksChanged();
    void subTracksChanged();

private slots:
    void doUpdate();
    void handleRenderContextCreated();
    void handleMpvEvents();

private:
    void handlePropertyChange(mpv_event_property *prop);

    mpv_handle *m_mpv = nullptr;

    double m_position = 0.0;
    double m_duration = 0.0;
    bool m_paused = false;
    bool m_muted = false;
    double m_volume = 100.0;
    QString m_videoCodec;
    QString m_audioCodec;
    int m_videoWidth = 0;
    int m_videoHeight = 0;
    int m_audioTrackCount = 0;
    int m_audioTrackCurrent = 0;
    int m_subTrackCount = 0;
    int m_subTrackCurrent = 0;
};

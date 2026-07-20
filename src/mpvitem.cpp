#include "mpvitem.h"

#include <cstdint>
#include <cstring>

#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QtGlobal>
#include <QtQuick/QQuickWindow>

namespace {

// Resolve GL entry points through Qt's current context so mpv renders into the
// same GL context the scene graph is using.
void *getProcAddressMpv(void *ctx, const char *name)
{
    Q_UNUSED(ctx)
    QOpenGLContext *glctx = QOpenGLContext::currentContext();
    if (!glctx)
        return nullptr;
    return reinterpret_cast<void *>(glctx->getProcAddress(QByteArray(name)));
}

// Look up a value by key in an mpv node map; returns nullptr if absent.
const mpv_node *mapGet(const mpv_node *map, const char *key)
{
    if (!map || map->format != MPV_FORMAT_NODE_MAP)
        return nullptr;
    const mpv_node_list *l = map->u.list;
    for (int i = 0; i < l->num; ++i)
        if (std::strcmp(l->keys[i], key) == 0)
            return &l->values[i];
    return nullptr;
}

// Renders mpv's video output into the FBO that Qt then draws as a textured
// node in the scene graph. Lives entirely on the render thread.
class MpvRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvRenderer(MpvItem *item) : m_item(item) {}

    ~MpvRenderer() override
    {
        // Must be torn down before the mpv_handle it was created from.
        if (m_mpvGl)
            mpv_render_context_free(m_mpvGl);
    }

    // Called with the GL context current, so this is where we can safely
    // initialize the mpv render context on first use.
    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_mpvGl) {
            mpv_opengl_init_params glInit{getProcAddressMpv, nullptr};
            mpv_render_param params[]{
                {MPV_RENDER_PARAM_API_TYPE,
                 const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
                {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
                {MPV_RENDER_PARAM_INVALID, nullptr},
            };
            if (mpv_render_context_create(&m_mpvGl, m_item->handle(), params) < 0)
                qFatal("failed to initialize mpv GL render context");
            mpv_render_context_set_update_callback(
                m_mpvGl, MpvItem::onMpvRedraw, m_item);
            // Tell the item (on the GUI thread) that it's now safe to load a
            // file, since vo=libmpv needs this context to exist first.
            QMetaObject::invokeMethod(m_item, "handleRenderContextCreated",
                                      Qt::QueuedConnection);
        }
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo mpfbo{static_cast<int>(fbo->handle()),
                             fbo->width(), fbo->height(), 0};
        int flipY = 0;
        mpv_render_param params[]{
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        // Bracket mpv's raw GL calls so the scene graph resets its own GL state
        // afterwards; otherwise mpv's state changes corrupt the control bar and
        // other QML visuals drawn over the video.
        QQuickWindow *win = m_item->window();
        if (win)
            win->beginExternalCommands();
        mpv_render_context_render(m_mpvGl, params);
        if (win)
            win->endExternalCommands();
    }

private:
    MpvItem *m_item;
    mpv_render_context *m_mpvGl = nullptr;
};

} // namespace

MpvItem::MpvItem(QQuickItem *parent) : QQuickFramebufferObject(parent)
{
    m_mpv = mpv_create();
    if (!m_mpv)
        qFatal("could not create mpv context");

    // Route video output through the libmpv render API so mpv never creates its
    // own window; it waits for our render context and draws into our FBO. Must
    // be set before mpv_initialize().
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    mpv_set_option_string(m_mpv, "hwdec", "auto");
    // Log to stderr while we're bringing the pipeline up.
    mpv_set_option_string(m_mpv, "terminal", "yes");
    mpv_set_option_string(m_mpv, "msg-level", "all=info");

    if (mpv_initialize(m_mpv) < 0)
        qFatal("could not initialize mpv context");

    // Marshal mpv's cross-thread redraw notifications onto the GUI thread.
    connect(this, &MpvItem::redrawRequested, this, &MpvItem::doUpdate,
            Qt::QueuedConnection);

    // Same pattern for mpv's event queue: wake up on mpv's thread, drain on the
    // GUI thread where it's safe to touch Q_PROPERTYs / emit NOTIFY signals.
    connect(this, &MpvItem::mpvEventsPending, this, &MpvItem::handleMpvEvents,
            Qt::QueuedConnection);
    mpv_set_wakeup_callback(m_mpv, MpvItem::onMpvEvents, this);

    // Track the playback state the control bar displays.
    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "mute", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "video-format", MPV_FORMAT_STRING);
    mpv_observe_property(m_mpv, 0, "audio-codec-name", MPV_FORMAT_STRING);
    mpv_observe_property(m_mpv, 0, "video-params/w", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "video-params/h", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "track-list", MPV_FORMAT_NODE);
}

MpvItem::~MpvItem()
{
    if (m_mpv)
        mpv_terminate_destroy(m_mpv);
}

QQuickFramebufferObject::Renderer *MpvItem::createRenderer() const
{
    return new MpvRenderer(const_cast<MpvItem *>(this));
}

void MpvItem::command(const QVariant &args)
{
    if (!m_mpv)
        return;

    const QVariantList list = args.toList();
    if (list.isEmpty())
        return;

    // libmpv takes a null-terminated array of C strings; stringify each arg
    // (numbers like seek amounts convert cleanly).
    QVector<QByteArray> owned;
    owned.reserve(list.size());
    for (const QVariant &v : list)
        owned.push_back(v.toString().toUtf8());

    QVector<const char *> cargs;
    cargs.reserve(owned.size() + 1);
    for (const QByteArray &b : owned)
        cargs.push_back(b.constData());
    cargs.push_back(nullptr);

    mpv_command(m_mpv, cargs.data());
}

void MpvItem::loadFile(const QString &path)
{
    command(QVariantList{QStringLiteral("loadfile"), path});
}

void MpvItem::openUrls(const QList<QUrl> &urls)
{
    bool first = true;
    for (const QUrl &url : urls) {
        // Local files become clean filesystem paths (no file:// / percent
        // encoding); remote URLs pass through for mpv to handle.
        const QString target =
            url.isLocalFile() ? url.toLocalFile() : url.toString();
        if (target.isEmpty())
            continue;

        if (first) {
            loadFile(target); // replace current playback
            first = false;
        } else {
            command(QVariantList{QStringLiteral("loadfile"), target,
                                 QStringLiteral("append-play")});
        }
    }
}

void MpvItem::beginWindowDrag()
{
    if (QQuickWindow *w = window())
        w->startSystemMove();
}

void MpvItem::onMpvRedraw(void *ctx)
{
    // Runs on mpv's render thread; the queued connection hops to the GUI thread.
    emit static_cast<MpvItem *>(ctx)->redrawRequested();
}

void MpvItem::doUpdate()
{
    update();
}

void MpvItem::handleRenderContextCreated()
{
    emit ready();
}

void MpvItem::onMpvEvents(void *ctx)
{
    // Runs on mpv's thread; the queued connection hops to the GUI thread.
    emit static_cast<MpvItem *>(ctx)->mpvEventsPending();
}

void MpvItem::handleMpvEvents()
{
    // Drain the queue without blocking (timeout 0).
    while (m_mpv) {
        mpv_event *event = mpv_wait_event(m_mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        if (event->event_id == MPV_EVENT_PROPERTY_CHANGE)
            handlePropertyChange(static_cast<mpv_event_property *>(event->data));
    }
}

void MpvItem::handlePropertyChange(mpv_event_property *prop)
{
    // When a property is unavailable, mpv reports MPV_FORMAT_NONE with null
    // data, so each case falls back to a cleared/zero value.
    const QByteArray name(prop->name);

    if (name == "time-pos") {
        m_position = prop->format == MPV_FORMAT_DOUBLE
                         ? *static_cast<double *>(prop->data)
                         : 0.0;
        emit positionChanged();
    } else if (name == "duration") {
        m_duration = prop->format == MPV_FORMAT_DOUBLE
                         ? *static_cast<double *>(prop->data)
                         : 0.0;
        emit durationChanged();
    } else if (name == "pause") {
        if (prop->format == MPV_FORMAT_FLAG)
            m_paused = *static_cast<int *>(prop->data) != 0;
        emit pausedChanged();
    } else if (name == "mute") {
        if (prop->format == MPV_FORMAT_FLAG)
            m_muted = *static_cast<int *>(prop->data) != 0;
        emit mutedChanged();
    } else if (name == "volume") {
        if (prop->format == MPV_FORMAT_DOUBLE)
            m_volume = *static_cast<double *>(prop->data);
        emit volumeChanged();
    } else if (name == "video-format") {
        m_videoCodec = prop->format == MPV_FORMAT_STRING
                           ? QString::fromUtf8(*static_cast<char **>(prop->data))
                           : QString();
        emit videoCodecChanged();
    } else if (name == "audio-codec-name") {
        m_audioCodec = prop->format == MPV_FORMAT_STRING
                           ? QString::fromUtf8(*static_cast<char **>(prop->data))
                           : QString();
        emit audioCodecChanged();
    } else if (name == "video-params/w") {
        m_videoWidth = prop->format == MPV_FORMAT_INT64
                           ? static_cast<int>(*static_cast<int64_t *>(prop->data))
                           : 0;
        emit videoSizeChanged();
    } else if (name == "video-params/h") {
        m_videoHeight = prop->format == MPV_FORMAT_INT64
                            ? static_cast<int>(*static_cast<int64_t *>(prop->data))
                            : 0;
        emit videoSizeChanged();
    } else if (name == "track-list") {
        int aCount = 0, aCur = 0, sCount = 0, sCur = 0;
        if (prop->format == MPV_FORMAT_NODE) {
            const mpv_node *node = static_cast<mpv_node *>(prop->data);
            if (node && node->format == MPV_FORMAT_NODE_ARRAY) {
                const mpv_node_list *arr = node->u.list;
                for (int i = 0; i < arr->num; ++i) {
                    const mpv_node *track = &arr->values[i];
                    const mpv_node *type = mapGet(track, "type");
                    const mpv_node *sel = mapGet(track, "selected");
                    if (!type || type->format != MPV_FORMAT_STRING)
                        continue;
                    const bool selected = sel && sel->format == MPV_FORMAT_FLAG
                                          && sel->u.flag;
                    if (std::strcmp(type->u.string, "audio") == 0) {
                        ++aCount;
                        if (selected)
                            aCur = aCount;
                    } else if (std::strcmp(type->u.string, "sub") == 0) {
                        ++sCount;
                        if (selected)
                            sCur = sCount;
                    }
                }
            }
        }
        if (aCount != m_audioTrackCount || aCur != m_audioTrackCurrent) {
            m_audioTrackCount = aCount;
            m_audioTrackCurrent = aCur;
            emit audioTracksChanged();
        }
        if (sCount != m_subTrackCount || sCur != m_subTrackCurrent) {
            m_subTrackCount = sCount;
            m_subTrackCurrent = sCur;
            emit subTracksChanged();
        }
    }
}

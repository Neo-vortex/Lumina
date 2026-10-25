// JNI bridge between dev.lumina.calls.NativeCall (Kotlin) and tgcalls, for
// one-to-one voice and video calls.
//
// Adapted from Telegram-Android's TMessagesProj/jni/voip/
// org_telegram_messenger_voip_Instance.cpp (GNU GPL v2 or later; copyright
// Telegram FZ-LLC and contributors), trimmed to private calls: no group
// calls, streams or conference encryption. Lumina is GPL-3.0-or-later
// (docs/DECISIONS.md D14).

#include <jni.h>

#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include <modules/utility/include/jvm_android.h>
#include <platform/android/AndroidContext.h>
#include <platform/android/AndroidInterface.h>
#include <rtc_base/ssl_adapter.h>
#include <sdk/android/native_api/base/init.h>
#include <sdk/android/native_api/video/wrapper.h>
#include <voip/webrtc/media/base/media_constants.h>

#include "InstanceImpl.h"
#include "StaticThreads.h"
#include "tgcalls/VideoCaptureInterface.h"
#include "tgcalls/v2/InstanceV2Impl.h"
#include "tgcalls/v2/InstanceV2ReferenceImpl.h"
#include "v2wasm/InstanceV2PumpImpl.h"

using namespace tgcalls;

// Protocol versions this build can speak; Meta::Versions() lists them for
// CallProtocol.libraryVersions.
const auto RegisterTag = Register<InstanceImpl>();
const auto RegisterTagV2_4_0_1 = Register<InstanceV2Impl>();
const auto RegisterTagV2_4_1_2 = Register<InstanceV2ReferenceImpl>();
#if defined(__aarch64__)
const auto RegisterTagV2_Pump = Register<InstanceV2PumpImpl>();
#endif

namespace {

JavaVM *sharedJvm = nullptr;
jclass nativeCallClass = nullptr;

// Mirrors NativeCall's constants.
constexpr jint kStateWaitInit = 1;
constexpr jint kStateWaitInitAck = 2;
constexpr jint kStateEstablished = 3;
constexpr jint kStateFailed = 4;
constexpr jint kStateReconnecting = 5;

constexpr jint kEndpointInet = 0;
constexpr jint kEndpointLan = 1;
constexpr jint kEndpointUdpRelay = 2;
constexpr jint kEndpointTcpRelay = 3;

JNIEnv *currentEnv() {
    JNIEnv *env = nullptr;
    sharedJvm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    return env;
}

// Runs [f] with a JNIEnv, attaching the calling (tgcalls) thread if needed.
void withJni(const std::function<void(JNIEnv *)> &f) {
    JNIEnv *env = currentEnv();
    bool attached = false;
    if (env == nullptr) {
        sharedJvm->AttachCurrentThread(&env, nullptr);
        attached = true;
    }
    f(env);
    if (attached) sharedJvm->DetachCurrentThread();
}

std::string toStdString(JNIEnv *env, jstring s) {
    if (s == nullptr) return "";
    const char *chars = env->GetStringUTFChars(s, nullptr);
    std::string out(chars);
    env->ReleaseStringUTFChars(s, chars);
    return out;
}

jbyteArray toJavaBytes(JNIEnv *env, const std::vector<uint8_t> &bytes) {
    jbyteArray out = env->NewByteArray(static_cast<jsize>(bytes.size()));
    env->SetByteArrayRegion(out, 0, static_cast<jsize>(bytes.size()), reinterpret_cast<const jbyte *>(bytes.data()));
    return out;
}

/// Reads public (@JvmField) fields of a Kotlin object by name.
class Fields {
public:
    Fields(JNIEnv *env, jobject obj) : env_(env), obj_(obj), class_(env->GetObjectClass(obj)) {}
    ~Fields() { env_->DeleteLocalRef(class_); }

    jint i(const char *name) { return env_->GetIntField(obj_, env_->GetFieldID(class_, name, "I")); }
    jlong l(const char *name) { return env_->GetLongField(obj_, env_->GetFieldID(class_, name, "J")); }
    bool z(const char *name) { return env_->GetBooleanField(obj_, env_->GetFieldID(class_, name, "Z")) == JNI_TRUE; }
    jdouble d(const char *name) { return env_->GetDoubleField(obj_, env_->GetFieldID(class_, name, "D")); }
    std::string s(const char *name) {
        auto value = static_cast<jstring>(env_->GetObjectField(obj_, env_->GetFieldID(class_, name, "Ljava/lang/String;")));
        std::string out = toStdString(env_, value);
        env_->DeleteLocalRef(value);
        return out;
    }
    jbyteArray bytes(const char *name) {
        return static_cast<jbyteArray>(env_->GetObjectField(obj_, env_->GetFieldID(class_, name, "[B")));
    }

private:
    JNIEnv *env_;
    jobject obj_;
    jclass class_;
};

struct CallHolder {
    std::unique_ptr<Instance> instance;
    std::shared_ptr<VideoCaptureInterface> camera;
    std::shared_ptr<VideoCaptureInterface> screen;
    bool useScreen = false;
    std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> remoteSink;
    std::shared_ptr<PlatformContext> platformContext;
    std::string persistentStatePath;
};

CallHolder *holderOf(JNIEnv *env, jobject obj) {
    static jfieldID ptr = env->GetFieldID(nativeCallClass, "nativePtr", "J");
    return reinterpret_cast<CallHolder *>(env->GetLongField(obj, ptr));
}

jobject peerOf(const std::shared_ptr<PlatformContext> &context) {
    return static_cast<AndroidContext *>(context.get())->getJavaPeerInstance();
}

// Capturers made before a call starts (preview), keyed to the context that
// must become the call's platform context.
std::mutex capturerContextsMutex;
std::map<VideoCaptureInterface *, std::shared_ptr<PlatformContext>> capturerContexts;

void initWebRtc(JNIEnv *env) {
    static bool done = false;
    if (done) return;
    JavaVM *vm = nullptr;
    env->GetJavaVM(&vm);
    webrtc::InitAndroid(vm);
    webrtc::JVM::Initialize(vm);
    rtc::InitializeSSL();
    done = true;
}

void readPersistentState(const std::string &path, PersistentState &state) {
    FILE *f = fopen(path.c_str(), "r");
    if (f == nullptr) return;
    fseek(f, 0, SEEK_END);
    auto len = static_cast<size_t>(ftell(f));
    fseek(f, 0, SEEK_SET);
    if (len > 0 && len < 512 * 1024) {
        state.value.resize(len);
        if (fread(state.value.data(), 1, len, f) != len) state.value.clear();
    }
    fclose(f);
}

void savePersistentState(const std::string &path, const PersistentState &state) {
    if (path.empty()) return;
    FILE *f = fopen(path.c_str(), "w");
    if (f == nullptr) return;
    fwrite(state.value.data(), 1, state.value.size(), f);
    fclose(f);
}

NetworkType networkType(jint t) {
    // Same numbering as Telegram's Instance.NET_TYPE_*.
    switch (t) {
        case 1: return NetworkType::Gprs;
        case 2: return NetworkType::Edge;
        case 3: return NetworkType::ThirdGeneration;
        case 4: return NetworkType::Hspa;
        case 5: return NetworkType::Lte;
        case 6: return NetworkType::WiFi;
        case 7: return NetworkType::Ethernet;
        case 8: return NetworkType::OtherHighSpeed;
        case 9: return NetworkType::OtherLowSpeed;
        case 10: return NetworkType::Dialup;
        case 11: return NetworkType::OtherMobile;
        default: return NetworkType::Unknown;
    }
}

DataSaving dataSaving(jint d) {
    switch (d) {
        case 1: return DataSaving::Mobile;
        case 2: return DataSaving::Always;
        default: return DataSaving::Never;
    }
}

EndpointType endpointType(jint t) {
    switch (t) {
        case kEndpointInet: return EndpointType::Inet;
        case kEndpointLan: return EndpointType::Lan;
        case kEndpointTcpRelay: return EndpointType::TcpRelay;
        case kEndpointUdpRelay:
        default: return EndpointType::UdpRelay;
    }
}

jint javaState(State state) {
    switch (state) {
        case State::WaitInit: return kStateWaitInit;
        case State::WaitInitAck: return kStateWaitInitAck;
        case State::Established: return kStateEstablished;
        case State::Failed: return kStateFailed;
        case State::Reconnecting: return kStateReconnecting;
    }
    return kStateFailed;
}

void pushServer(std::vector<RtcServer> &servers, RtcServer &&server, const std::string &ipv6) {
    if (!ipv6.empty()) {
        RtcServer v6 = server;
        v6.host = ipv6;
        servers.push_back(std::move(server));
        servers.push_back(std::move(v6));
    } else {
        servers.push_back(std::move(server));
    }
}

void callPeer(const std::shared_ptr<PlatformContext> &context, const char *name, const char *signature,
              const std::function<void(JNIEnv *, jobject, jmethodID)> &call) {
    jobject peer = peerOf(context);
    withJni([&](JNIEnv *env) {
        jmethodID method = env->GetMethodID(nativeCallClass, name, signature);
        call(env, peer, method);
    });
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *) {
    sharedJvm = vm;
    JNIEnv *env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) return -1;
    jclass local = env->FindClass("dev/lumina/calls/NativeCall");
    if (local == nullptr) return -1;
    nativeCallClass = static_cast<jclass>(env->NewGlobalRef(local));
    env->DeleteLocalRef(local);
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_dev_lumina_calls_NativeCall_versions(JNIEnv *env, jclass) {
    std::vector<std::string> versions = Meta::Versions();
    jclass stringClass = env->FindClass("java/lang/String");
    jobjectArray out = env->NewObjectArray(static_cast<jsize>(versions.size()), stringClass, nullptr);
    for (size_t i = 0; i < versions.size(); i++) {
        jstring s = env->NewStringUTF(versions[i].c_str());
        env->SetObjectArrayElement(out, static_cast<jsize>(i), s);
        env->DeleteLocalRef(s);
    }
    return out;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_lumina_calls_NativeCall_maxLayer(JNIEnv *, jclass) {
    return Meta::MaxLayer();
}

// type: 0 back camera, 1 front camera, 2 screen.
extern "C" JNIEXPORT jlong JNICALL
Java_dev_lumina_calls_NativeCall_createCapturer(JNIEnv *env, jclass, jobject localSink, jint type) {
    initWebRtc(env);
    const bool screen = type == 2;
    auto context = std::make_shared<AndroidContext>(env, nullptr, nullptr, screen);
    std::unique_ptr<VideoCaptureInterface> capture = VideoCaptureInterface::Create(
        StaticThreads::getThreads(), screen ? "screen" : (type == 1 ? "front" : "back"), screen, context);
    if (!capture) return 0;
    capture->setOutput(webrtc::JavaToNativeVideoSink(env, localSink));
    capture->setState(VideoState::Active);
    auto *holder = new std::shared_ptr<VideoCaptureInterface>(std::move(capture));
    std::lock_guard<std::mutex> lock(capturerContextsMutex);
    capturerContexts[holder->get()] = context;
    return reinterpret_cast<jlong>(holder);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_destroyCapturer(JNIEnv *, jclass, jlong capturer) {
    if (capturer == 0) return;
    auto *holder = reinterpret_cast<std::shared_ptr<VideoCaptureInterface> *>(capturer);
    {
        std::lock_guard<std::mutex> lock(capturerContextsMutex);
        capturerContexts.erase(holder->get());
    }
    delete holder;
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_switchCapturerCamera(JNIEnv *, jclass, jlong capturer, jboolean front) {
    if (capturer == 0) return;
    (*reinterpret_cast<std::shared_ptr<VideoCaptureInterface> *>(capturer))->switchToDevice(front ? "front" : "back", false);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_setCapturerState(JNIEnv *, jclass, jlong capturer, jint state) {
    if (capturer == 0) return;
    (*reinterpret_cast<std::shared_ptr<VideoCaptureInterface> *>(capturer))->setState(static_cast<VideoState>(state));
}

// Starts the call once TDLib reports CallStateReady. [config] is a
// NativeCall.Config, [endpoints] NativeCall.Endpoint[], [proxy] a nullable
// NativeCall.Proxy (SOCKS5).
extern "C" JNIEXPORT jlong JNICALL
Java_dev_lumina_calls_NativeCall_start(JNIEnv *env, jobject self, jstring version, jobject config,
                                       jobjectArray endpoints, jobject proxy, jint network, jbyteArray key,
                                       jboolean outgoing, jobject remoteSink, jlong capturer, jfloat aspectRatio,
                                       jstring persistentStatePath) {
    initWebRtc(env);
    if (env->GetArrayLength(key) != 256) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Encryption key must be 256 bytes");
        return 0;
    }
    auto keyBytes = std::make_shared<std::array<uint8_t, 256>>();
    env->GetByteArrayRegion(key, 0, 256, reinterpret_cast<jbyte *>(keyBytes->data()));

    std::shared_ptr<VideoCaptureInterface> camera;
    std::shared_ptr<PlatformContext> context;
    if (capturer != 0) {
        camera = *reinterpret_cast<std::shared_ptr<VideoCaptureInterface> *>(capturer);
        std::lock_guard<std::mutex> lock(capturerContextsMutex);
        auto it = capturerContexts.find(camera.get());
        if (it != capturerContexts.end()) context = it->second;
    }
    if (context) {
        static_cast<AndroidContext *>(context.get())->setJavaPeerInstance(env, self);
    } else {
        context = std::make_shared<AndroidContext>(env, self, nullptr, false);
    }

    Fields c(env, config);
    Descriptor descriptor = {
        .config = Config{
            .initializationTimeout = c.d("initializationTimeout"),
            .receiveTimeout = c.d("receiveTimeout"),
            .dataSaving = dataSaving(c.i("dataSaving")),
            .enableP2P = c.z("enableP2p"),
            .enableStunMarking = false,
            .enableAEC = c.z("enableAec"),
            .enableNS = c.z("enableNs"),
            .enableAGC = c.z("enableAgc"),
            .enableVolumeControl = true,
            .logPath = {c.s("logPath")},
            .statsLogPath = {c.s("statsLogPath")},
            .maxApiLayer = c.i("maxApiLayer"),
            .enableHighBitrateVideo = true,
            .preferredVideoCodecs = {cricket::kVp9CodecName},
            .customParameters = c.s("customParameters"),
        },
        .encryptionKey = EncryptionKey(std::move(keyBytes), outgoing == JNI_TRUE),
        .videoCapture = camera,
        .stateUpdated = [context](State state) {
            const jint s = javaState(state);
            callPeer(context, "onStateUpdated", "(I)V", [s](JNIEnv *env, jobject peer, jmethodID m) {
                env->CallVoidMethod(peer, m, s);
            });
        },
        .signalBarsUpdated = [context](int bars) {
            callPeer(context, "onSignalBarsUpdated", "(I)V", [bars](JNIEnv *env, jobject peer, jmethodID m) {
                env->CallVoidMethod(peer, m, static_cast<jint>(bars));
            });
        },
        .audioLevelsUpdated = [context](float mine, float theirs) {
            callPeer(context, "onAudioLevels", "(FF)V", [mine, theirs](JNIEnv *env, jobject peer, jmethodID m) {
                env->CallVoidMethod(peer, m, mine, theirs);
            });
        },
        .remoteMediaStateUpdated = [context](AudioState audio, VideoState video) {
            callPeer(context, "onRemoteMediaState", "(II)V", [audio, video](JNIEnv *env, jobject peer, jmethodID m) {
                env->CallVoidMethod(peer, m, static_cast<jint>(audio), static_cast<jint>(video));
            });
        },
        .signalingDataEmitted = [context](const std::vector<uint8_t> &data) {
            callPeer(context, "onSignalingData", "([B)V", [&data](JNIEnv *env, jobject peer, jmethodID m) {
                jbyteArray bytes = toJavaBytes(env, data);
                env->CallVoidMethod(peer, m, bytes);
                env->DeleteLocalRef(bytes);
            });
        },
    };
    descriptor.version = toStdString(env, version);

    for (jsize i = 0, n = env->GetArrayLength(endpoints); i < n; i++) {
        jobject e = env->GetObjectArrayElement(endpoints, i);
        Fields f(env, e);
        RtcServer server;
        server.id = static_cast<uint8_t>(f.i("reflectorId"));
        server.host = f.s("ipv4");
        server.port = static_cast<uint16_t>(f.i("port"));
        server.login = f.s("username");
        server.password = f.s("password");
        const std::string ipv6 = f.s("ipv6");
        if (f.z("isRtc")) {
            // WebRTC STUN/TURN server.
            server.isTurn = f.z("turn");
            pushServer(descriptor.rtcServers, std::move(server), ipv6);
        } else {
            // Telegram reflector: usable as TURN and as a tgcalls endpoint.
            server.isTurn = true;
            server.isTcp = f.z("tcp");
            pushServer(descriptor.rtcServers, std::move(server), ipv6);
            Endpoint endpoint;
            endpoint.endpointId = f.l("id");
            endpoint.host = EndpointHost{f.s("ipv4"), ipv6};
            endpoint.port = static_cast<uint16_t>(f.i("port"));
            endpoint.type = endpointType(f.i("type"));
            jbyteArray tag = f.bytes("peerTag");
            if (tag != nullptr && env->GetArrayLength(tag) >= 16) {
                env->GetByteArrayRegion(tag, 0, 16, reinterpret_cast<jbyte *>(endpoint.peerTag));
            }
            if (tag != nullptr) env->DeleteLocalRef(tag);
            descriptor.endpoints.push_back(std::move(endpoint));
        }
        env->DeleteLocalRef(e);
    }

    if (proxy != nullptr) {
        Fields p(env, proxy);
        descriptor.proxy = std::make_unique<Proxy>();
        descriptor.proxy->host = p.s("host");
        descriptor.proxy->port = static_cast<uint16_t>(p.i("port"));
        descriptor.proxy->login = p.s("login");
        descriptor.proxy->password = p.s("password");
    }

    auto *holder = new CallHolder;
    holder->persistentStatePath = toStdString(env, persistentStatePath);
    readPersistentState(holder->persistentStatePath, descriptor.persistentState);
    holder->instance = Meta::Create(descriptor.version, std::move(descriptor));
    if (!holder->instance) {
        delete holder;
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), "Unsupported call protocol version");
        return 0;
    }
    holder->camera = camera;
    holder->platformContext = context;
    holder->remoteSink = webrtc::JavaToNativeVideoSink(env, remoteSink);
    holder->instance->setIncomingVideoOutput(holder->remoteSink);
    holder->instance->setNetworkType(networkType(network));
    holder->instance->setRequestedVideoAspect(aspectRatio);
    return reinterpret_cast<jlong>(holder);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_receiveSignaling(JNIEnv *env, jobject self, jbyteArray data) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr || !h->instance) return;
    std::vector<uint8_t> bytes(static_cast<size_t>(env->GetArrayLength(data)));
    env->GetByteArrayRegion(data, 0, static_cast<jsize>(bytes.size()), reinterpret_cast<jbyte *>(bytes.data()));
    h->instance->receiveSignalingData(bytes);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_setMuted(JNIEnv *env, jobject self, jboolean muted) {
    CallHolder *h = holderOf(env, self);
    if (h != nullptr && h->instance) h->instance->setMuteMicrophone(muted == JNI_TRUE);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_setNetworkType(JNIEnv *env, jobject self, jint type) {
    CallHolder *h = holderOf(env, self);
    if (h != nullptr && h->instance) h->instance->setNetworkType(networkType(type));
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_setAudioOutputGainControl(JNIEnv *env, jobject self, jboolean enabled) {
    CallHolder *h = holderOf(env, self);
    if (h != nullptr && h->instance) h->instance->setAudioOutputGainControlEnabled(enabled == JNI_TRUE);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_setEchoCancellationStrength(JNIEnv *env, jobject self, jint strength) {
    CallHolder *h = holderOf(env, self);
    if (h != nullptr && h->instance) h->instance->setEchoCancellationStrength(strength);
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_lumina_calls_NativeCall_debugInfo(JNIEnv *env, jobject self) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr || !h->instance) return nullptr;
    return env->NewStringUTF(h->instance->getDebugInfo().c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_lumina_calls_NativeCall_lastError(JNIEnv *env, jobject self) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr || !h->instance) return nullptr;
    return env->NewStringUTF(h->instance->getLastError().c_str());
}

// Outgoing video: type 0 back camera, 1 front camera, 2 screen. Reuses the
// capturer of that kind if one exists.
extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_setupOutgoingVideo(JNIEnv *env, jobject self, jobject localSink, jint type) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr || !h->instance) return;
    const bool screen = type == 2;
    std::shared_ptr<VideoCaptureInterface> &capture = screen ? h->screen : h->camera;
    if (capture == nullptr) {
        capture = VideoCaptureInterface::Create(StaticThreads::getThreads(),
                                                screen ? "screen" : (type == 1 ? "front" : "back"), screen,
                                                std::make_shared<AndroidContext>(env, nullptr, nullptr, screen));
    }
    if (capture == nullptr) return;
    h->useScreen = screen;
    capture->setOutput(webrtc::JavaToNativeVideoSink(env, localSink));
    capture->setState(VideoState::Active);
    h->instance->setVideoCapture(capture);
}

// Uses a capturer created for the preview (createCapturer) as the camera.
extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_useCapturer(JNIEnv *env, jobject self, jlong capturer) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr || !h->instance || capturer == 0) return;
    h->camera = *reinterpret_cast<std::shared_ptr<VideoCaptureInterface> *>(capturer);
    h->camera->setState(VideoState::Active);
    h->useScreen = false;
    h->instance->setVideoCapture(h->camera);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_setVideoState(JNIEnv *env, jobject self, jint state) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr) return;
    auto capture = h->useScreen ? h->screen : h->camera;
    if (capture != nullptr) capture->setState(static_cast<VideoState>(state));
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_switchCamera(JNIEnv *env, jobject self, jboolean front) {
    CallHolder *h = holderOf(env, self);
    if (h != nullptr && h->camera != nullptr) h->camera->switchToDevice(front ? "front" : "back", false);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_stopVideo(JNIEnv *env, jobject self) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr || !h->instance) return;
    h->instance->setVideoCapture(nullptr);
    h->camera = nullptr;
    h->screen = nullptr;
}

// Ends the call; NativeCall.onStop(debugLog, ratingSuggested) follows on a
// tgcalls thread, after which the native side is gone.
extern "C" JNIEXPORT void JNICALL
Java_dev_lumina_calls_NativeCall_stop(JNIEnv *env, jobject self) {
    CallHolder *h = holderOf(env, self);
    if (h == nullptr || !h->instance) return;
    h->instance->stop([h](const FinalState &state) {
        savePersistentState(h->persistentStatePath, state.persistentState);
        jobject peer = peerOf(h->platformContext);
        withJni([&](JNIEnv *env) {
            jstring log = env->NewStringUTF(state.debugLog.c_str());
            env->CallVoidMethod(peer, env->GetMethodID(nativeCallClass, "onStop", "(Ljava/lang/String;Z)V"), log,
                                static_cast<jboolean>(state.isRatingSuggested));
            env->DeleteLocalRef(log);
        });
        delete h;
    });
}

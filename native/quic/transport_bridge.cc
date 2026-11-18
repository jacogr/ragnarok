// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Google QUICHE provider for transport_bridge.h. Nim owns UDP readiness, peer
// identity/admission policy and JAMNP-S framing. This provider owns only QUIC,
// TLS, copied endpoint metadata and opaque callback handles, on the caller's
// dispatcher thread. QUICHE sources are used without build or runtime patches.
//
// Packet writing and alarms never start a thread or perform a blocking wait.
// Each process turn limits packets, alarms and application callbacks. A blocked
// UDP callback leaves the datagram with QUICHE for a later turn. Stream handles
// outlive QUICHE streams until the final Nim close callback, avoiding deletion
// from inside read, reset or TLS callbacks. Admission refusal and connection
// close are likewise drained after packet processing returns. Destruction is a
// hard cut: it retires callbacks while their Nim owners still live, without
// waiting for a peer or trying to finish application transfers. Receive-window options
// set initial credit; QUICHE retains its bounded window tuning as the application
// consumes bytes. The bridge never drains a paused application reader.

#include "transport_bridge.h"

#include <algorithm>
#include <chrono>
#include <cerrno>
#include <cstring>
#include <fstream>
#include <limits>
#include <list>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "absl/log/initialize.h"
#include "absl/log/globals.h"
#include "absl/log/log.h"
#include "openssl/pem.h"
#include "openssl/pool.h"
#include "openssl/ssl.h"
#include "quiche/common/simple_buffer_allocator.h"
#include "quiche/quic/core/crypto/certificate_view.h"
#include "quiche/quic/core/crypto/client_proof_source.h"
#include "quiche/quic/core/crypto/proof_source_x509.h"
#include "quiche/quic/core/crypto/proof_verifier.h"
#include "quiche/quic/core/crypto/quic_crypto_client_config.h"
#include "quiche/quic/core/crypto/quic_crypto_server_config.h"
#include "quiche/quic/core/crypto/quic_random.h"
#include "quiche/quic/core/deterministic_connection_id_generator.h"
#include "quiche/quic/core/quic_alarm_factory.h"
#include "quiche/quic/core/quic_clock.h"
#include "quiche/quic/core/quic_crypto_client_stream.h"
#include "quiche/quic/core/quic_crypto_server_stream_base.h"
#include "quiche/quic/core/quic_dispatcher.h"
#include "quiche/quic/core/quic_packet_writer.h"
#include "quiche/quic/core/quic_session.h"
#include "quiche/quic/core/quic_stream.h"
#include "quiche/quic/core/quic_utils.h"
#include "quiche/quic/core/quic_version_manager.h"

using namespace quic;

namespace {
constexpr unsigned TurnBudget = 64;
constexpr size_t DatagramCapacity = 2048;
constexpr size_t WriteChunk = 4096;
constexpr unsigned MinWindow = 16384;
constexpr unsigned MaxWindow = 16777216;
class Session;
class Stream;
class Writer;
class Dispatcher;

// Stable application handles are retired after QUICHE has detached its pointer.
struct Handle {
    rq_transport *owner;
    Session *session;
    Stream *stream = nullptr;
    uint64_t id;
    int peer_slot = -1;
    uint64_t generation = 0;
    bool announced = false, closing = false, reset = false, reset_pending = false;
    bool want_read = true, want_write = false, fin_received = false, write_done = false;
};

// Both roles use the same steady clock; wall time is reserved for TLS metadata.
class Clock final : public QuicClock {
  public:
    QuicTime Now() const override {
        const auto value = std::chrono::duration_cast<std::chrono::microseconds>(
                               std::chrono::steady_clock::now().time_since_epoch())
                               .count();
        return CreateTimeFromMicroseconds(static_cast<uint64_t>(value) + 1);
    }
    QuicTime ApproximateNow() const override { return Now(); }
    QuicWallTime WallNow() const override {
        return QuicWallTime::FromUNIXSeconds(
            static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
                                      std::chrono::system_clock::now().time_since_epoch())
                                      .count()));
    }
};

class Alarm;
// QUICHE may destroy a factory before its last alarm. Each alarm retains this
// scheduler state independently; the endpoint clock outlives both.
struct Schedule {
    explicit Schedule(const Clock &value) : clock(value) {}
    const Clock &clock;
    std::multimap<int64_t, Alarm *> queue;
};
// Ordered cancellation removes retired alarms before their foreign owners die.
class Alarms final : public QuicAlarmFactory {
  public:
    explicit Alarms(const Clock &clock) : state_(std::make_shared<Schedule>(clock)) {}
    QuicAlarm *CreateAlarm(QuicAlarm::Delegate *delegate) override;
    QuicArenaScopedPtr<QuicAlarm> CreateAlarm(QuicArenaScopedPtr<QuicAlarm::Delegate> delegate,
                                              QuicConnectionArena *arena) override;
    void Process();
    int64_t Next() const {
        if (state_->queue.empty())
            return 10000;
        return std::max<int64_t>(0, state_->queue.begin()->first -
                                        state_->clock.Now().ToDebuggingValue());
    }

  private:
    std::shared_ptr<Schedule> state_;
};

// QUICHE retains deadline/delegate ownership; the bridge retains only an index.
class Alarm final : public QuicAlarm {
  public:
    Alarm(std::shared_ptr<Schedule> owner, QuicArenaScopedPtr<Delegate> delegate)
        : QuicAlarm(std::move(delegate)), owner_(std::move(owner)) {}
    ~Alarm() override { CancelImpl(); }
    void Run() {
        CancelImpl();
        Fire();
    }

  protected:
    void SetImpl() override {
        CancelImpl();
        entry_ = owner_->queue.emplace(deadline().ToDebuggingValue(), this);
        armed_ = true;
    }
    void CancelImpl() override {
        if (armed_) {
            owner_->queue.erase(entry_);
            armed_ = false;
        }
    }

  private:
    std::shared_ptr<Schedule> owner_;
    std::multimap<int64_t, Alarm *>::iterator entry_;
    bool armed_ = false;
};

QuicAlarm *Alarms::CreateAlarm(QuicAlarm::Delegate *delegate) {
    return new Alarm(state_, QuicArenaScopedPtr<QuicAlarm::Delegate>(delegate));
}
QuicArenaScopedPtr<QuicAlarm> Alarms::CreateAlarm(QuicArenaScopedPtr<QuicAlarm::Delegate> delegate,
                                                  QuicConnectionArena *arena) {
    if (arena)
        return arena->New<Alarm>(state_, std::move(delegate));
    return QuicArenaScopedPtr<QuicAlarm>(new Alarm(state_, std::move(delegate)));
}
void Alarms::Process() {
    for (unsigned count = 0; count < TurnBudget && !state_->queue.empty(); ++count) {
        if (state_->queue.begin()->first > state_->clock.Now().ToDebuggingValue())
            break;
        state_->queue.begin()->second->Run();
    }
}

// Buffer allocation and entropy remain QUICHE/BoringSSL primitives.
class Helper final : public QuicConnectionHelperInterface {
  public:
    explicit Helper(const Clock &clock) : clock_(clock) {}
    const QuicClock *GetClock() const override { return &clock_; }
    QuicRandom *GetRandomGenerator() override { return QuicRandom::GetInstance(); }
    quiche::QuicheBufferAllocator *GetStreamSendBufferAllocator() override {
        return quiche::SimpleBufferAllocator::Get();
    }

  private:
    const Clock &clock_;
};

// Legacy gQUIC CHLO is never accepted; this endpoint selects only RFCv1 TLS.
class CryptoHelper final : public QuicCryptoServerStreamBase::Helper {
    bool CanAcceptClientHello(const CryptoHandshakeMessage &, const QuicSocketAddress &,
                              const QuicSocketAddress &, const QuicSocketAddress &,
                              std::string *) const override {
        return false;
    }
};

// Read bounded credential files before publishing a transport owner.
std::string ReadFile(const char *path, size_t maximum) {
    if (!path)
        return {};
    std::ifstream file(path, std::ios::binary);
    std::string result;
    char bytes[4096];
    while (file && result.size() <= maximum) {
        file.read(bytes, sizeof(bytes));
        result.append(bytes, static_cast<size_t>(file.gcount()));
    }
    if (!file.eof() || result.size() > maximum)
        return {};
    return result;
}

// Preserve certificate-chain order; certificate acceptance remains the Nim callback.
std::vector<std::string> Certificates(const char *path) {
    const std::string pem = ReadFile(path, 65536);
    if (pem.empty())
        return {};
    bssl::UniquePtr<BIO> bio(BIO_new_mem_buf(pem.data(), static_cast<int>(pem.size())));
    std::vector<std::string> result;
    while (bio && result.size() < 8) {
        bssl::UniquePtr<X509> cert(PEM_read_bio_X509(bio.get(), nullptr, nullptr, nullptr));
        if (!cert)
            break;
        const int size = i2d_X509(cert.get(), nullptr);
        if (size <= 0 || size > 8192)
            return {};
        std::string der(static_cast<size_t>(size), '\0');
        auto *cursor = reinterpret_cast<uint8_t *>(der.data());
        if (i2d_X509(cert.get(), &cursor) != size)
            return {};
        result.push_back(std::move(der));
    }
    return result;
}

// Canonical copied IP metadata uses the same IPv4-mapped representation as Nim.
void CopyIp(const QuicIpAddress &ip, uint8_t bytes[16]) {
    std::memset(bytes, 0, 16);
    const std::string packed = ip.ToPackedString();
    if (packed.size() == 4) {
        bytes[10] = bytes[11] = 255;
        std::memcpy(bytes + 12, packed.data(), 4);
    } else if (packed.size() == 16) {
        std::memcpy(bytes, packed.data(), 16);
    }
}
QuicSocketAddress SocketAddress(const uint8_t bytes[16], uint16_t port, bool ipv6) {
    QuicIpAddress ip;
    ip.FromPackedString(reinterpret_cast<const char *>(bytes + (ipv6 ? 0 : 12)), ipv6 ? 16 : 4);
    return QuicSocketAddress(ip, port);
}

// One monotonic owner identity per endpoint, on the shared dispatcher thread.
uint64_t next_owner = 0;
bool logging_initialized = false;
} // namespace

// All callback records are scalar or owned by this stable endpoint. Session and
// stream destruction run before these records and before the caller's Nim owner.
struct rq_transport {
    rq_transport_options options{};
    Clock clock;
    QuicConfig config;
    DeterministicConnectionIdGenerator cid_generator{8};
    std::unique_ptr<QuicVersionManager> versions;
    std::unique_ptr<QuicCryptoServerConfig> server_crypto;
    std::unique_ptr<QuicCryptoClientConfig> client_crypto;
    std::unique_ptr<Helper> client_helper;
    std::unique_ptr<Alarms> client_alarms;
    std::unique_ptr<Writer> client_writer;
    std::unique_ptr<Dispatcher> dispatcher;
    std::unique_ptr<Session> client;
    Alarms *alarms = nullptr;
    Writer *writer = nullptr;
    QuicSocketAddress local;
    std::vector<std::string> alpns;
    std::vector<Session *> peers;
    std::vector<uint64_t> generations;
    std::vector<bool> peer_closing;
    std::set<Session *> sessions;
    std::list<std::unique_ptr<Handle>> handles;
    bool handshake_slots[RQ_HANDSHAKE_SLOTS]{};
    void *user = nullptr;
    rq_verify_cb verify = nullptr;
    rq_send_cb send = nullptr;
    rq_stream_cb stream = nullptr;
    rq_handshake_cb handshake = nullptr;
    rq_peer_cb peer = nullptr;
    rq_admission_cb admission = nullptr;
    uint64_t owner_id = 0, next_generation = 0;
    uint64_t active = 0, accepted = 0, closed = 0, peak = 0, authenticated = 0, rejected = 0;
    unsigned peer_capacity = RQ_PEER_SLOTS;
    int status = 0;
    bool multi = false, persistent = false, network_started = false, packets_seen = false;
    bool destroying = false, processing = false, failed = false;
    ~rq_transport();
    void Process();
    void Notify();
    bool Admit(Session *session);
    void Retire(Session *session);
};

namespace {
// Synchronous public verifier delegates identity policy without retaining DER spans.
class Verifier final : public ProofVerifier {
  public:
    explicit Verifier(rq_transport *owner) : owner_(owner) {}
    QuicAsyncStatus VerifyProof(const std::string &, uint16_t, const std::string &,
                                QuicTransportVersion, absl::string_view,
                                const std::vector<std::string> &, const std::string &,
                                const std::string &, const ProofVerifyContext *, std::string *,
                                std::unique_ptr<ProofVerifyDetails> *,
                                std::unique_ptr<ProofVerifierCallback>) override {
        return QUIC_FAILURE;
    }
    QuicAsyncStatus VerifyCertChain(const std::string &, uint16_t,
                                    const std::vector<absl::string_view> &certs,
                                    const std::string &, const std::string &,
                                    const ProofVerifyContext *, std::string *error,
                                    std::unique_ptr<ProofVerifyDetails> *, uint8_t *alert,
                                    std::unique_ptr<ProofVerifierCallback>) override {
        if (certs.empty() || certs.size() > 8 || certs[0].empty() || certs[0].size() > 8192 ||
            !owner_->verify(owner_->user, reinterpret_cast<const uint8_t *>(certs[0].data()),
                            certs[0].size())) {
            *error = "peer certificate refused";
            *alert = SSL_AD_CERTIFICATE_UNKNOWN;
            return QUIC_FAILURE;
        }
        return QUIC_SUCCESS;
    }
    std::unique_ptr<ProofVerifyContext> CreateDefaultContext() override { return nullptr; }

  private:
    rq_transport *owner_;
};

// The native sender consumes one borrowed datagram. Blocking also bounds one
// QUICHE write turn; SetWritable permits a later fair dispatcher turn to retry.
class Writer final : public QuicPacketWriter {
  public:
    explicit Writer(rq_transport *owner) : owner_(owner) {}
    WriteResult WritePacket(const char *bytes, size_t length, const QuicIpAddress &,
                            const QuicSocketAddress &peer, PerPacketOptions *,
                            const QuicPacketWriterParams &) override {
        if (length > DatagramCapacity)
            return WriteResult(WRITE_STATUS_MSG_TOO_BIG, EMSGSIZE);
        if (blocked_ || attempts_ >= TurnBudget) {
            blocked_ = true;
            return WriteResult(WRITE_STATUS_BLOCKED, EAGAIN);
        }
        uint8_t address[16];
        CopyIp(peer.host(), address);
        ++attempts_; // Hard errors also consume bounded work on shared and time-wait writers.
        const int error = owner_->send(owner_->user, reinterpret_cast<const uint8_t *>(bytes),
                                       length, address, peer.port());
        if (error == EAGAIN || error == EWOULDBLOCK || error == EINTR) {
            blocked_ = true;
            return WriteResult(WRITE_STATUS_BLOCKED, error);
        }
        // A destination or path failure belongs to the connection attempting this write.
        if (error == EMSGSIZE)
            return WriteResult(WRITE_STATUS_MSG_TOO_BIG, error);
        if (error != 0)
            return WriteResult(WRITE_STATUS_ERROR, error);
        return WriteResult(WRITE_STATUS_OK, static_cast<int>(length));
    }
    bool IsWriteBlocked() const override { return blocked_; }
    void SetWritable() override {
        blocked_ = false;
        attempts_ = 0;
    }
    std::optional<int> MessageTooBigErrorCode() const override { return EMSGSIZE; }
    QuicByteCount GetMaxPacketSize(const QuicSocketAddress &) const override { return 1472; }
    bool SupportsReleaseTime() const override { return false; }
    bool IsBatchMode() const override { return false; }
    bool SupportsEcn() const override { return false; }
    QuicPacketBuffer GetNextWriteLocation(const QuicIpAddress &,
                                          const QuicSocketAddress &) override {
        return {nullptr, nullptr};
    }
    WriteResult Flush() override { return WriteResult(WRITE_STATUS_OK, 0); }

  private:
    rq_transport *owner_;
    bool blocked_ = false;
    unsigned attempts_ = 0;
};

// No legacy proof or application state is used by this TLS-only client.
class ProofHandler final : public QuicCryptoClientStream::ProofHandler {
    void OnProofValid(const QuicCryptoClientConfig::CachedState &) override {}
    void OnProofVerifyDetailsAvailable(const ProofVerifyDetails &) override {}
    bool OnCertificateRequested(const std::vector<std::string> &) override { return false; }
};

// A session owns QUICHE state; its endpoint owns the separate native handles.
class Session final : public QuicSession {
  public:
    Session(rq_transport *owner, QuicConnection *connection, Visitor *visitor,
            QuicCompressedCertsCache *cache);
    ~Session() override;
    const QuicCryptoStream *GetCryptoStream() const override { return crypto_.get(); }
    QuicCryptoStream *GetMutableCryptoStream() override { return crypto_.get(); }
    std::vector<std::string> GetAlpnsToOffer() const override { return owner->alpns; }
    std::vector<absl::string_view>::const_iterator
    SelectAlpn(const std::vector<absl::string_view> &offered) const override {
        for (const auto &supported : owner->alpns) {
            auto match = std::find(offered.begin(), offered.end(), supported);
            if (match != offered.end())
                return match;
        }
        return offered.end();
    }
    void OnAlpnSelected(absl::string_view selected) override { protocol.assign(selected); }
    QuicSSLConfig GetSSLConfig() const override {
        QuicSSLConfig result;
        result.client_cert_mode =
            owner->options.server ? ClientCertMode::kRequire : ClientCertMode::kNone;
        result.early_data_enabled = false;
        result.disable_ticket_support = true;
        result.signing_algorithm_prefs =
            QuicSignatureAlgorithmVector{SSL_SIGN_ED25519, SSL_SIGN_ECDSA_SECP256R1_SHA256};
        return result;
    }
    bool ShouldKeepConnectionAlive() const override { return keepalive; }
    void OnTlsHandshakeComplete() override;
    void OnConnectionClosed(const QuicConnectionCloseFrame &frame,
                            ConnectionCloseSource source) override {
        if (keepalive_alarm_)
            keepalive_alarm_->Cancel();
        QuicSession::OnConnectionClosed(frame, source);
        owner->Retire(this);
    }
    void Start() {
        if (client_stream_)
            client_stream_->CryptoConnect();
    }
    bool QueueOpen() {
        if (!authenticated || close_pending ||
            pending_opens == std::numeric_limits<unsigned>::max())
            return false;
        ++pending_opens;
        return true;
    }
    void OpenPending();
    void HandshakeOutcome(bool success);
    void RequestClose() { close_pending = true; }
    std::string PeerDer() const;
    rq_transport *owner;
    std::string protocol;
    bool authenticated = false, close_pending = false, retired = false, keepalive = false;
    unsigned pending_opens = 0;
    int peer_slot = -1, handshake_slot = -1;
    bool handshake_settled = false, handshake_overflow = false;

  protected:
    QuicStream *CreateIncomingStream(QuicStreamId id) override;

  private:
    // This public QUICHE alarm uses the same bounded scheduler as transport alarms.
    // The session destroys it before releasing its connection context.
    class KeepaliveAlarm final : public QuicAlarm::DelegateWithContext {
      public:
        explicit KeepaliveAlarm(Session *session)
            : DelegateWithContext(session->connection()->context()), session_(session) {}
        void OnAlarm() override { session_->SendKeepalive(); }

      private:
        Session *session_;
    };
    void StartKeepalive();
    void SendKeepalive();
    std::unique_ptr<QuicAlarm> keepalive_alarm_;
    QuicTime::Delta keepalive_interval_ = QuicTime::Delta::Zero();
    std::unique_ptr<QuicCryptoStream> crypto_;
    QuicCryptoClientStream *client_stream_ = nullptr;
    ProofHandler proof_handler_;
    CryptoHelper crypto_helper_;
};

// Stream virtual hooks record readiness only. No Nim callback can recursively
// destroy a QUICHE object on its own call stack.
class Stream final : public QuicStream {
  public:
    Stream(QuicStreamId id, Session *session, Handle *handle)
        : QuicStream(id, session, false, BIDIRECTIONAL), handle_(handle) {
        handle_->stream = this;
        sequencer()->set_level_triggered(true);
    }
    ~Stream() override { Detach(); }
    QuicStreamSequencer *Reader() { return sequencer(); }
    void OnDataAvailable() override {}
    void OnCanWriteNewData() override {}
    void OnFinRead() override {
        if (handle_)
            handle_->fin_received = true;
        QuicStream::OnFinRead();
    }
    void OnStreamReset(const QuicRstStreamFrame &frame) override {
        if (handle_) {
            handle_->reset = true;
            handle_->reset_pending = true;
        }
        QuicStream::OnStreamReset(frame);
    }
    bool OnStopSending(QuicResetStreamError error) override {
        if (handle_) {
            handle_->reset = true;
            handle_->reset_pending = true;
        }
        return QuicStream::OnStopSending(error);
    }
    void OnClose() override {
        Detach();
        QuicStream::OnClose();
    }

  private:
    void Detach() {
        if (handle_) {
            handle_->stream = nullptr;
            handle_->closing = true;
            handle_ = nullptr;
        }
    }
    Handle *handle_;
};

// Construct TLS and transport state before publishing a live session to the endpoint.
Session::Session(rq_transport *transport, QuicConnection *connection, Visitor *visitor,
                 QuicCompressedCertsCache *cache)
    : QuicSession(connection, visitor, transport->config, {ParsedQuicVersion::RFCv1()}, 0),
      owner(transport) {
    keepalive = owner->options.idle_seconds
                    ? owner->options.keepalive != 0
                    : (!owner->options.server || owner->options.profile >= 4);
    if (owner->options.server) {
        crypto_ =
            CreateCryptoServerStream(owner->server_crypto.get(), cache, this, &crypto_helper_);
        if (owner->handshake) {
            for (unsigned i = 0; i < RQ_HANDSHAKE_SLOTS; ++i) {
                if (!owner->handshake_slots[i]) {
                    owner->handshake_slots[i] = true;
                    handshake_slot = static_cast<int>(i);
                    break;
                }
            }
            uint8_t bytes[16];
            CopyIp(connection->peer_address().host(), bytes);
            handshake_overflow = handshake_slot < 0;
            owner->handshake(owner->user,
                             handshake_overflow ? RQ_HANDSHAKE_SLOTS
                                                : static_cast<unsigned>(handshake_slot),
                             handshake_overflow ? RQ_HANDSHAKE_DROPPED : RQ_HANDSHAKE_STARTED,
                             bytes, connection->peer_address().port(), nullptr, 0);
        }
    } else {
        auto stream = std::make_unique<QuicCryptoClientStream>(
            QuicServerId("", connection->peer_address().port()), this, nullptr,
            owner->client_crypto.get(), &proof_handler_, false);
        client_stream_ = stream.get();
        crypto_ = std::move(stream);
    }
    Initialize();
    owner->sessions.insert(this);
}

// Retire observer slots and detach native handles before destroying TLS and the connection.
Session::~Session() {
    keepalive_alarm_.reset();
    if (!retired)
        owner->Retire(this);
    if (!handshake_settled)
        HandshakeOutcome(false);
    if (handshake_slot >= 0)
        owner->handshake_slots[handshake_slot] = false;
    for (auto &handle : owner->handles) {
        if (handle->session == this) {
            handle->session = nullptr;
            handle->stream = nullptr;
            handle->closing = true;
        }
    }
    owner->sessions.erase(this);
    crypto_.reset();
    DeleteConnection();
}

// Copy the authenticated leaf from this exact public TLS stream; never correlate by address.
std::string Session::PeerDer() const {
    const SSL *ssl = crypto_->GetSsl();
    const auto *chain = ssl ? SSL_get0_peer_certificates(ssl) : nullptr;
    if (!chain || sk_CRYPTO_BUFFER_num(chain) == 0 || sk_CRYPTO_BUFFER_num(chain) > 8)
        return {};
    const auto *leaf = sk_CRYPTO_BUFFER_value(chain, 0);
    const size_t size = CRYPTO_BUFFER_len(leaf);
    if (!size || size > 8192)
        return {};
    return std::string(reinterpret_cast<const char *>(CRYPTO_BUFFER_data(leaf)), size);
}

// Settle each tracked handshake once, even when TLS fails or the endpoint is destroyed.
void Session::HandshakeOutcome(bool success) {
    if (handshake_settled)
        return;
    handshake_settled = true;
    if (!owner->handshake || handshake_slot < 0)
        return;
    const std::string der = success ? PeerDer() : std::string{};
    owner->handshake(owner->user, static_cast<unsigned>(handshake_slot),
                     success ? RQ_HANDSHAKE_SUCCEEDED : RQ_HANDSHAKE_FAILED, nullptr, 0,
                     der.empty() ? nullptr : reinterpret_cast<const uint8_t *>(der.data()),
                     der.size());
}

// Finish QUICHE TLS bookkeeping before admission; refusals close on a later safe turn.
void Session::OnTlsHandshakeComplete() {
    QuicSession::OnTlsHandshakeComplete();
    HandshakeOutcome(true);
    if (owner->options.server) {
        if (!owner->Admit(this)) {
            close_pending = true;
            return;
        }
    } else {
        authenticated = true;
        owner->status = 1;
        ++owner->authenticated;
    }
    StartKeepalive();
}

// Use negotiated idle credit for both roles. The stock keepalive deadline is client-only;
// retransmittable-on-wire probes back off and have a lifetime cap, so neither alone
// implements the caller's persistent server policy. Public alarms and SendPing do.
void Session::StartKeepalive() {
    if (!keepalive || !connection()->connected())
        return;
    auto timeout = config()->IdleNetworkTimeout();
    if (timeout.IsInfinite() || timeout <= QuicTime::Delta::Zero())
        return;
    // QUICHE expires clients one second before the negotiated idle timeout when
    // it exceeds one second. Probe halfway through that shorter window in both roles.
    if (timeout > QuicTime::Delta::FromSeconds(1))
        timeout = timeout - QuicTime::Delta::FromSeconds(1);
    keepalive_interval_ =
        QuicTime::Delta::FromMicroseconds(std::max<int64_t>(1, timeout.ToMicroseconds() / 2));
    keepalive_alarm_.reset(owner->alarms->CreateAlarm(new KeepaliveAlarm(this)));
    keepalive_alarm_->Set(owner->clock.Now() + keepalive_interval_);
}

// Send one probe per due alarm without catch-up bursts. QUICHE owns packet creation,
// congestion control and retransmission; the shared writer retains its per-turn budget.
void Session::SendKeepalive() {
    if (retired || close_pending || !connection()->connected())
        return;
    connection()->SendPing();
    if (!retired && !close_pending && connection()->connected())
        keepalive_alarm_->Set(owner->clock.Now() + keepalive_interval_);
}

// Allocate a stable ABI handle before activating the stream; application notification is deferred.
QuicStream *Session::CreateIncomingStream(QuicStreamId id) {
    auto handle = std::make_unique<Handle>();
    handle->owner = owner;
    handle->session = this;
    handle->id = id;
    auto stream = std::make_unique<Stream>(id, this, handle.get());
    auto *result = stream.get();
    owner->handles.push_back(std::move(handle));
    ActivateStream(std::move(stream));
    return result;
}

// Create only credited outgoing streams; cancellation clears intents which have no stream yet.
void Session::OpenPending() {
    unsigned count = 0;
    while (authenticated && !close_pending && pending_opens && count++ < TurnBudget &&
           CanOpenNextOutgoingBidirectionalStream()) {
        --pending_opens;
        CreateIncomingStream(GetNextOutgoingBidirectionalStreamId());
    }
}

// Dispatcher ALPN parsing remains transport configuration, not JAM policy.
class Versions final : public QuicVersionManager {
  public:
    explicit Versions(rq_transport *owner)
        : QuicVersionManager({ParsedQuicVersion::RFCv1()}), owner_(owner) {
        RefilterSupportedVersions();
    }
    void Refresh() { RefilterSupportedVersions(); }

  protected:
    void RefilterSupportedVersions() override {
        QuicVersionManager::RefilterSupportedVersions();
        for (const auto &alpn : owner_->alpns)
            AddCustomAlpn(alpn);
    }

  private:
    rq_transport *owner_;
};

// QUICHE owns CID routing, buffering and time-wait. Admission is separately
// bounded after authentication; a listener failure never selects another peer.
class Dispatcher final : public QuicDispatcher {
  public:
    Dispatcher(rq_transport *owner, std::unique_ptr<Helper> helper, std::unique_ptr<Alarms> alarms)
        : QuicDispatcher(&owner->config, owner->server_crypto.get(), owner->versions.get(),
                         std::move(helper), std::make_unique<CryptoHelper>(), std::move(alarms), 8,
                         owner->cid_generator),
          owner_(owner) {}

  protected:
    QuicPacketFate ValidityChecksOnFullChlo(const ReceivedPacketInfo &,
                                            const ParsedClientHello &) const override {
        return owner_->sessions.size() >= owner_->peer_capacity + RQ_HANDSHAKE_SLOTS ? kFateDrop
                                                                                     : kFateProcess;
    }
    std::unique_ptr<QuicSession>
    CreateQuicSession(QuicConnectionId id, const QuicSocketAddress &local,
                      const QuicSocketAddress &peer, absl::string_view,
                      const ParsedQuicVersion &version, const ParsedClientHello &,
                      ConnectionIdGeneratorInterface &generator) override {
        auto connection = std::make_unique<QuicConnection>(
            id, local, peer, helper(), alarm_factory(), writer(), false, Perspective::IS_SERVER,
            ParsedQuicVersionVector{version}, generator);
        auto session =
            std::make_unique<Session>(owner_, connection.get(), this, compressed_certs_cache());
        connection.release();
        return session;
    }

  private:
    rq_transport *owner_;
};

// Trust only a currently retained authenticated admission in the queried owner.
Session *Peer(rq_transport *owner, const rq_peer_ref *peer) {
    if (!owner || owner->destroying || !peer || peer->owner != owner->owner_id ||
        !peer->generation || peer->slot >= owner->peer_capacity ||
        peer->generation != owner->generations[peer->slot] || owner->peer_closing[peer->slot])
        return nullptr;
    auto *session = owner->peers[peer->slot];
    return session && session->authenticated && session->connection()->connected() ? session
                                                                                   : nullptr;
}
} // namespace

// Apply Nim admission before retaining a peer slot or exposing any application stream.
bool rq_transport::Admit(Session *session) {
    unsigned slot = 0;
    while (slot < peer_capacity && peers[slot])
        ++slot;
    const std::string der = session->PeerDer();
    bool allowed = slot < peer_capacity && (multi || !active) && next_generation != UINT64_MAX;
    if (allowed && admission)
        allowed = !der.empty() && !session->protocol.empty() &&
                  admission(user, slot, reinterpret_cast<const uint8_t *>(der.data()), der.size(),
                            reinterpret_cast<const uint8_t *>(session->protocol.data()),
                            session->protocol.size()) == 1;
    if (!allowed) {
        if (slot == peer_capacity || (!multi && active))
            ++rejected;
        if (handshake) {
            uint8_t address[16];
            CopyIp(session->connection()->peer_address().host(), address);
            handshake(user, RQ_HANDSHAKE_SLOTS, RQ_ADMISSION_REFUSED, address,
                      session->connection()->peer_address().port(), nullptr, 0);
        }
        return false;
    }
    session->authenticated = true;
    session->peer_slot = static_cast<int>(slot);
    peers[slot] = session;
    generations[slot] = ++next_generation;
    ++active;
    ++accepted;
    ++authenticated;
    peak = std::max(peak, active);
    status = 1;
    if (peer)
        peer(user, slot, RQ_PEER_ACCEPTED, reinterpret_cast<const uint8_t *>(der.data()),
             der.size());
    return true;
}

// Mark a generation closing; its final peer notification waits for stream-handle retirement.
void rq_transport::Retire(Session *session) {
    if (session->retired)
        return;
    session->retired = true;
    session->pending_opens = 0;
    if (!session->handshake_settled)
        session->HandshakeOutcome(false);
    if (session->peer_slot >= 0)
        peer_closing[session->peer_slot] = true;
    if (!options.server && !session->authenticated)
        status = -1;
}

// Rotate ready streams; reserve a separate budget so busy readers cannot starve peer retirement.
void rq_transport::Notify() {
    unsigned budget = TurnBudget;
    size_t remaining = handles.size();
    while (remaining-- && budget && !handles.empty()) {
        // Rotate stable heap handles so one permanently ready peer cannot
        // consume every callback turn ahead of later peers.
        auto storage = std::move(handles.front());
        handles.pop_front();
        Handle *handle = storage.get();
        if (!handle->announced && handle->stream && handle->session &&
            handle->session->authenticated) {
            handle->peer_slot = handle->session->peer_slot;
            handle->generation = generations[handle->peer_slot];
            handle->announced = true;
            --budget;
            stream(user, handle, 0);
        }
        if (budget && handle->announced && handle->reset_pending) {
            handle->reset_pending = false;
            --budget;
            stream(user, handle, 4);
        }
        if (budget && !handle->reset && handle->announced && handle->stream && handle->want_read &&
            (handle->stream->Reader()->HasBytesToRead() || handle->stream->Reader()->IsClosed())) {
            --budget;
            stream(user, handle, 1);
        }
        if (budget && !handle->reset && handle->announced && handle->stream && handle->want_write &&
            handle->stream->CanWriteNewData()) {
            --budget;
            stream(user, handle, 2);
        }
        if (handle->closing && (!handle->announced || budget)) {
            if (handle->announced) {
                --budget;
                stream(user, handle, 3);
            }
        } else {
            handles.push_back(std::move(storage));
        }
    }
    unsigned retire_budget = TurnBudget;
    for (unsigned slot = 0; slot < peer_capacity; ++slot) {
        if (peer_closing[slot]) {
            if (!retire_budget)
                break;
            bool pending = false;
            for (const auto &handle : handles) {
                if (handle->peer_slot == static_cast<int>(slot) &&
                    handle->generation == generations[slot] && handle->announced) {
                    pending = true;
                    break;
                }
            }
            if (pending)
                continue;
            --retire_budget;
            if (options.server && peer && !destroying) {
                peer(user, slot, RQ_PEER_CLOSED, nullptr, 0);
            }
            peers[slot] = nullptr;
            peer_closing[slot] = false;
            if (active)
                --active;
            ++closed;
            if (!multi && persistent)
                status = 0;
        }
    }
}

// Retry UDP writes, run due alarms and drain deferred lifecycle work without a blocking wait.
void rq_transport::Process() {
    if (processing || destroying)
        return;
    processing = true;
    network_started = true;
    writer->SetWritable();
    if (dispatcher) {
        dispatcher->ProcessBufferedChlos(8);
        dispatcher->OnCanWrite();
    }
    if (client && client->connection()->connected() && !writer->IsWriteBlocked())
        client->connection()->OnCanWrite();
    alarms->Process();
    const std::vector<Session *> snapshot(sessions.begin(), sessions.end());
    for (auto *session : snapshot) {
        if (!sessions.count(session))
            continue;
        if (session->close_pending && session->connection()->connected())
            session->connection()->CloseConnection(
                QUIC_NO_ERROR, "local close",
                ConnectionCloseBehavior::SEND_CONNECTION_CLOSE_PACKET);
        else if (session->connection()->connected())
            session->OpenPending();
    }
    Notify();
    if (client && client->retired && client->peer_slot >= 0 && !peers[client->peer_slot])
        client.reset();
    processing = false;
}

// Hard-cut live sessions while all Nim callback owners are still valid; do not fabricate peer loss.
rq_transport::~rq_transport() {
    destroying = true;
    const std::vector<Session *> snapshot(sessions.begin(), sessions.end());
    for (auto *session : snapshot) {
        if (session->connection()->connected())
            session->connection()->CloseConnection(QUIC_NO_ERROR, "endpoint shutdown",
                                                   ConnectionCloseBehavior::SILENT_CLOSE);
    }
    dispatcher.reset();
    client.reset();
    // Native final callbacks have no per-turn budget during explicit teardown.
    for (auto &handle : handles) {
        if (handle->announced)
            stream(user, handle.get(), 3);
    }
    handles.clear();
}

extern "C" {
// Validate scalar startup policy and credentials before publishing an endpoint owner.
rq_transport *rq_transport_new_config(const rq_transport_options *options, uint16_t port,
                                      const char *certificate, const char *key, const char *alpn,
                                      void *user, rq_verify_cb verify, rq_send_cb send,
                                      rq_stream_cb stream) {
    if (!options || !certificate || !key || !alpn || !verify || !send || !stream ||
        options->server < 0 || options->server > 1 || options->ipv6 < 0 || options->ipv6 > 1 ||
        options->multi < 0 || options->multi > 1 || (options->multi && !options->server) ||
        options->profile < 0 || options->profile > 5 ||
        ((options->profile == 2 || options->profile == 5) && !options->server) ||
        options->idle_seconds > 600 || options->keepalive > 1 ||
        (!options->idle_seconds && options->keepalive) ||
        (options->stream_window &&
         (options->stream_window < MinWindow || options->stream_window > MaxWindow)) ||
        (options->connection_window &&
         (options->connection_window < MinWindow || options->connection_window > MaxWindow)) ||
        (options->stream_window && options->connection_window &&
         options->stream_window > options->connection_window))
        return nullptr;
    const size_t length = std::strlen(alpn);
    if (!length || length > 255 || next_owner == UINT64_MAX)
        return nullptr;
    try {
        if (!logging_initialized) {
            absl::InitializeLog();
            absl::SetMinLogLevel(absl::LogSeverityAtLeast::kWarning);
            logging_initialized = true;
        }
        auto owner = std::make_unique<rq_transport>();
        owner->options = *options;
        owner->multi = options->multi || options->profile == 2 || options->profile == 5;
        owner->persistent = options->profile >= 3;
        owner->user = user;
        owner->verify = verify;
        owner->send = send;
        owner->stream = stream;
        owner->owner_id = ++next_owner;
        owner->peers.resize(RQ_PEER_SLOTS, nullptr);
        owner->generations.resize(RQ_PEER_SLOTS, 0);
        owner->peer_closing.resize(RQ_PEER_SLOTS, false);
        owner->alpns.emplace_back(alpn, length);
        uint8_t loopback[16]{};
        loopback[15] = 1;
        if (!options->ipv6) {
            loopback[10] = loopback[11] = 255;
            loopback[12] = 127;
        }
        owner->local = SocketAddress(loopback, port, options->ipv6 != 0);
        unsigned window =
            options->stream_window ? options->stream_window : (options->profile ? 65536 : 1048576);
        unsigned connection_window =
            options->connection_window ? options->connection_window : 1048576;
        owner->config.SetInitialStreamFlowControlWindowToSend(window);
        owner->config.SetInitialMaxStreamDataBytesIncomingBidirectionalToSend(window);
        owner->config.SetInitialMaxStreamDataBytesOutgoingBidirectionalToSend(window);
        owner->config.SetInitialMaxStreamDataBytesUnidirectionalToSend(window);
        owner->config.SetInitialSessionFlowControlWindowToSend(connection_window);
        owner->config.SetMaxBidirectionalStreamsToSend(
            (owner->multi || options->profile >= 4) ? 8 : 100);
        owner->config.SetMaxUnidirectionalStreamsToSend(0);
        unsigned idle = options->idle_seconds ? options->idle_seconds
                                              : ((owner->multi || options->profile >= 4) ? 2 : 30);
        const auto idle_timeout = QuicTime::Delta::FromSeconds(idle);
        owner->config.SetIdleNetworkTimeout(idle_timeout);
        // The endpoint's idle policy also bounds startup. QUICHE otherwise uses
        // a separate five-second initial idle timeout, closing normal peers
        // before their application deadline during a delayed first flight.
        owner->config.set_max_idle_time_before_crypto_handshake(idle_timeout);
        owner->config.set_max_time_before_crypto_handshake(
            std::max(owner->config.max_time_before_crypto_handshake(), idle_timeout));
        const bool missing = std::strcmp(certificate, "-") == 0 && std::strcmp(key, "-") == 0;
        auto chain = missing ? std::vector<std::string>{} : Certificates(certificate);
        std::unique_ptr<CertificatePrivateKey> private_key;
        if (!missing) {
            std::istringstream input(ReadFile(key, 16384));
            private_key = CertificatePrivateKey::LoadPemFromStream(&input);
            if (chain.empty() || !private_key)
                return nullptr;
        }
        if (options->server) {
            if (missing)
                return nullptr;
            auto proof =
                ProofSourceX509::Create(quiche::QuicheReferenceCountedPointer<ProofSource::Chain>(
                                            new ProofSource::Chain(chain)),
                                        std::move(*private_key));
            if (!proof)
                return nullptr;
            uint8_t secret[32];
            QuicRandom::GetInstance()->RandBytes(secret, sizeof(secret));
            owner->server_crypto = std::make_unique<QuicCryptoServerConfig>(
                absl::string_view(reinterpret_cast<const char *>(secret), sizeof(secret)),
                QuicRandom::GetInstance(), std::move(proof), KeyExchangeSource::Default(),
                std::make_unique<Verifier>(owner.get()));
            if (!SSL_CTX_set1_sigalgs_list(owner->server_crypto->ssl_ctx(),
                                           "ed25519:ecdsa_secp256r1_sha256"))
                return nullptr;
            owner->versions = std::make_unique<Versions>(owner.get());
            auto alarms = std::make_unique<Alarms>(owner->clock);
            owner->alarms = alarms.get();
            owner->dispatcher = std::make_unique<Dispatcher>(
                owner.get(), std::make_unique<Helper>(owner->clock), std::move(alarms));
            owner->writer = new Writer(owner.get());
            owner->dispatcher->InitializeWithWriter(owner->writer);
        } else {
            owner->client_crypto =
                std::make_unique<QuicCryptoClientConfig>(std::make_unique<Verifier>(owner.get()));
            owner->client_crypto->set_tls_signature_algorithms("ed25519:ecdsa_secp256r1_sha256");
            if (!missing) {
                auto proof = std::make_unique<DefaultClientProofSource>();
                if (!proof->AddCertAndKey({"*"},
                                          quiche::QuicheReferenceCountedPointer<ProofSource::Chain>(
                                              new ProofSource::Chain(chain)),
                                          std::move(*private_key)))
                    return nullptr;
                owner->client_crypto->set_proof_source(std::move(proof));
            }
            owner->client_helper = std::make_unique<Helper>(owner->clock);
            owner->client_alarms = std::make_unique<Alarms>(owner->clock);
            owner->alarms = owner->client_alarms.get();
            owner->client_writer = std::make_unique<Writer>(owner.get());
            owner->writer = owner->client_writer.get();
        }
        return owner.release();
    } catch (const std::exception &error) {
        ABSL_LOG(ERROR) << "QUIC endpoint setup failed: " << error.what();
        return nullptr;
    }
}

// Preserve the IPv4 profile factory through the common validated constructor.
rq_transport *rq_transport_new(int profile, int server, uint16_t port, const char *cert,
                               const char *key, const char *alpn, void *user, rq_verify_cb verify,
                               rq_send_cb send, rq_stream_cb stream) {
    const rq_transport_options options{profile, server, 0, profile == 2 || profile == 5,
                                       0,       0,      0, 0};
    return rq_transport_new_config(&options, port, cert, key, alpn, user, verify, send, stream);
}
// Preserve supported IPv6 profiles without a second implementation.
rq_transport *rq_transport_new_ipv6_profile(int profile, int server, uint16_t port,
                                            const char *cert, const char *key, const char *alpn,
                                            void *user, rq_verify_cb verify, rq_send_cb send,
                                            rq_stream_cb stream) {
    if (profile < 3 || profile > 5 || (profile == 5 && !server))
        return nullptr;
    const rq_transport_options options{profile, server, 1, profile == 5, 0, 0, 0, 0};
    return rq_transport_new_config(&options, port, cert, key, alpn, user, verify, send, stream);
}
// Construct the default persistent IPv6 endpoint.
rq_transport *rq_transport_new_ipv6(int server, uint16_t port, const char *cert, const char *key,
                                    const char *alpn, void *user, rq_verify_cb verify,
                                    rq_send_cb send, rq_stream_cb stream) {
    return rq_transport_new_ipv6_profile(3, server, port, cert, key, alpn, user, verify, send,
                                         stream);
}
// Copy the bounded ALPN list before the first network turn; refuse partial configuration.
int rq_server_alpns(rq_transport *owner, const uint8_t *wire, size_t length) try {
    if (!owner || !owner->options.server || owner->network_started || !wire || !length ||
        length > 512)
        return 0;
    std::vector<std::string> values;
    for (size_t offset = 0; offset < length;) {
        size_t size = wire[offset++];
        if (!size || size > length - offset || values.size() >= 8)
            return 0;
        values.emplace_back(reinterpret_cast<const char *>(wire + offset), size);
        offset += size;
    }
    owner->alpns.swap(values);
    static_cast<Versions *>(owner->versions.get())->Refresh();
    return 1;
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_server_alpns failed: " << error.what();
    return 0;
}
// Allocate all replacement peer tables before publishing startup capacity.
int rq_set_peer_capacity(rq_transport *owner, unsigned maximum, int multiple) try {
    if (!owner || !owner->options.server || owner->network_started || owner->peer ||
        owner->admission || !maximum || maximum > RQ_MAX_PEER_SLOTS || multiple < 0 || multiple > 1)
        return 0;
    std::vector<Session *> peers(maximum, nullptr);
    std::vector<uint64_t> generations(maximum, 0);
    std::vector<bool> closing(maximum, false);
    owner->peers.swap(peers);
    owner->generations.swap(generations);
    owner->peer_closing.swap(closing);
    owner->peer_capacity = maximum;
    if (multiple)
        owner->multi = true;
    return 1;
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_set_peer_capacity failed: " << error.what();
    return 0;
}
// Install the fixed handshake observer once, before network processing.
int rq_observe_handshakes(rq_transport *owner, unsigned slots, rq_handshake_cb callback) {
    if (!owner || !owner->options.server || owner->network_started || owner->handshake ||
        !callback || slots != RQ_HANDSHAKE_SLOTS)
        return 0;
    owner->handshake = callback;
    return 1;
}
// Install an observer whose native slot count agrees with its Nim owner.
int rq_observe_peers(rq_transport *owner, unsigned slots, rq_peer_cb callback) {
    if (!owner || !owner->options.server || owner->network_started || owner->peer || !callback ||
        slots != owner->peer_capacity)
        return 0;
    owner->peer = callback;
    return 1;
}
// Install synchronous authenticated admission before any peer can be retained.
int rq_admit_peers(rq_transport *owner, unsigned slots, rq_admission_cb callback) {
    if (!owner || !owner->options.server || owner->network_started || owner->admission ||
        !callback || slots != owner->peer_capacity)
        return 0;
    owner->admission = callback;
    return 1;
}
// Copy the bound UDP address before creating a QUIC connection.
int rq_bind_address(rq_transport *owner, const uint8_t *address) {
    if (!owner || !address || owner->network_started)
        return 0;
    owner->local = SocketAddress(address, owner->local.port(), owner->options.ipv6 != 0);
    return 1;
}
// Create a client session and generation; let the public TLS stream start the handshake.
int rq_connect_address(rq_transport *owner, const uint8_t *address, uint16_t port) try {
    if (!owner || !address || !port || owner->options.server || owner->client || owner->active ||
        owner->next_generation == UINT64_MAX)
        return 0;
    owner->network_started = true;
    owner->status = 0;
    uint8_t id[8];
    QuicRandom::GetInstance()->RandBytes(id, sizeof(id));
    auto connection = std::make_unique<QuicConnection>(
        QuicConnectionId(reinterpret_cast<const char *>(id), sizeof(id)), owner->local,
        SocketAddress(address, port, owner->options.ipv6 != 0), owner->client_helper.get(),
        owner->alarms, owner->writer, false, Perspective::IS_CLIENT,
        ParsedQuicVersionVector{ParsedQuicVersion::RFCv1()}, owner->cid_generator);
    owner->client = std::make_unique<Session>(owner, connection.get(), nullptr, nullptr);
    connection.release();
    owner->client->peer_slot = 0;
    owner->peers[0] = owner->client.get();
    owner->generations[0] = ++owner->next_generation;
    ++owner->active;
    ++owner->accepted;
    owner->peak = std::max(owner->peak, owner->active);
    owner->client->Start();
    return 1;
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_connect_address failed: " << error.what();
    return 0;
}
// Dial the profile family loopback endpoint through the common address path.
int rq_connect(rq_transport *owner, uint16_t port) {
    if (!owner)
        return 0;
    uint8_t address[16]{};
    address[15] = 1;
    if (!owner->options.ipv6) {
        address[10] = address[11] = 255;
        address[12] = 127;
    }
    return rq_connect_address(owner, address, port);
}
// Borrow one bounded datagram for synchronous QUICHE packet processing.
int rq_packet_in_address(rq_transport *owner, const uint8_t *bytes, size_t length,
                         const uint8_t *source, uint16_t port) try {
    if (!owner || !bytes || !source || !length || length > DatagramCapacity)
        return -1;
    owner->network_started = owner->packets_seen = true;
    const QuicReceivedPacket packet(reinterpret_cast<const char *>(bytes), length,
                                    owner->clock.Now(), false);
    const auto remote = SocketAddress(source, port, owner->options.ipv6 != 0);
    if (owner->dispatcher)
        owner->dispatcher->ProcessPacket(owner->local, remote, packet);
    else if (owner->client && owner->client->connection()->connected())
        owner->client->connection()->ProcessUdpPacket(owner->local, remote, packet);
    return 0;
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_packet_in_address failed: " << error.what();
    return -1;
}
// Supply the profile loopback source for the legacy packet entry point.
int rq_packet_in(rq_transport *owner, const uint8_t *bytes, size_t length, uint16_t port) {
    if (!owner)
        return -1;
    uint8_t address[16]{};
    address[15] = 1;
    if (!owner->options.ipv6) {
        address[10] = address[11] = 255;
        address[12] = 127;
    }
    return rq_packet_in_address(owner, bytes, length, address, port);
}
// Advance a bounded dispatcher turn and translate native exceptions at the C boundary.
void rq_process(rq_transport *owner) try {
    if (owner)
        owner->Process();
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_process failed: " << error.what();
    if (owner) {
        owner->processing = false;
        owner->status = -1;
    }
}
// Return a nonnegative monotonic alarm delay in microseconds.
int64_t rq_next_tick(rq_transport *owner) {
    return owner && owner->alarms ? owner->alarms->Next() : 10000;
}
// Read the endpoint readiness or failure state without borrowing a session.
int rq_status(rq_transport *owner) {
    return owner ? owner->status : -1;
}
// Hard-close QUICHE before final callbacks release borrowed Nim owners.
void rq_transport_free(rq_transport *owner) {
    delete owner;
}
// Queue a close so callbacks cannot destroy a connection on its own stack.
void rq_disconnect(rq_transport *owner) {
    if (owner && owner->client)
        owner->client->RequestClose();
    else if (owner && !owner->multi)
        for (unsigned slot = 0; slot < owner->peer_capacity; ++slot)
            if (owner->peers[slot] && !owner->peer_closing[slot])
                owner->peers[slot]->RequestClose();
}
// Read cumulative endpoint counters without exposing foreign connection pointers.
uint64_t rq_peer_metric(rq_transport *owner, int metric) {
    if (!owner)
        return 0;
    switch (metric) {
    case 0:
        return owner->active;
    case 1:
        return owner->accepted;
    case 2:
        return owner->closed;
    case 3:
        return owner->peak;
    case 4:
        return owner->authenticated;
    case 5:
        return owner->rejected;
    default:
        return 0;
    }
}
// Copy only an authenticated live owner, generation and slot reference.
int rq_peer_at(rq_transport *owner, unsigned slot, rq_peer_ref *result) {
    if (!owner || !result || slot >= owner->peer_capacity || !owner->peers[slot] ||
        owner->peer_closing[slot] || !owner->peers[slot]->authenticated || owner->destroying)
        return 0;
    *result = {owner->owner_id, owner->generations[slot], slot};
    return 1;
}
// Associate a live stream with its current authenticated admission.
int rq_stream_peer(rq_transport *owner, void *pointer, rq_peer_ref *result) {
    auto *handle = static_cast<Handle *>(pointer);
    if (!owner || !handle || handle->owner != owner || !handle->session ||
        handle->session->peer_slot < 0)
        return 0;
    return rq_peer_at(owner, static_cast<unsigned>(handle->session->peer_slot), result);
}
// Reject stale or foreign peer references before using a session pointer.
int rq_peer_live(rq_transport *owner, const rq_peer_ref *peer) {
    return Peer(owner, peer) != nullptr;
}
// Queue a targeted stream open until the peer grants outgoing stream credit.
int rq_open_peer(rq_transport *owner, const rq_peer_ref *peer) {
    auto *session = Peer(owner, peer);
    return session && session->QueueOpen();
}
// Defer a targeted close until the next safe processing turn.
int rq_close_peer(rq_transport *owner, const rq_peer_ref *peer) {
    auto *session = Peer(owner, peer);
    if (!session)
        return 0;
    session->RequestClose();
    return 1;
}
// Cancel queued opens without affecting streams already delivered to Nim.
int rq_cancel_peer_opens(rq_transport *owner, const rq_peer_ref *peer) {
    auto *session = Peer(owner, peer);
    if (!session)
        return 0;
    session->pending_opens = 0;
    return 1;
}
// Queue an open on the default authenticated session.
void rq_open_stream(rq_transport *owner) {
    if (!owner || owner->status != 1)
        return;
    for (unsigned slot = 0; slot < owner->peer_capacity; ++slot)
        if (owner->peers[slot] && !owner->peer_closing[slot] && owner->peers[slot]->authenticated) {
            owner->peers[slot]->QueueOpen();
            break;
        }
}
// Copy available bytes; distinguish blocked reads, FIN and reset with the existing ABI.
int64_t rq_stream_read(void *pointer, uint8_t *bytes, size_t length) try {
    auto *handle = static_cast<Handle *>(pointer);
    if (!handle || handle->reset)
        return -1;
    if (!handle->stream)
        return handle->fin_received ? 0 : -1;
    iovec destination{bytes, length};
    const size_t size = handle->stream->Reader()->Readv(&destination, 1);
    if (size)
        return static_cast<int64_t>(size);
    return handle->fin_received || (handle->stream && handle->stream->Reader()->IsClosed()) ? 0
                                                                                            : -2;
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_stream_read failed: " << error.what();
    return -1;
}
// Accept at most one bounded chunk while QUICHE has send-buffer capacity.
int64_t rq_stream_write(void *pointer, const uint8_t *bytes, size_t length) try {
    auto *handle = static_cast<Handle *>(pointer);
    if (!handle || !handle->stream || handle->reset || handle->write_done)
        return -1;
    if (!handle->stream->CanWriteNewData())
        return -2;
    const size_t accepted = std::min(length, WriteChunk);
    handle->stream->WriteOrBufferData(
        absl::string_view(reinterpret_cast<const char *>(bytes), accepted), false, nullptr);
    return static_cast<int64_t>(accepted);
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_stream_write failed: " << error.what();
    return -1;
}
// Control level-triggered application read callbacks.
void rq_stream_want_read(void *pointer, int want) {
    if (pointer)
        static_cast<Handle *>(pointer)->want_read = want != 0;
}
// Control level-triggered application write callbacks.
void rq_stream_want_write(void *pointer, int want) {
    if (pointer)
        static_cast<Handle *>(pointer)->want_write = want != 0;
}
// Queue FIN once after all application bytes accepted by this stream.
void rq_stream_fin(void *pointer) try {
    auto *handle = static_cast<Handle *>(pointer);
    if (!handle || !handle->stream || handle->write_done || handle->reset)
        return;
    handle->write_done = true;
    handle->want_write = false;
    handle->stream->WriteOrBufferData({}, true, nullptr);
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_stream_fin failed: " << error.what();
}
// Reset both stream directions with the protocol application error code zero.
void rq_stream_abort(void *pointer) try {
    auto *handle = static_cast<Handle *>(pointer);
    if (!handle)
        return;
    handle->want_read = handle->want_write = false;
    handle->reset = true;
    if (handle->stream)
        handle->stream->ResetWithError(QuicResetStreamError::FromIetf(uint64_t{0}));
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_stream_abort failed: " << error.what();
}
// Explicitly retire the application read half after its framing policy succeeds.
void rq_stream_read_done(void *pointer) try {
    auto *handle = static_cast<Handle *>(pointer);
    if (!handle)
        return;
    handle->want_read = false;
    if (handle->stream)
        handle->stream->StopReading();
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_stream_read_done failed: " << error.what();
}
// Offer pending data to the shared nonblocking packet writer.
int rq_stream_flush(void *pointer) try {
    auto *handle = static_cast<Handle *>(pointer);
    if (!handle || !handle->stream || !handle->session)
        return -1;
    auto *connection = handle->session->connection();
    if (connection->connected() && !connection->writer()->IsWriteBlocked())
        connection->OnCanWrite();
    return 0;
} catch (const std::exception &error) {
    ABSL_LOG(ERROR) << "rq_stream_flush failed: " << error.what();
    return -1;
}
// Compare current session identity while both native handles remain live.
int rq_stream_same_peer(void *a, void *b) {
    auto *first = static_cast<Handle *>(a);
    auto *second = static_cast<Handle *>(b);
    return first && second && first->session && first->session == second->session;
}
// Read the stable wire stream identifier while the native handle is retained.
uint64_t rq_stream_id(void *pointer) {
    return pointer ? static_cast<Handle *>(pointer)->id : 0;
}
// Determine the initiator from the RFCv1 stream identifier and endpoint role.
int rq_stream_local(rq_transport *owner, void *pointer) {
    return owner && pointer &&
           (static_cast<Handle *>(pointer)->id & 1) == static_cast<unsigned>(owner->options.server);
}
} // extern "C"

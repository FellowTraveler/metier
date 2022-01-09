// Copyright (c) 2019-2022 The Open-Transactions developers
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#pragma once

#include "otwrap.hpp"  // IWYU pragma: associated

#include <opentxs/opentxs.hpp>
#include <QDebug>
#include <QDir>
#include <QGuiApplication>
#include <QStandardPaths>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <future>
#include <map>
#include <mutex>
#include <set>
#include <string>

#include "models/accountlist.hpp"
#include "models/seedlang.hpp"
#include "models/seedsize.hpp"
#include "models/seedtype.hpp"
#include "otwrap/notary.hpp"
#include "otwrap/passwordcallback.hpp"
#include "rpc/rpc.hpp"
#include "util/claim.hpp"
#include "util/convertblockchain.hpp"
#include "util/scopeguard.hpp"

namespace ot = opentxs;

static const auto ot_args_ = ot::Options{};

auto make_args(QGuiApplication& parent, int& argc, char** argv) noexcept
    -> const ot::Options&;
auto make_args(QGuiApplication& parent, int& argc, char** argv) noexcept
    -> const ot::Options&
{
    parent.setOrganizationDomain(METIER_APP_DOMAIN);
    parent.setApplicationName(METIER_APP_NAME);
    auto path =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);

    if (path.isEmpty()) { qFatal("Invalid app data folder"); }

    auto folder = QDir{path.append("/opentxs/")};
    const auto absolute = folder.absolutePath();

    if (folder.mkpath(absolute)) {
        qDebug() << QString("Setting opentxs data folder to: %1").arg(absolute);
    } else {
        qFatal("Failed to create opentxs data folder");
    }

    auto& args = const_cast<ot::Options&>(ot_args_);
    args.ParseCommandLine(argc, argv);
    args.SetHome(absolute.toStdString().c_str());
    args.SetBlockchainStorageLevel(1);

    for (const auto* endpoint : metier::seed_server_endpoints_) {
        args.AddBlockchainSyncServer(endpoint);
    }

    args.SetQtRootObject(&parent);
    args.SetIpv4ConnectionMode(ot::Options::ConnectionMode::on);
    args.SetIpv6ConnectionMode(ot::Options::ConnectionMode::automatic);

    return ot_args_;
}

auto ready(bool complete = false) noexcept -> std::shared_future<void>;
auto ready(bool complete) noexcept -> std::shared_future<void>
{
    static auto mutex = std::mutex{};
    auto lock = std::lock_guard<std::mutex>{mutex};
    static auto promise = std::promise<void>{};
    static auto future = std::shared_future<void>{promise.get_future()};

    if (complete) { promise.set_value(); }

    return future;
}

namespace metier
{
constexpr auto seed_id_key{"seedid"};
constexpr auto nym_id_key{"nymid"};

namespace zmq = opentxs::network::zeromq;

struct OTWrap::Imp {
private:
    OTWrap& parent_;
    QGuiApplication& qt_parent_;

public:
    struct EnabledChains {
        using Vector = std::set<ot::blockchain::Type>;

        auto count() const noexcept
        {
            ot::Lock lock(lock_);

            return enabled_.size();
        }
        auto get() const noexcept
        {
            auto output = BlockchainList{};
            auto copy = Vector{};
            {
                ot::Lock lock(lock_);
                copy = enabled_;
            }
            std::transform(
                std::begin(copy), std::end(copy), std::back_inserter(output), [
                ](const auto& in) -> auto { return static_cast<int>(in); });

            return output;
        }

        auto add(ot::blockchain::Type chain) noexcept
        {
            ot::Lock lock(lock_);
            enabled_.emplace(chain);
        }
        auto remove(ot::blockchain::Type chain) noexcept
        {
            ot::Lock lock(lock_);
            enabled_.erase(chain);
        }
        auto set(Vector&& in) noexcept
        {
            ot::Lock lock(lock_);
            std::swap(enabled_, in);
        }

        EnabledChains(Vector&& in) noexcept
            : enabled_(std::move(in))
        {
        }

    private:
        mutable std::mutex lock_{};
        Vector enabled_{};
    };

    using SeedLanguageMap =
        std::map<ot::crypto::SeedStyle, std::unique_ptr<model::SeedLanguage>>;
    using SeedSizeMap =
        std::map<ot::crypto::SeedStyle, std::unique_ptr<model::SeedSize>>;

    PasswordCallback callback_;
    opentxs::PasswordCaller caller_;
    const opentxs::api::Context& ot_;
    const ot::OTZMQListenCallback rpc_cb_;
    ot::OTZMQRouterSocket rpc_socket_;
    const opentxs::api::session::Client& api_;
    const ot::OTNotaryID introduction_notary_id_;
    const ot::OTNotaryID messaging_notary_id_;
    const std::string seed_id_;
    const int longest_seed_word_;
    const SeedLanguageMap seed_language_;
    const SeedSizeMap seed_size_;
    mutable std::mutex lock_;
    mutable std::atomic_bool have_nym_;
    mutable std::promise<ot::OTNymID> nym_id_promise_;
    std::shared_future<ot::OTNymID> nym_id_value_;
    EnabledChains enabled_chains_;
    std::unique_ptr<model::SeedType> seed_type_;
    std::unique_ptr<model::AccountList> account_list_;
    std::unique_ptr<model::BlockchainChooser> mainnet_model_;

    template <typename OutputType, typename InputType>
    static auto transform(const InputType& data) noexcept -> OutputType
    {
        auto output = OutputType{};
        std::transform(
            data.begin(), data.end(), std::back_inserter(output), [
            ](const auto& in) -> auto {
                return std::make_pair(in.second, static_cast<int>(in.first));
            });
        std::sort(output.begin(), output.end());

        return output;
    }

    auto check_chains(int count) const noexcept -> void
    {
        validateBlockchains();
        emit parent_.chainsChanged(count);
    }

    auto enableDefaultChain() const noexcept -> bool
    {
#ifdef METIER_DEFAULT_BLOCKCHAIN
        return api_.Network().Blockchain().Enable(
            util::convert(METIER_DEFAULT_BLOCKCHAIN));
#else
        return false;
#endif
    }
    auto needNym() const noexcept
    {
        ready().get();

        return 0 == api_.Wallet().LocalNymCount();
    }
    auto needSeed() const noexcept
    {
        ready().get();

        return api_.Storage().SeedList().empty();
    }
    auto rpc(zmq::Message&& in) const noexcept -> void
    {
        const auto body = in.Body();

        if (1u != body.size()) { qInfo() << "Invalid message"; }

        const auto& cmd = body.at(0);
        auto out = zmq::reply_to_message(std::move(in));

        if (ot_.RPC(cmd.Bytes(), out.AppendBytes())) {
            rpc_socket_->Send(std::move(out));
        }
    }
    auto validateBlockchains() const noexcept -> bool
    {
        ready().get();
        ot::Lock lock(lock_);

        for (const auto chain : api_.Network().Blockchain().EnabledChains()) {
            if (false == make_accounts(chain)) { return false; }
        }

        check_registration();

        return true;
    }
    auto validateNym() const noexcept
    {
        ready().get();
        ot::Lock lock(lock_);
        auto nymID = api_.Factory().NymID();
        auto postcondition = ScopeGuard{[&] {
            if (nymID->empty()) { return; }

            {
                auto& pointer =
                    const_cast<std::unique_ptr<model::AccountList>&>(
                        account_list_);

                if (!pointer) {
                    pointer = std::make_unique<model::AccountList>(
                        api_.UI().AccountListQt(nymID));

                    assert(pointer);

                    Ownership::Claim(pointer.get());
                }

                nym_id_promise_.set_value(std::move(nymID));
                have_nym_ = true;
            }
        }};

        if (have_nym_) { return true; }

        auto id = ot::String::Factory();
        bool notUsed{false};
        api_.Config().Check_str(
            ot::String::Factory(
                QGuiApplication::applicationName().toStdString()),
            ot::String::Factory(nym_id_key),
            id,
            notUsed);

        if (id->Exists()) {
            nymID->SetString(id->Get());

            return true;
        }

        const auto nymList = api_.Wallet().LocalNyms();

        if (1 == nymList.size()) {
            const auto& firstID = *nymList.begin();
            id->Set(firstID->str().c_str());
            const auto config = api_.Config().Set_str(
                ot::String::Factory(
                    QGuiApplication::applicationName().toStdString()),
                ot::String::Factory(nym_id_key),
                id,
                notUsed);

            if (false == config) { return false; }

            if (false == api_.Config().Save()) { return false; }

            nymID->SetString(id->Get());

            return true;
        }

        return false;
    }
    auto validateSeed() const noexcept
    {
        ready().get();
        ot::Lock lock(lock_);

        if (false == seed_id_.empty()) { return true; }

        auto& seed = const_cast<std::string&>(seed_id_);
        auto id = ot::String::Factory();
        bool notUsed{false};
        api_.Config().Check_str(
            ot::String::Factory(
                QGuiApplication::applicationName().toStdString()),
            ot::String::Factory(seed_id_key),
            id,
            notUsed);

        if (id->Exists()) {
            seed = id->Get();

            return true;
        }

        const auto seedList = api_.Storage().SeedList();

        if (1 == seedList.size()) {
            const auto& firstID = seedList.begin()->first;
            id->Set(firstID.c_str());
            const auto config = api_.Config().Set_str(
                ot::String::Factory(
                    QGuiApplication::applicationName().toStdString()),
                ot::String::Factory(seed_id_key),
                id,
                notUsed);

            if (false == config) { return false; }

            if (false == api_.Config().Save()) { return false; }

            seed = id->Get();

            return true;
        }

        return false;
    }

    auto accountActivityModel(const int chain) noexcept -> AccountActivity*
    {
        ready().get();
        const auto& nymID = nym_id_value_.get().get();
        const auto& account =
            api_.Crypto().Blockchain().Account(nymID, util::convert(chain));

        return api_.UI().AccountActivityQt(nymID, account.AccountID());
    }
    auto accountActivityModel(const ot::Identifier& id) noexcept
        -> AccountActivity*
    {
        ready().get();
        const auto& nymID = nym_id_value_.get().get();

        return api_.UI().AccountActivityQt(nymID, id);
    }
    auto accountStatusModel(const int chain) noexcept
        -> ot::ui::BlockchainAccountStatusQt*
    {
        ready().get();
        const auto& nymID = nym_id_value_.get().get();

        return api_.UI().BlockchainAccountStatusQt(nymID, util::convert(chain));
    }
    auto activityThreadModel(const ot::Identifier& id) noexcept
        -> ActivityThread*
    {
        ready().get();
        const auto& nymID = nym_id_value_.get().get();

        return api_.UI().ActivityThreadQt(nymID, id);
    }
    auto chain_is_disabled(int chain) noexcept -> void
    {
        enabled_chains_.remove(static_cast<ot::blockchain::Type>(chain));
    }
    auto chain_is_enabled(int chain) noexcept -> void
    {
        enabled_chains_.add(static_cast<ot::blockchain::Type>(chain));
    }
    auto contactListModel() noexcept -> ContactList*
    {
        ready().get();
        const auto& nymID = nym_id_value_.get().get();

        return api_.UI().ContactListQt(nymID);
    }
    auto createNym(QString alias) noexcept -> void
    {
        ready().get();
        ot::Lock lock(lock_);
        const auto reason =
            api_.Factory().PasswordPrompt("Generate a new Metier identity");

        assert(false == seed_id_.empty());

        const auto pNym =
            api_.Wallet().Nym({seed_id_, 0}, reason, alias.toStdString());

        if (!pNym) { return; }

        const auto& nym = *pNym;
        bool notUsed{false};
        const auto config = api_.Config().Set_str(
            ot::String::Factory(
                QGuiApplication::applicationName().toStdString()),
            ot::String::Factory(nym_id_key),
            ot::String::Factory(nym.ID().str()),
            notUsed);

        if (false == config) { return; }
        if (false == api_.Config().Save()) { return; }

        nym_id_promise_.set_value(nym.ID());
        have_nym_ = true;
    }
    auto createNewSeed(
        const int type,
        const int lang,
        const int strength) noexcept -> QStringList
    {
        ready().get();
        ot::Lock lock(lock_);
        auto success{false};
        auto& id = const_cast<std::string&>(seed_id_);
        auto postcondition = ScopeGuard{[&]() {
            if (false == success) { id = {}; }
        }};
        const auto& seeds = api_.Crypto().Seed();

        assert(id.empty());
        assert(seeds.DefaultSeed().empty());

        const auto invalid = [](const int in) -> auto
        {
            return (0 > in) || (std::numeric_limits<std::uint8_t>::max() < in);
        };

        if (invalid(type) || invalid(lang) || invalid(strength)) { return {}; }

        auto reason =
            api_.Factory().PasswordPrompt("Generate a new Metier wallet seed");
        id = seeds.NewSeed(
            static_cast<ot::crypto::SeedStyle>(static_cast<std::uint8_t>(type)),
            static_cast<ot::crypto::Language>(static_cast<std::uint8_t>(lang)),
            static_cast<ot::crypto::SeedStrength>(
                static_cast<std::size_t>(strength)),
            reason);

        if (id.empty()) { return {}; }

        auto notUsed{false};
        const auto config = api_.Config().Set_str(
            ot::String::Factory(
                QGuiApplication::applicationName().toStdString()),
            ot::String::Factory(seed_id_key),
            ot::String::Factory(id),
            notUsed);

        if (false == config) { return {}; }
        if (false == api_.Config().Save()) { return {}; }

        success = true;
        const auto words = QString{seeds.Words(id, reason).c_str()};

        return words.split(' ', Qt::SkipEmptyParts);
    }
    auto getRecoveryWords() -> QStringList
    {
        ready().get();
        ot::Lock lock(lock_);
        const auto& seeds = api_.Crypto().Seed();
        const auto reason =
            api_.Factory().PasswordPrompt("Loading recovery words for backup");
        const auto words = QString{seeds.Words(seed_id_, reason).c_str()};

        return words.split(' ', Qt::SkipEmptyParts);
    }
    auto importSeed(
        int type,
        int lang,
        const QString& input,
        const QString& password) -> void
    {
        ready().get();
        ot::Lock lock(lock_);
        auto success{false};
        auto& id = const_cast<std::string&>(seed_id_);
        auto postcondition = ScopeGuard{[&]() {
            if (false == success) { id = {}; }
        }};
        const auto& seeds = api_.Crypto().Seed();

        assert(id.empty());
        assert(seeds.DefaultSeed().empty());

        auto reason =
            api_.Factory().PasswordPrompt("Import a Metier wallet seed");
        const auto words = api_.Factory().SecretFromText(input.toStdString());
        const auto passphrase =
            api_.Factory().SecretFromText(password.toStdString());
        id = seeds.ImportSeed(
            words,
            passphrase,
            static_cast<ot::crypto::SeedStyle>(static_cast<std::uint8_t>(type)),
            static_cast<ot::crypto::Language>(static_cast<std::uint8_t>(lang)),
            reason);

        if (id.empty()) { return; }

        auto notUsed{false};
        const auto config = api_.Config().Set_str(
            ot::String::Factory(
                QGuiApplication::applicationName().toStdString()),
            ot::String::Factory(seed_id_key),
            ot::String::Factory(id),
            notUsed);

        if (false == config) { return; }
        if (false == api_.Config().Save()) { return; }

        success = true;
    }
    auto profileModel() noexcept -> ot::ui::ProfileQt*
    {
        ready().get();
        const auto& nymID = nym_id_value_.get().get();

        return api_.UI().ProfileQt(nymID);
    }
    auto seedLanguageModel(const int type) -> model::SeedLanguage*
    {
        ready().get();

        try {

            return seed_language_.at(static_cast<ot::crypto::SeedStyle>(type))
                .get();
        } catch (...) {

            return nullptr;
        }
    }
    auto seedSizeModel(const int type) -> model::SeedSize*
    {
        ready().get();

        try {

            return seed_size_.at(static_cast<ot::crypto::SeedStyle>(type))
                .get();
        } catch (...) {

            return nullptr;
        }
    }
    auto seedWordValidator(const int type, const int lang)
        -> const opentxs::ui::SeedValidator*
    {
        ready().get();
        const auto style =
            static_cast<ot::crypto::SeedStyle>(static_cast<std::uint8_t>(type));
        const auto language =
            static_cast<ot::crypto::Language>(static_cast<std::uint8_t>(lang));

        return api_.UI().SeedValidator(style, language);
    }
    auto wordCount(const int type, const int strength) -> int
    {
        ready().get();
        const auto output = api_.Crypto().Seed().WordCount(
            static_cast<ot::crypto::SeedStyle>(static_cast<std::uint8_t>(type)),
            static_cast<ot::crypto::SeedStrength>(
                static_cast<std::size_t>(strength)));

        return static_cast<int>(output);
    }

    Imp(QGuiApplication& parent, App& app, OTWrap& me, int& argc, char** argv)
        : parent_(me)
        , qt_parent_(parent)
        , callback_(app)
        , caller_()
        , ot_(ot::InitContext(
              make_args(parent, argc, argv),
              [this]() -> auto {
                  caller_.SetCallback(&callback_);
                  return &caller_;
              }()))
        , rpc_cb_(zmq::ListenCallback::Factory(
              [this](auto&& in) { rpc(std::move(in)); }))
        , rpc_socket_([this] {
            using Dir = zmq::socket::Socket::Direction;
            auto out = ot_.ZMQ().RouterSocket(rpc_cb_, Dir::Bind);
            const auto endpoint = rpc_endpoint();

            if (out->Start(endpoint)) {
                qInfo() << QString("RPC socket opened at: %1")
                               .arg(endpoint.c_str());
            } else {
                qFatal("Failed to start RPC socket");
            }

            return out;
        }())
        , api_(ot_.StartClientSession(ot_args_, 0))
        , introduction_notary_id_([&] {
            try {
                const auto contract =
                    import_contract(introduction_notary_contract_);
                auto out = api_.Factory().ServerID();
                out->Assign(contract->ID()->Bytes());

                return out;
            } catch (...) {

                return api_.Factory().ServerID();
            }
        }())
        , messaging_notary_id_([&] {
            try {
                const auto contract =
                    import_contract(messaging_notary_contract_);
                auto out = api_.Factory().ServerID();
                out->Assign(contract->ID()->Bytes());

                return out;
            } catch (...) {

                return api_.Factory().ServerID();
            }
        }())
        , seed_id_()
        , longest_seed_word_([&]() -> auto {
            const auto& api = api_.Crypto().Seed();
            auto output = int{};
            const auto types = api.AllowedSeedTypes();

            for (const auto& [style, description] : types) {
                const auto langs = api.AllowedLanguages(style);

                for (const auto& [lang, name] : langs) {
                    output = std::max(
                        output, static_cast<int>(api.LongestWord(style, lang)));
                }
            }

            return output;
        }())
        , seed_language_([this] {
            auto out = SeedLanguageMap{};
            const auto& api = api_.Crypto().Seed();
            const auto types = api.AllowedSeedTypes();

            for (const auto& [style, description] : types) {
                auto [it, added] = out.try_emplace(
                    style,
                    std::make_unique<model::SeedLanguage>(
                        &qt_parent_,
                        transform<model::SeedLanguage::Data>(
                            api_.Crypto().Seed().AllowedLanguages(style))));
                auto& pModel = it->second;

                assert(pModel);

                Ownership::Claim(pModel.get());
            }

            return out;
        }())
        , seed_size_([this] {
            auto out = SeedSizeMap{};
            const auto& api = api_.Crypto().Seed();
            const auto types = api.AllowedSeedTypes();

            for (const auto& [style, description] : types) {
                auto [it, added] = out.try_emplace(
                    style,
                    std::make_unique<model::SeedSize>(
                        &qt_parent_,
                        transform<model::SeedSize::Data>(
                            api_.Crypto().Seed().AllowedSeedStrength(style))));
                auto& pModel = it->second;

                assert(pModel);

                Ownership::Claim(pModel.get());
            }

            return out;
        }())
        , lock_()
        , have_nym_(false)
        , nym_id_promise_()
        , nym_id_value_(nym_id_promise_.get_future())
        , enabled_chains_([&] {
            auto* full =
                api_.UI().BlockchainSelectionQt(ot::ui::Blockchains::All);
            auto* main =
                api_.UI().BlockchainSelectionQt(ot::ui::Blockchains::Main);
            auto* test =
                api_.UI().BlockchainSelectionQt(ot::ui::Blockchains::Test);

            assert(nullptr != full);
            assert(nullptr != main);
            assert(nullptr != test);

            using Model = ot::ui::BlockchainSelectionQt;
            connect(
                full, &Model::enabledChanged, &parent_, &OTWrap::checkChains);
            connect(
                full, &Model::chainEnabled, &parent_, &OTWrap::chainIsEnabled);
            connect(
                full,
                &Model::chainDisabled,
                &parent_,
                &OTWrap::chainIsDisabled);

            return api_.Network().Blockchain().EnabledChains();
        }())
        , seed_type_(std::make_unique<model::SeedType>(
              &parent,
              transform<model::SeedType::Data>(
                  api_.Crypto().Seed().AllowedSeedTypes())))
        , account_list_()
        , mainnet_model_(std::make_unique<model::BlockchainChooser>(
              api_.UI().BlockchainSelectionQt(ot::ui::Blockchains::Main)))
    {
        assert(seed_type_);

        Ownership::Claim(mainnet_model_.get());
        Ownership::Claim(seed_type_.get());
        check_introduction_notary();
        ready(true);
    }

    ~Imp() { rpc_socket_->Close(); }

private:

    auto check_introduction_notary() const noexcept -> void
    {
        if (introduction_notary_id_->empty()) { return; }

        api_.OTX().SetIntroductionServer(
            api_.Wallet().Server(introduction_notary_id_));
    }

    auto check_registration() const noexcept -> bool
    {
        if (false == have_nym_) { return false; }
        if (introduction_notary_id_->empty()) { return false; }
        if (messaging_notary_id_->empty()) { return false; }

        const auto& nymID = nym_id_value_.get().get();

        {
            const auto reason = api_.Factory().PasswordPrompt(
                "Checking or updating public contact data");
            auto nym = api_.Wallet().mutable_Nym(nymID, reason);
            const auto notary = nym.PreferredOTServer();

            if (notary.empty()) {
                nym.AddPreferredOTServer(
                    messaging_notary_id_->str(), true, reason);
            }
        }

        const auto isRegistered = [&](const auto& server) {
            auto context = api_.Wallet().ServerContext(nymID, server);

            if (context) { return (0 != context->Request()); }

            return false;
        };
        const auto check = [&](const auto& server) {
            if (false == isRegistered(server)) {
                const auto [id, future] = api_.OTX().RegisterNym(nymID, server);

                if (0 > id) { return false; }
            }

            return true;
        };

        auto output = check(messaging_notary_id_);
        output &= check(introduction_notary_id_);

        return output;
    }

    auto import_contract(const char* text) const noexcept(false)
        -> ot::OTServerContract
    {
        if ((nullptr == text) || (0 == std::strlen(text))) {
            throw std::runtime_error{"invalid contract"};
        }

        const auto armored = [&] {
            auto out = api_.Factory().Armored();
            out->LoadFromString(ot::String::Factory(text));

            return out;
        }();
        const auto proto = api_.Factory().Data(armored);

        return api_.Wallet().Server(proto->Bytes());
    }

    auto make_accounts(const ot::blockchain::Type chain) const noexcept -> bool
    {
        using Chain = ot::blockchain::Type;
        using Protocol = ot::blockchain::crypto::HDProtocol;
        const auto& nymID = nym_id_value_.get().get();

        const auto want = [&] {
            auto out = std::set<Protocol>{};
            out.emplace(Protocol::BIP_44);

            if (ot::blockchain::HasSegwit(chain)) {
                out.emplace(Protocol::BIP_49);
                out.emplace(Protocol::BIP_84);
            }

            return out;
        }();
        const auto have = [&] {
            auto out = std::set<Protocol>{};
            const auto& account =
                api_.Crypto().Blockchain().Account(nymID, chain);

            for (const auto& hd : account.GetHD()) {
                out.emplace(hd.Standard());
            }

            return out;
        }();
        const auto need = [&] {
            auto out = std::vector<Protocol>{};
            std::set_difference(
                want.begin(),
                want.end(),
                have.begin(),
                have.end(),
                std::back_inserter(out));

            return out;
        }();

        for (const auto& type : need) {
            const auto prompt = std::string{"Creating a new "} +
                                ot::blockchain::DisplayString(chain) +
                                " account";
            const auto reason = api_.Factory().PasswordPrompt(prompt);
            const auto id = [&] {
                if ((Chain::PKT == chain) && (Protocol::BIP_84 == type)) {
                    // TODO only do this if the primary seed is a pktwallet type

                    return api_.Crypto().Blockchain().NewHDSubaccount(
                        nymID, type, Chain::Bitcoin, chain, reason);
                } else {

                    return api_.Crypto().Blockchain().NewHDSubaccount(
                        nymID, type, chain, reason);
                }
            }();

            if (id->empty()) { return false; }
        }

        return true;
    }
};
}  // namespace metier

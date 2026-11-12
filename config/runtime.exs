import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/riddlr start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :riddlr, RiddlrWeb.Endpoint, server: true
end

config :riddlr, RiddlrWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :riddlr, Riddlr.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      raise "environment variable PHX_HOST is missing. Set it to the site's domain."

  # The info page (contact, texts, privacy), linked from emails, texts and
  # the text consent copy.
  config :riddlr, info_url: "https://www.#{host}/info"

  config :riddlr, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :riddlr, RiddlrWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: ["https://#{host}", "https://www.#{host}"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :riddlr, RiddlrWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :riddlr, RiddlrWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Phone storage
  #
  # CLOAK_KEY: base64 of 32 random bytes (`openssl rand -base64 32`). It
  # encrypts phone numbers. To rotate, set CLOAK_KEY to the new key and
  # CLOAK_KEY_OLD to the old one, deploy, run `mix cloak.migrate.ecto`, then
  # drop CLOAK_KEY_OLD. CLOAK_KEY_TAG (required) names the key; bump it with
  # each new key and move the old tag to CLOAK_KEY_OLD_TAG, so stored values
  # name the key that made them. Each stored value finds its key by tag, so
  # data written before tags were required needs "AES.GCM.V1", as CLOAK_KEY_TAG
  # or as CLOAK_KEY_OLD_TAG. With any other tag the app boots but cannot read
  # those numbers.
  #
  # PHONE_HMAC_KEY: a separate secret for the phone blind index. Changing it
  # orphans every stored hash, so do not rotate it without a re-hash.
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise "environment variable CLOAK_KEY is missing. Generate with: openssl rand -base64 32"

  cloak_key_tag =
    System.get_env("CLOAK_KEY_TAG") ||
      raise "environment variable CLOAK_KEY_TAG is missing. For example: AES.GCM.V1"

  old_cloak_keys =
    case System.get_env("CLOAK_KEY_OLD") do
      nil ->
        []

      key ->
        tag =
          System.get_env("CLOAK_KEY_OLD_TAG") ||
            raise "CLOAK_KEY_OLD is set, so CLOAK_KEY_OLD_TAG must be too: the old key's tag"

        [{tag, key}]
    end

  config :riddlr, Riddlr.Vault, keys: [{cloak_key_tag, cloak_key} | old_cloak_keys]

  config :riddlr, Riddlr.Hashed.HMAC,
    secret:
      System.get_env("PHONE_HMAC_KEY") ||
        raise(
          "environment variable PHONE_HMAC_KEY is missing. Generate with: openssl rand -base64 32"
        )

  # ## SMS
  #
  # SMS_ADAPTER names a module under Riddlr.SMS. With none set, the phone UI
  # stays hidden.
  #
  # "AWS" sends through AWS End User Messaging SMS. It needs AWS_REGION (picks
  # the endpoint), SMS_ORIGINATION_ID (the number, in E.164, or its ID that
  # texts come from) and both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY,
  # which sign each request. Email does not use any of these.
  if sms_adapter = System.get_env("SMS_ADAPTER") do
    adapter = Module.concat(Riddlr.SMS, sms_adapter)

    # Local logs each text, codes included; Test sends to a test process.
    if adapter in [Riddlr.SMS.Local, Riddlr.SMS.Test] do
      raise "SMS_ADAPTER=#{sms_adapter} is for dev and test only"
    end

    if adapter == Riddlr.SMS.AWS do
      fetch_env! = fn name ->
        case String.trim(System.get_env(name, "")) do
          "" ->
            raise "environment variable #{name} is missing or blank. SMS_ADAPTER=AWS needs it."

          value ->
            value
        end
      end

      config :riddlr, Riddlr.SMS.AWS,
        region: fetch_env!.("AWS_REGION"),
        access_key_id: fetch_env!.("AWS_ACCESS_KEY_ID"),
        secret_access_key: fetch_env!.("AWS_SECRET_ACCESS_KEY"),
        origination_identity: fetch_env!.("SMS_ORIGINATION_ID")
    end

    config :riddlr, Riddlr.SMS, adapter: adapter
  end

  # ## Mailer
  #
  # MAILER_ADAPTER names an adapter under Swoosh.Adapters. With none set,
  # the mailer keeps the default from config.exs.
  #
  # "Resend" sends through Resend. It needs MAILER_API_KEY (a Resend API
  # key) and MAIL_FROM (an address on a domain Resend has verified), and no
  # AWS_* keys.
  #
  # Any other value names an API adapter, e.g. "Postmark" or "Brevo".
  # MAILER_API_KEY and MAILER_DOMAIN are passed only when set; check the
  # adapter's docs for which it needs.
  #
  # The API client (Req, via Riddlr.Mailer.ResendApiClient) is set in
  # config/prod.exs.
  mail_from = System.get_env("MAIL_FROM")

  if mail_from do
    config :riddlr, :mail_from, {"Kriddle", mail_from}
  end

  case System.get_env("MAILER_ADAPTER") do
    nil ->
      :ok

    "Resend" ->
      resend_env =
        Map.new(~w(MAILER_API_KEY MAIL_FROM), &{&1, String.trim(System.get_env(&1, ""))})

      missing = for {name, ""} <- resend_env, do: name

      if missing != [] do
        raise "environment variables #{Enum.join(missing, ", ")} missing or blank. " <>
                "MAILER_ADAPTER=Resend needs them."
      end

      config :riddlr, :mail_from, {"Kriddle", resend_env["MAIL_FROM"]}

      config :riddlr, Riddlr.Mailer,
        adapter: Swoosh.Adapters.Resend,
        api_key: resend_env["MAILER_API_KEY"]

    adapter ->
      mailer_opts =
        [
          api_key: System.get_env("MAILER_API_KEY"),
          domain: System.get_env("MAILER_DOMAIN")
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      config :riddlr,
             Riddlr.Mailer,
             [adapter: Module.concat(Swoosh.Adapters, adapter)] ++ mailer_opts
  end
end

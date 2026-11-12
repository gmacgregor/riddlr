defmodule Riddlr.RuntimeConfigTest do
  # Reads config/runtime.exs as prod with fake env values. It sets OS env
  # vars, which all processes share, so it does not run async.
  use ExUnit.Case, async: false

  @runtime "config/runtime.exs"

  @base_env %{
    "DATABASE_URL" => "ecto://user:pass@localhost/riddlr",
    "SECRET_KEY_BASE" => String.duplicate("a", 64),
    "PHX_HOST" => "example.com",
    "CLOAK_KEY" => "fake-cloak-key",
    "CLOAK_KEY_TAG" => "AES.GCM.V1",
    "PHONE_HMAC_KEY" => "fake-hmac-key"
  }

  @managed_vars Map.keys(@base_env) ++
                  ~w(MAILER_ADAPTER MAILER_API_KEY MAILER_DOMAIN MAIL_FROM
                     SMS_ADAPTER AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
                     SMS_ORIGINATION_ID PHX_SERVER CLOAK_KEY_OLD CLOAK_KEY_OLD_TAG)

  @resend_env %{
    "MAILER_ADAPTER" => "Resend",
    "MAILER_API_KEY" => "re_fake_key",
    "MAIL_FROM" => "riddles@example.com"
  }

  @aws_sms_env %{
    "SMS_ADAPTER" => "AWS",
    "AWS_REGION" => "ca-central-1",
    "AWS_ACCESS_KEY_ID" => "AKIAFAKE",
    "AWS_SECRET_ACCESS_KEY" => "fake-secret",
    "SMS_ORIGINATION_ID" => "+15555550100"
  }

  setup do
    saved = Map.new(@managed_vars, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  defp read_prod(env) do
    Enum.each(@managed_vars, &System.delete_env/1)
    System.put_env(Map.merge(@base_env, env))
    Config.Reader.read!(@runtime, env: :prod, target: :host)
  end

  test "Resend email needs only its key and sender, no AWS settings" do
    config = read_prod(@resend_env)

    mailer = config[:riddlr][Riddlr.Mailer]
    assert mailer[:adapter] == Swoosh.Adapters.Resend
    assert mailer[:api_key] == "re_fake_key"
    assert config[:riddlr][:mail_from] == {"Kriddle", "riddles@example.com"}
    refute config[:riddlr][Riddlr.SMS]
  end

  test "Resend trims stray spaces from its key and sender" do
    config =
      read_prod(%{
        @resend_env
        | "MAILER_API_KEY" => " re_fake_key ",
          "MAIL_FROM" => " riddles@example.com\n"
      })

    assert config[:riddlr][Riddlr.Mailer][:api_key] == "re_fake_key"
    assert config[:riddlr][:mail_from] == {"Kriddle", "riddles@example.com"}
  end

  test "Resend with missing key and sender names both" do
    env = Map.drop(@resend_env, ~w(MAILER_API_KEY MAIL_FROM))

    error = assert_raise RuntimeError, fn -> read_prod(env) end
    assert error.message =~ "MAILER_API_KEY"
    assert error.message =~ "MAIL_FROM"
  end

  test "Resend with blank key and sender names both" do
    env = %{@resend_env | "MAILER_API_KEY" => " ", "MAIL_FROM" => ""}

    error = assert_raise RuntimeError, fn -> read_prod(env) end
    assert error.message =~ "MAILER_API_KEY"
    assert error.message =~ "MAIL_FROM"
  end

  test "Resend with only the key missing names the key alone" do
    env = Map.delete(@resend_env, "MAILER_API_KEY")

    error = assert_raise RuntimeError, fn -> read_prod(env) end
    assert error.message =~ "MAILER_API_KEY"
    refute error.message =~ "MAIL_FROM"
  end

  test "AWS SMS alone configures texts and leaves the mailer default" do
    config = read_prod(@aws_sms_env)

    assert config[:riddlr][Riddlr.SMS][:adapter] == Riddlr.SMS.AWS

    assert config[:riddlr][Riddlr.SMS.AWS] == [
             region: "ca-central-1",
             access_key_id: "AKIAFAKE",
             secret_access_key: "fake-secret",
             origination_identity: "+15555550100"
           ]

    refute config[:riddlr][Riddlr.Mailer]
  end

  for name <- ~w(AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY SMS_ORIGINATION_ID) do
    test "AWS SMS without #{name} fails, even with Resend set" do
      env = Map.merge(@resend_env, Map.delete(@aws_sms_env, unquote(name)))

      error = assert_raise RuntimeError, fn -> read_prod(env) end
      assert error.message =~ unquote(name)
    end
  end

  for name <- ~w(AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY SMS_ORIGINATION_ID) do
    test "AWS SMS with blank #{name} fails" do
      env = %{@aws_sms_env | unquote(name) => "  "}

      error = assert_raise RuntimeError, fn -> read_prod(env) end
      assert error.message =~ unquote(name)
    end
  end

  test "AWS SMS trims stray spaces from its settings" do
    config = read_prod(%{@aws_sms_env | "AWS_REGION" => " ca-central-1\n"})

    assert config[:riddlr][Riddlr.SMS.AWS][:region] == "ca-central-1"
  end

  test "Resend email and AWS SMS each get their own settings" do
    config = read_prod(Map.merge(@resend_env, @aws_sms_env))

    assert config[:riddlr][Riddlr.Mailer] == [
             adapter: Swoosh.Adapters.Resend,
             api_key: "re_fake_key"
           ]

    assert config[:riddlr][:mail_from] == {"Kriddle", "riddles@example.com"}
    assert config[:riddlr][Riddlr.SMS][:adapter] == Riddlr.SMS.AWS
    assert config[:riddlr][Riddlr.SMS.AWS][:access_key_id] == "AKIAFAKE"
  end

  test "another adapter name goes through the generic branch" do
    config =
      read_prod(%{
        "MAILER_ADAPTER" => "Mailgun",
        "MAILER_API_KEY" => "key",
        "MAILER_DOMAIN" => "mg.example.com"
      })

    assert config[:riddlr][Riddlr.Mailer] == [
             adapter: Swoosh.Adapters.Mailgun,
             api_key: "key",
             domain: "mg.example.com"
           ]
  end

  test "AmazonSES has no dedicated branch" do
    config = read_prod(%{"MAILER_ADAPTER" => "AmazonSES"})

    assert config[:riddlr][Riddlr.Mailer] == [adapter: Swoosh.Adapters.AmazonSES]
  end
end

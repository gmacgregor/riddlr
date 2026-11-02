defmodule Riddlr.VaultTest do
  use ExUnit.Case, async: true

  alias Riddlr.Vault

  @key Base.encode64(:binary.copy(<<1>>, 32))
  @old_key Base.encode64(:binary.copy(<<2>>, 32))

  describe "init/1" do
    test "labels the first key :default and the next :old" do
      {:ok, config} = Vault.init(keys: [{"AES.GCM.V2", @key}, {"AES.GCM.V1", @old_key}])

      assert [
               default: {Cloak.Ciphers.AES.GCM, default_opts},
               old: {Cloak.Ciphers.AES.GCM, old_opts}
             ] = config[:ciphers]

      assert default_opts[:tag] == "AES.GCM.V2"
      assert old_opts[:tag] == "AES.GCM.V1"
    end

    test "refuses two keys with the same tag" do
      assert_raise ArgumentError, ~r/tag/, fn ->
        Vault.init(keys: [{"AES.GCM.V1", @key}, {"AES.GCM.V1", @old_key}])
      end
    end

    test "refuses more keys than it has labels for" do
      third = Base.encode64(:binary.copy(<<3>>, 32))

      assert_raise ArgumentError, ~r/at most 2 keys/, fn ->
        Vault.init(keys: [{"V3", @key}, {"V2", @old_key}, {"V1", third}])
      end
    end
  end
end

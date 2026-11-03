defmodule Riddlr.CacheTest do
  use ExUnit.Case, async: false

  import Riddlr.CacheHelpers

  alias Riddlr.Cache

  setup :enable_cache

  test "get/1 misses a key never put" do
    assert Cache.get({:test, make_ref()}) == :error
  end

  test "put/2 then get/1 returns the value" do
    key = {:test, make_ref()}
    Cache.put(key, %{a: 1})
    assert Cache.get(key) == {:ok, %{a: 1}}
  end

  test "delete/1 drops the key" do
    key = {:test, make_ref()}
    Cache.put(key, 1)
    Cache.delete(key)
    assert Cache.get(key) == :error
  end

  test "delete_match/1 drops every key matching the pattern" do
    ref = make_ref()
    Cache.put({:test, ref, 1}, :a)
    Cache.put({:test, ref, 2}, :b)
    Cache.put({:other, ref}, :c)

    Cache.delete_match({:test, ref, :_})

    assert Cache.get({:test, ref, 1}) == :error
    assert Cache.get({:test, ref, 2}) == :error
    assert Cache.get({:other, ref}) == {:ok, :c}
  end

  describe "fetch/2" do
    test "computes and stores the value on a miss" do
      key = {:test, make_ref()}
      assert Cache.fetch(key, fn -> 42 end) == 42
      assert Cache.get(key) == {:ok, 42}
    end

    test "returns the stored value on a hit, without computing" do
      key = {:test, make_ref()}
      Cache.put(key, 1)
      assert Cache.fetch(key, fn -> flunk("computed on a hit") end) == 1
    end
  end

  describe "turned off" do
    setup do
      Application.put_env(:riddlr, Cache, enabled: false)
      :ok
    end

    test "stores nothing and always computes" do
      key = {:test, make_ref()}
      Cache.put(key, 1)
      assert Cache.get(key) == :error
      assert Cache.fetch(key, fn -> 2 end) == 2
      assert Cache.get(key) == :error
    end
  end
end

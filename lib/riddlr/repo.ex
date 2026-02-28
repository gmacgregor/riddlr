defmodule Riddlr.Repo do
  use Ecto.Repo,
    otp_app: :riddlr,
    adapter: Ecto.Adapters.Postgres
end

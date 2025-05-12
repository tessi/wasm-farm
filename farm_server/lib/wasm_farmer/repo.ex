defmodule WasmFarmer.Repo do
  use Ecto.Repo,
    otp_app: :wasm_farmer,
    adapter: Ecto.Adapters.Postgres
end

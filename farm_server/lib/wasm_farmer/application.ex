defmodule WasmFarmer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      WasmFarmerWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: WasmFarmer.PubSub},
      # Start the Endpoint (http/https)
      WasmFarmerWeb.Endpoint,
      # Start the GameServer
      WasmFarmer.Game.GameServer
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WasmFarmer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WasmFarmerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

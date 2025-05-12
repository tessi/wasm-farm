defmodule WasmFarmerWeb.PageController do
  use WasmFarmerWeb, :controller

  def home(conn, _params) do
    farm_id = GenServer.call(WasmFarmer.Game.GameServer, :create_farm)
    redirect(conn, to: ~p"/farms/#{farm_id}")
  end
end

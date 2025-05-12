defmodule WasmFarmerWeb.FarmListLive do
  use WasmFarmerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(1000, self(), :refresh)
    end

    socket = allow_upload(socket, :wasm_binary, accept: [".wasm"], max_entries: 1)
    farms = get_farms()
    {:ok, assign(socket, farms: farms)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_farm", %{"farm_id" => farm_id}, socket) do
    GenServer.cast(WasmFarmer.Game.GameServer, {:delete_farm, farm_id})
    farms = get_farms()
    {:noreply, assign(socket, farms: farms)}
  end

  @impl true
  def handle_event("create_farm", _params, socket) do
    GenServer.call(WasmFarmer.Game.GameServer, :create_farm)
    farms = get_farms()
    {:noreply, assign(socket, farms: farms)}
  end

  @impl true
  def handle_event("upload_wasm", %{"farm_id" => farm_id, "count" => count}, socket) do
    {entries, []} = uploaded_entries(socket, :wasm_binary)

    case Integer.parse(count) do
      {count, _} when count > 0 and count <= 10 ->
        case entries do
          [] ->
            {:noreply, put_flash(socket, :error, "No file selected")}

          [entry | _] ->
            case consume_uploaded_entry(socket, entry, fn %{path: path} ->
              case File.read(path) do
                {:ok, binary} -> {:ok, {:ok, binary}}
                {:error, reason} -> {:error, reason}
              end
            end) do
              {:ok, wasm_binary} when is_binary(wasm_binary) ->
                with :ok <- GenServer.call(WasmFarmer.Game.GameServer, {:add_wasm_bots, farm_id, wasm_binary, count}) do
                  {:noreply, redirect(socket, to: ~p"/farms/#{farm_id}")}
                else
                  {:error, reason} ->
                    {:noreply, put_flash(socket, :error, "Failed to add WASM bots: #{inspect(reason)}")}
                end
              {:error, reason} ->
                {:noreply, put_flash(socket, :error, "Failed to read WASM binary: #{reason}")}
            end
        end
      _ ->
        {:noreply, put_flash(socket, :error, "Count must be between 1 and 10")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    farms = get_farms()
    {:noreply, assign(socket, farms: farms)}
  end

  defp get_farms do
    GenServer.call(WasmFarmer.Game.GameServer, :get_all_farms)
  end
end

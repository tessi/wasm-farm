defmodule WasmFarmer.Game.GameServer do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :timer.send_interval(WasmFarmer.Game.Settings.tick_interval(), self(), :tick)
    {:ok, %{farms: %{}, bot_owners: %{}, logs: %{}}}
  end

  def handle_call({:get_state, farm_id}, _from, state) do
    case Map.get(state.farms, farm_id) do
      nil ->
        {:reply, nil, state}

      farm ->
        logs = Map.get(state.logs, farm_id, [])
        {:reply, %{farm | logs: logs}, state}
    end
  end

  def handle_call(:get_all_farms, _from, state) do
    {:reply, state.farms, state}
  end

  def handle_call(:create_farm, _from, state) do
    farm_id = Ecto.UUID.generate()
    farm = WasmFarmer.Game.Farm.new()

    {:reply, farm_id,
     %{state | farms: Map.put(state.farms, farm_id, farm), logs: Map.put(state.logs, farm_id, [])}}
  end

  def handle_call({:add_wasm_bots, farm_id, wasm_binary, count}, _from, state) do
    IO.puts("Adding WASM bot to farm #{farm_id} with wasm_binary #{inspect(wasm_binary)}")

    case Map.get(state.farms, farm_id) do
      nil ->
        {:noreply, state}

      _farm ->
        result =
          Enum.reduce(1..count, {:ok, state}, fn
            _, {:error, error} ->
              {:error, error}

            _, {:ok, state} ->
              bot_id = "wasm-" <> Ecto.UUID.generate()

              with {:ok, pid} <-
                     WasmFarmer.Game.WasmBot.start_link(%{
                       farm_id: farm_id,
                       bot_id: bot_id,
                       wasm_binary: wasm_binary,
                       tick_interval: WasmFarmer.Game.Settings.tick_interval()
                     }) do
                IO.puts("Added bot #{bot_id} to farm #{farm_id}")
                %{logs: logs} = add_log(state, farm_id, bot_id, "Bot joined the farm", :info)
                farm = Map.get(state.farms, farm_id)
                new_farm = WasmFarmer.Game.Farm.add_bot(farm, bot_id, 0, 0, _is_wasm_bot = true)

                {:ok,
                 %{
                   state
                   | farms: Map.put(state.farms, farm_id, new_farm),
                     bot_owners: Map.put(state.bot_owners, bot_id, pid),
                     logs: logs
                 }}
              end
          end)

        Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)

        case result do
          {:ok, state} ->
            {:reply, :ok, state}

          {:error, error} ->
            IO.puts("Error adding WASM bot to farm #{farm_id}: #{inspect(error)}")
            {:reply, {:error, error}, state}
        end
    end
  end

  def handle_info(:tick, state) do
    new_farms =
      Enum.reduce(state.farms, %{}, fn {farm_id, farm}, acc ->
        new_farm = WasmFarmer.Game.Farm.tick(farm)
        Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)
        Map.put(acc, farm_id, new_farm)
      end)

    {:noreply, %{state | farms: new_farms}}
  end

  def handle_cast({:bot_action, farm_id, bot_id, action}, state) do
    case Map.get(state.farms, farm_id) do
      nil ->
        {:noreply, state}

      farm ->
        bot = WasmFarmer.Game.Farm.get_bot(farm, bot_id)
        bot = WasmFarmer.Game.Bot.initiate_action(bot, action)
        new_farm = WasmFarmer.Game.Farm.update_bot(farm, bot)
        Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)
        {:noreply, %{state | farms: Map.put(state.farms, farm_id, new_farm)}}
    end
  end

  def handle_cast({:sell, farm_id, resource, amount}, state) do
    case Map.get(state.farms, farm_id) do
      nil ->
        {:noreply, state}

      farm ->
        new_farm = WasmFarmer.Game.Farm.sell_resources(farm, resource, amount)
        Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)
        {:noreply, %{state | farms: Map.put(state.farms, farm_id, new_farm)}}
    end
  end

  def handle_cast({:buy, farm_id, bot_id, resource, amount}, state) do
    case Map.get(state.farms, farm_id) do
      nil ->
        {:noreply, state}

      farm ->
        new_farm = WasmFarmer.Game.Farm.buy_resources(farm, bot_id, resource, amount)
        Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)
        {:noreply, %{state | farms: Map.put(state.farms, farm_id, new_farm)}}
    end
  end

  def handle_cast({:add_bot, farm_id, bot_id, x, y, owner_pid}, state) do
    case Map.get(state.farms, farm_id) do
      nil ->
        {:noreply, state}

      farm ->
        new_farm = WasmFarmer.Game.Farm.add_bot(farm, bot_id, x, y, _is_wasm_bot = false)
        Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)

        {:noreply,
         %{
           state
           | farms: Map.put(state.farms, farm_id, new_farm),
             bot_owners: Map.put(state.bot_owners, bot_id, owner_pid)
         }}
    end
  end

  def handle_cast({:remove_bot, farm_id, bot_id, owner_pid}, state) do
    case Map.get(state.farms, farm_id) do
      nil ->
        {:noreply, state}

      farm ->
        case Map.get(state.bot_owners, bot_id) do
          ^owner_pid ->
            new_farm = %{farm | bots: Map.delete(farm.bots, bot_id)}
            add_log(state, farm_id, bot_id, "Bot #{bot_id} left the farm", :info)
            Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)

            {:noreply,
             %{
               state
               | farms: Map.put(state.farms, farm_id, new_farm),
                 bot_owners: Map.delete(state.bot_owners, bot_id)
             }}

          actual_owner ->
            IO.puts(
              "Cannot remove bot #{bot_id} - owned by #{inspect(actual_owner)}, requested by #{inspect(owner_pid)}"
            )

            {:noreply, state}
        end
    end
  end

  def handle_cast({:delete_farm, farm_id}, state) do
    Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :deleted)

    {:noreply,
     %{state | farms: Map.delete(state.farms, farm_id), logs: Map.delete(state.logs, farm_id)}}
  end

  def handle_cast({:update_bot_display_name, farm_id, bot_id, display_name, owner_pid}, state) do
    case Map.get(state.farms, farm_id) do
      nil ->
        {:noreply, state}

      farm ->
        case Map.get(state.bot_owners, bot_id) do
          ^owner_pid ->
            bot = WasmFarmer.Game.Farm.get_bot(farm, bot_id)
            bot = %{bot | display_name: display_name}
            new_farm = WasmFarmer.Game.Farm.update_bot(farm, bot)
            Phoenix.PubSub.broadcast(WasmFarmer.PubSub, "farm:#{farm_id}", :tick)
            {:noreply, %{state | farms: Map.put(state.farms, farm_id, new_farm)}}

          _ ->
            {:noreply, state}
        end
    end
  end

  def handle_cast({:log, farm_id, bot_id, message, level}, state) do
    {:noreply, add_log(state, farm_id, bot_id, message, level)}
  end

  defp add_log(state, farm_id, bot_id, message, log_level) do
    logs = Map.get(state.logs, farm_id, [])

    new_log = %{
      bot_id: bot_id,
      message: message,
      timestamp: DateTime.utc_now(),
      level: log_level
    }

    new_logs = [new_log | logs] |> Enum.take(WasmFarmer.Game.Settings.max_log_entries())
    %{state | logs: Map.put(state.logs, farm_id, new_logs)}
  end
end

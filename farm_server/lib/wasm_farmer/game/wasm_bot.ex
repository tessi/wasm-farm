defmodule WasmFarmer.Game.WasmBot do
  use GenServer
  require Logger

  @buyable_resources [:energy, :water, :seeds]
  @sellable_resources [:grass, :wheat]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(%{
        farm_id: farm_id,
        bot_id: bot_id,
        wasm_binary: wasm_binary,
        tick_interval: tick_interval
      }) do
    IO.puts("Initializing WASM bot for farm #{farm_id} with bot #{bot_id}")

    imports = %{
      "wasi:random/random@0.2.3" => %{
        "get-random-bytes" =>
        {:fn,
         fn len ->
           Enum.map(0..len - 1, fn _ -> :rand.uniform(2 ** 8 - 1) end)
         end},
        "get-random-u64" =>
        {:fn,
         fn ->
           :rand.uniform(2 ** 64 - 1)
         end}
      },
      "sell" =>
        {:fn,
         fn resource, amount ->
           if resource in @sellable_resources do
             GenServer.cast(
               WasmFarmer.Game.GameServer,
               {:sell, farm_id, resource, amount}
             )
             :ok
           else
             {:error,
              "Invalid resource. Valid resources are: #{inspect(@sellable_resources)}, but got: #{resource}"}
           end
         end},
      "buy" =>
        {:fn,
         fn resource, amount ->
           if resource in @buyable_resources do
             GenServer.cast(
               WasmFarmer.Game.GameServer,
               {:buy, farm_id, bot_id, resource, amount}
             )
             :ok
           else
             {:error,
              "Invalid resource. Valid resources are: #{inspect(@buyable_resources)}, but got: #{resource}"}
           end
         end},
      "bot-action" =>
        {:fn,
         fn action ->
           case action do
             {:seed, _plant_type} ->
               GenServer.cast(
                 WasmFarmer.Game.GameServer,
                 {:bot_action, farm_id, bot_id, :seed}
               )

             :water ->
               GenServer.cast(
                 WasmFarmer.Game.GameServer,
                 {:bot_action, farm_id, bot_id, :water}
               )

             :harvest ->
               GenServer.cast(
                 WasmFarmer.Game.GameServer,
                 {:bot_action, farm_id, bot_id, :harvest}
               )

             :idle ->
               nil

             :"move-left" ->
               GenServer.cast(
                 WasmFarmer.Game.GameServer,
                 {:bot_action, farm_id, bot_id, :move_left}
               )

             :"move-right" ->
               GenServer.cast(
                 WasmFarmer.Game.GameServer,
                 {:bot_action, farm_id, bot_id, :move_right}
               )

             :"move-up" ->
               GenServer.cast(
                 WasmFarmer.Game.GameServer,
                 {:bot_action, farm_id, bot_id, :move_up}
               )

             :"move-down" ->
               GenServer.cast(
                 WasmFarmer.Game.GameServer,
                 {:bot_action, farm_id, bot_id, :move_down}
               )

             _ ->
               Logger.info("Unknown action: #{inspect(action)}")
           end
         end},
      "update-display-name" =>
        {:fn,
         fn new_display_name ->
           GenServer.cast(
             WasmFarmer.Game.GameServer,
             {:update_display_name, farm_id, bot_id, new_display_name}
           )
         end},
      "get-farm" =>
        {:fn,
         fn ->
           farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, farm_id})

           fields =
             Enum.map(farm.fields, fn {_key, field} ->
               plant =
                 case field.content do
                   :empty ->
                     :none

                   :grass ->
                     {:some,
                      %{
                        "plant-type": :grass,
                        "growth-stage": field.growth_stage,
                        "growth-stage-max": 4
                      }}

                   :wheat ->
                     {:some,
                      %{
                        "plant-type": :wheat,
                        "growth-stage": field.growth_stage,
                        "growth-stage-max": 4
                      }}
                 end

               entities =
                 farm.bots
                 |> Enum.filter(fn {_id, bot} -> bot.x == field.x and bot.y == field.y end)
                 |> Enum.map(fn {_id, bot} ->
                   display_name =
                     case bot.display_name do
                       nil -> :none
                       name -> {:some, name}
                     end

                   %{
                     id: bot.id,
                     "display-name": display_name,
                     "entity-type": :bot,
                     position: %{
                       x: bot.x,
                       y: bot.y
                     }
                   }
                 end)

               %{
                 x: field.x,
                 y: field.y,
                 plant: plant,
                 "field-type": :owned,
                 entities: entities,
                 watered: field.watered
               }
             end)

           fields =
             fields
             |> Enum.group_by(& &1.y)
             |> Enum.sort_by(fn {y, _fields} -> y end)
             |> Enum.map(fn {_y, fields_row} ->
               Enum.sort_by(fields_row, & &1.x)
             end)
             |> Enum.map(fn fields_row ->
               Enum.map(fields_row, &Map.drop(&1, [:x, :y]))
             end)

           %{
             "fields-width": farm.width,
             "fields-height": farm.height,
             grass: farm.resources.grass,
             wheat: farm.resources.wheat,
             fields: fields
           }
         end},
      "get-bot-state" =>
        {:fn,
         fn a ->
           Logger.info("get-bot-state #{a}")
         end},
      "log" =>
        {:fn,
         fn message, log_level ->
           GenServer.cast(
             WasmFarmer.Game.GameServer,
             {:log, farm_id, bot_id, message, log_level}
           )
         end}
    }

    with {:ok, pid} <-
           Wasmex.Components.start_link(%{
             bytes: wasm_binary,
             imports: imports
           }) do
      Process.send_after(self(), :tick, tick_interval)
      {:ok, %{farm_id: farm_id, bot_id: bot_id, wasm_pid: pid, tick_interval: tick_interval}}
    else
      error ->
        Logger.error("Error starting WASM bot: #{inspect(error)}")
        {:error, error}
    end
  end

  def handle_info(:tick, state) do
    farm = GenServer.call(WasmFarmer.Game.GameServer, {:get_state, state.farm_id})
    bot = WasmFarmer.Game.Farm.get_bot(farm, state.bot_id)

    action =
      case bot.current_action do
        :idle -> :idle
        nil -> :idle
        :move_left -> :"move-left"
        :move_right -> :"move-right"
        :move_up -> :"move-up"
        :move_down -> :"move-down"
        :water -> :water
        :seed -> {:seed, "wheat"}
        :harvest -> :harvest
      end

    bot_param = %{
      "id" => bot.id,
      "display-name" => bot.display_name,
      "current-action" => action,
      "energy" => bot.energy,
      "water" => bot.water,
      "seeds" => bot.seeds,
      "position" => %{
        "x" => bot.x,
        "y" => bot.y
      }
    }

    {:ok, []} = Wasmex.Components.call_function(state.wasm_pid, "tick", [bot_param])

    # Schedule next tick delayed slightly random
    delay = :rand.uniform(100)
    Process.send_after(self(), :tick, state.tick_interval + delay)
    {:noreply, state}
  end

  def terminate(reason, state) do
    GenServer.cast(
      WasmFarmer.Game.GameServer,
      {:remove_bot, state.farm_id, state.bot_id, self()}
    )

    GenServer.stop(state.wasm_pid, reason)
  end
end

defmodule WasmFarmer.Game.Bot do
  defstruct [:id, :display_name, :x, :y, :energy, :water, :seeds, :current_action, :wait, :is_wasm_bot]

  @type action ::
          :move_left | :move_right | :move_up | :move_down | :seed | :water | :harvest | :idle

  @type t :: %__MODULE__{
          id: String.t(),
          display_name: String.t() | nil,
          x: integer(),
          y: integer(),
          energy: integer(),
          water: integer(),
          seeds: integer(),
          current_action: action(),
          wait: integer(),
          is_wasm_bot: boolean()
        }

  def new(id, x, y, is_wasm_bot, inventory \\ Map.new()) do
    inventory = Map.merge(WasmFarmer.Game.Settings.bot_inventory(), inventory)

    %__MODULE__{
      id: id,
      display_name: nil,
      x: x,
      y: y,
      energy: inventory.energy,
      water: inventory.water,
      seeds: inventory.seeds,
      current_action: nil,
      wait: 0,
      is_wasm_bot: is_wasm_bot
    }
  end

  def get_display_name(bot) do
    Map.get(bot, :display_name) || "Bot #{bot.id}"
  end

  def tick(bot, farm) do
    case bot.current_action do
      nil ->
        {:ok, {farm, bot}}

      action ->
        new_wait = max(bot.wait - 1, 0)

        if new_wait == 0 do
          # Action completed
          case action do
            :move_left ->
              do_if_enough_energy(bot, farm, action, fn ->
                {farm, %{bot | x: max(bot.x - 1, 0)}}
              end)

            :move_right ->
              do_if_enough_energy(bot, farm, action, fn ->
                {farm, %{bot | x: min(bot.x + 1, farm.width - 1)}}
              end)

            :move_up ->
              do_if_enough_energy(bot, farm, action, fn ->
                {farm, %{bot | y: max(bot.y - 1, 0)}}
              end)

            :move_down ->
              do_if_enough_energy(bot, farm, action, fn ->
                {farm, %{bot | y: min(bot.y + 1, farm.height - 1)}}
              end)

            :plow ->
              do_if_enough_energy(bot, farm, action, fn ->
                {WasmFarmer.Game.Farm.bot_action(farm, bot, :plow), bot}
              end)

            :seed ->
              do_if_enough_energy(bot, farm, action, fn ->
                if bot.seeds > 0 do
                  {
                    WasmFarmer.Game.Farm.bot_action(farm, bot, {:seed, :wheat}),
                    %{bot | seeds: bot.seeds - 1}
                  }
                else
                  {farm, bot}
                end
              end)

            :water ->
              do_if_enough_energy(bot, farm, action, fn ->
                if bot.water > 0 do
                  {
                    WasmFarmer.Game.Farm.bot_action(farm, bot, :water),
                    %{bot | water: bot.water - 1}
                  }
                else
                  {farm, bot}
                end
              end)

            :harvest ->
              do_if_enough_energy(bot, farm, action, fn ->
                {WasmFarmer.Game.Farm.bot_action(farm, bot, :harvest), bot}
              end)
          end
        else
          # Action in progress
          {:ok, {farm, %{bot | wait: new_wait}}}
        end
    end
  end

  def do_if_enough_energy(bot, farm, action, fun) do
    energy_cost = WasmFarmer.Game.Settings.energy_costs()[action]

    if bot.energy >= energy_cost do
      {farm, bot} = fun.()
      {:ok, {farm, %{bot | current_action: nil, wait: 0, energy: bot.energy - energy_cost}}}
    else
      {:ok, {farm, %{bot | current_action: nil, wait: 0}}}
    end
  end

  def initiate_action(bot, action) do
    %{bot | current_action: action, wait: action_duration(action)}
  end

  defp action_duration(action) do
    WasmFarmer.Game.Settings.action_durations()[action]
  end
end

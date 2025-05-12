defmodule WasmFarmer.Game.Farm do
  defstruct [:fields, :bots, :resources, :money, :width, :height, :logs]

  @type t :: %__MODULE__{
          fields: %{{integer(), integer()} => WasmFarmer.Game.Field.t()},
          bots: %{String.t() => WasmFarmer.Game.Bot.t()},
          resources: %{wheat: integer(), grass: integer()},
          money: integer(),
          width: integer(),
          height: integer(),
          logs: list()
        }

  @default_width 7
  @default_height 5

  def new() do
    fields =
      for x <- 0..(@default_width - 1), y <- 0..(@default_height - 1), into: %{} do
        {{x, y}, WasmFarmer.Game.Field.new(x, y)}
      end

    %__MODULE__{
      fields: fields,
      bots: %{},
      resources: %{wheat: 0, grass: 0},
      money: 100,
      width: @default_width,
      height: @default_height,
      logs: []
    }
  end

  def get_field(farm, x, y) do
    Map.get(farm.fields, {x, y})
  end

  def add_bot(farm, bot_id, x, y, is_wasm_bot, inventory \\ Map.new()) do
    new_bot = WasmFarmer.Game.Bot.new(bot_id, x, y, is_wasm_bot, inventory)
    update_bot(farm, new_bot)
  end

  def get_bot(farm, bot_id) do
    farm.bots[bot_id]
  end

  def update_bot(farm, bot) do
    %{farm | bots: Map.put(farm.bots, bot.id, bot)}
  end

  def tick(farm) do
    # Tick all bots
    farm =
      Enum.reduce(farm.bots, farm, fn {_bot_id, bot}, farm ->
        {:ok, {farm, bot}} = WasmFarmer.Game.Bot.tick(bot, farm)
        update_bot(farm, bot)
      end)

    # Update all fields
    new_fields =
      Map.new(farm.fields, fn {pos, field} ->
        {pos, WasmFarmer.Game.Field.tick(field)}
      end)

    %{farm | fields: new_fields}
  end

  def bot_action(farm, bot, action) do
    case action do
      :plow ->
        field = WasmFarmer.Game.Field.plow(get_field(farm, bot.x, bot.y))
        %{farm | fields: Map.put(farm.fields, {bot.x, bot.y}, field)}

      {:seed, seed_type} ->
        field = WasmFarmer.Game.Field.seed(get_field(farm, bot.x, bot.y), seed_type)
        %{farm | fields: Map.put(farm.fields, {bot.x, bot.y}, field)}

      :water ->
        field = WasmFarmer.Game.Field.water(get_field(farm, bot.x, bot.y))
        %{farm | fields: Map.put(farm.fields, {bot.x, bot.y}, field)}

      :harvest ->
        {harvested_resources, field} =
          WasmFarmer.Game.Field.harvest(get_field(farm, bot.x, bot.y))

        resources =
          Enum.reduce(harvested_resources, farm.resources, fn {resource, amount}, acc ->
            Map.update(acc, resource, amount, &(&1 + amount))
          end)

        %{farm | fields: Map.put(farm.fields, {bot.x, bot.y}, field), resources: resources}

      _ ->
        farm
    end
  end

  def sell_resources(farm, resource, amount) do
    current_amount = farm.resources[resource]

    if current_amount >= amount do
      price = WasmFarmer.Game.Settings.sell_prices(resource, amount)
      new_resources = %{farm.resources | resource => current_amount - amount}
      %{farm | resources: new_resources, money: farm.money + price}
    else
      farm
    end
  end

  def buy_resources(farm, bot_id, resource, quantity) do
    bot = farm.bots[bot_id]
    price = WasmFarmer.Game.Settings.resource_prices(resource, quantity)

    if farm.money >= price do
      new_bot =
        case resource do
          :energy -> %{bot | energy: bot.energy + quantity}
          :water -> %{bot | water: bot.water + quantity}
          :seeds -> %{bot | seeds: bot.seeds + quantity}
        end

      %{farm | bots: Map.put(farm.bots, bot_id, new_bot), money: farm.money - price}
    else
      farm
    end
  end
end

defmodule WasmFarmer.Game.Settings do
  @tick_interval 100

  def tick_interval do
    @tick_interval
  end

  def energy_costs do
    %{
      move_left: 2,
      move_right: 2,
      move_up: 2,
      move_down: 2,
      plow: 20,
      seed: 8,
      water: 4,
      harvest: 12
    }
  end

  def resource_prices(resource, quantity \\ 1) do
    prices = %{
      energy: 1.33,
      water: 1,
      seeds: 3
    }

    round(prices[resource] * quantity)
  end

  def sell_prices(resource, quantity \\ 1) do
    prices = %{
      wheat: 45,
      grass: 25
    }

    round(prices[resource] * quantity)
  end

  def action_durations do
    %{
      move_left: 5,
      move_right: 5,
      move_up: 5,
      move_down: 5,
      seed: 18,
      water: 18,
      harvest: 20,
      plow: 20
    }
  end

  def bot_inventory do
    %{
      energy: 100,
      water: 0,
      seeds: 0
    }
  end

  def growth_ticks(current_stage, watered, crop_type) do
    multiplier = if watered, do: 0.6, else: 1

    case crop_type do
      :grass ->
        100

      :wheat ->
        case current_stage do
          0 -> 50 * multiplier
          1 -> 50 * multiplier
          2 -> 100 * multiplier
          3 -> 200 * multiplier
        end
    end
  end

  def decay_ticks do
    %{
      grass: 1000,
      wheat: 300
    }
  end

  def max_log_entries do
    1_000
  end
end

defmodule WasmFarmer.Game.Field do
  defstruct [:x, :y, :content, :growth_stage, :growth_timer, :fully_grown_timer, :watered]

  @type content :: :grass | :wheat | :empty
  @type growth_stage :: 0..4

  @type t :: %__MODULE__{
          x: integer(),
          y: integer(),
          content: content(),
          growth_stage: growth_stage(),
          growth_timer: integer(),
          fully_grown_timer: integer(),
          watered: boolean()
        }

  def new(x, y) do
    %__MODULE__{
      x: x,
      y: y,
      content: :empty,
      growth_stage: 0,
      growth_timer: 0,
      fully_grown_timer: 0,
      watered: false
    }
  end

  def tick(field) do
    case field.content do
      :empty ->
        # Random chance for grass to start growing
        # 0.5% chance each tick
        if :rand.uniform(10000) <= 5 do
          %{field | content: :grass, growth_stage: 0, growth_timer: 0}
        else
          field
        end

      _ ->
        if field.growth_stage < 4 do
          if field.growth_timer >=
               WasmFarmer.Game.Settings.growth_ticks(
                 field.growth_stage,
                 field.watered,
                 field.content
               ) do
            %{field | growth_stage: field.growth_stage + 1, growth_timer: 0, watered: false}
          else
            %{field | growth_timer: field.growth_timer + 1}
          end
        else
          if field.fully_grown_timer >= WasmFarmer.Game.Settings.decay_ticks()[field.content] do
            %{
              field
              | content: :empty,
                growth_stage: 0,
                growth_timer: 0,
                fully_grown_timer: 0,
                watered: false
            }
          else
            %{field | fully_grown_timer: field.fully_grown_timer + 1}
          end
        end
    end
  end

  def seed(field, crop_type) do
    if field.content == :empty do
      %{field | content: crop_type, growth_stage: 0, growth_timer: 0, fully_grown_timer: 0}
    else
      field
    end
  end

  def water(field) do
    %{field | watered: true}
  end

  def harvestable?(field) do
    field.content != :empty && field.growth_stage == 4
  end

  def harvest(field) do
    if harvestable?(field) do
      multiplier = if field.watered, do: 2, else: 1

      resources =
        case field.content do
          :wheat -> %{wheat: 1 * multiplier}
          :grass -> %{grass: 1 * multiplier}
          _ -> %{}
        end

      {resources,
       %{
         field
         | content: :empty,
           growth_stage: 0,
           growth_timer: 0,
           fully_grown_timer: 0,
           watered: false
       }}
    else
      {%{}, field}
    end
  end

  def plow(field) do
    if field.content == :grass do
      %{field | content: :empty, growth_stage: 0, growth_timer: 0, fully_grown_timer: 0}
    else
      field
    end
  end
end

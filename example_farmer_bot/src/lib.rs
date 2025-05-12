#[allow(warnings)]
mod bindings;

use bindings::{
    Action, BotState, Buyable, EntityType, FarmState, Field, Guest, PlantType, Sellable,
    bot_action, buy, sell,
};

struct Component;

impl Guest for Component {
    fn tick(bot: BotState) {
        let farm = resource_maintenance(&bot).unwrap_or_else(|e| {
            bindings::log(&format!("Error: {}", e), bindings::LogLevel::Error);
            bindings::get_farm()
        });

        if matches!(bot.current_action, Action::Idle) {
            let serviceable_fields = serviceable_fields(&bot, farm);

            // Process the closest field
            if let Some((target_x, target_y, work)) = serviceable_fields.first() {
                let dx = *target_x - bot.position.x as i32;
                let dy = *target_y - bot.position.y as i32;

                if dx == 0 && dy == 0 {
                    // We're at the target field, do the work
                    match work {
                        Work::Watering => {
                            bot_action(Action::Water);
                        }
                        Work::Harvesting => {
                            bot_action(Action::Harvest);
                        }
                        Work::Seeding => {
                            bot_action(Action::Seed(PlantType::Wheat));
                        }
                    }
                } else if bot.energy > 100 {
                    // Move towards the target
                    if dx.abs() > dy.abs() {
                        // Move horizontally
                        if dx > 0 {
                            bot_action(Action::MoveRight);
                        } else {
                            bot_action(Action::MoveLeft);
                        }
                    } else {
                        // Move vertically
                        if dy > 0 {
                            bot_action(Action::MoveDown);
                        } else {
                            bot_action(Action::MoveUp);
                        }
                    }
                }
            }
        }
    }
}

fn serviceable_fields(bot: &BotState, farm: FarmState) -> Vec<(i32, i32, Work)> {
    let mut serviceable_fields = Vec::new();

    for distance in 0..=3 {
        for dx in -distance..=distance {
            for dy in -distance..=distance {
                // Skip if not on the current ring's edge
                if (dx != distance && dx != -distance) && (dy != distance && dy != -distance) {
                    continue;
                }

                let x = bot.position.x as i32 + dx;
                let y = bot.position.y as i32 + dy;

                // Skip invalid coordinates
                if x < 0 || y < 0 || x >= farm.fields_width as i32 || y >= farm.fields_height as i32
                {
                    continue;
                }

                if let Some(current_field) = field_at(&farm, x as u32, y as u32) {
                    if let Some(work) = needs_work(current_field, bot) {
                        // ignore if another bot is already on this field
                        //  with a 40% chance - this is to prevent bots from dancing around each other
                        let random_uniform = rand::random::<f64>();
                        let skip_chance = if matches!(work, Work::Harvesting)
                            && matches!(current_field.plant, Some(plant) if plant.plant_type == PlantType::Grass)
                        {
                            let distance = (x - bot.position.x as i32).abs() + (y - bot.position.y as i32).abs();
                            distance as f64 * 0.15
                        } else {
                            0.0
                        };

                        if random_uniform < skip_chance {
                            continue;
                        }

                        if current_field.entities.iter().any(|entity| {
                            entity.entity_type == EntityType::Bot && entity.id != bot.id
                        }) && random_uniform > skip_chance
                        {
                            continue;
                        }

                        serviceable_fields.push((x, y, work));
                    }
                }
            }
        }
    }

    // Sort by Manhattan distance
    serviceable_fields.sort_by_key(|&(x, y, ref work)| {
        let dx = (x - bot.position.x as i32).abs();
        let dy = (y - bot.position.y as i32).abs();
        let distance = dx + dy;
        let distance_modifier = match work {
            Work::Harvesting => -1,
            Work::Watering => 1,
            _ => 0,
        };
        distance + distance_modifier
    });

    serviceable_fields
}

fn field_at(farm: &FarmState, x: u32, y: u32) -> Option<&Field> {
    farm.fields
        .get(y as usize)
        .and_then(|row| row.get(x as usize))
}

#[derive(Debug)]
enum Work {
    Watering,
    Harvesting,
    Seeding,
}

fn needs_work(field: &Field, bot: &BotState) -> Option<Work> {
    if let Some(plant) = field.plant {
        if plant.growth_stage == plant.growth_stage_max {
            return Some(Work::Harvesting);
        }

        if !field.watered
            && bot.energy > 100
            && bot.water > 0
            && plant.growth_stage > plant.growth_stage_max / 2
            && plant.plant_type != PlantType::Grass
        {
            return Some(Work::Watering);
        }

        return None;
    }

    if bot.energy > 80 && bot.seeds > 0 {
        Some(Work::Seeding)
    } else {
        None
    }
}

fn resource_maintenance(bot: &BotState) -> Result<FarmState, String> {
    if bot.energy < 150 {
        buy(Buyable::Energy, 25)?;
    }
    if bot.water < 1 {
        buy(Buyable::Water, 25)?;
    }
    if bot.seeds < 1 {
        buy(Buyable::Seeds, 1)?;
    }

    let farm = bindings::get_farm();
    if farm.grass > 0 {
        sell(Sellable::Grass, farm.grass)?;
    }
    if farm.wheat > 0 {
        sell(Sellable::Wheat, farm.wheat)?;
    }
    Ok(farm)
}

bindings::export!(Component with_types_in bindings);

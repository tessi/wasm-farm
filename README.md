# Wasm Farm

This is a farm game built with Phoenix/LiveView and WebAssembly.

<img src="https://github.com/tessi/wasm-farm/blob/main/wasm_farm.png?raw=true" alt="Wasm Farm Screenshot" width="600"/>

The goal of the game is to create a farm and seed, harvest, and sell crops.
However, you can not directly do this. You need to control a farm bot which
does the work for you - but every action needs energy. Can you manage to
grow your farm efficient enough to finance your bots energy needs?

Each farm is identified by a unique id. Share this id (or the farms url) with your friends to play together on the same farm.

If you get tired of manually operating your bot, automate it!
Build a bot program in a WebAssembly (Wasm) component. Implement the
interface described in `wasm_farmer_bot.wit` and spawn one or a whole
swarm of them to farm for you.

## Running the game

The game consists of two parts:

1. A Phoenix server that runs the game logic and serves the frontend.
2. An example WebAssembly component (written in Rust) that runs an example bot

To start the Phoenix server, run:

```bash
cd farm_server
mix deps.get
mix phx.server
```

and visit [`localhost:4000/farms`](http://localhost:4000/farms) from your browser to create and join a farm. Each farm can be visited by multiple players to play together.

To build the Wasm component bot, follow [the installation instructions for Rust Wasm component support](https://component-model.bytecodealliance.org/language-support/rust.html) and then run:

```bash
cd example_farmer_bot
cargo component build --release
```

This will create the `wasm_farmer_bot.wasm` file in the `example_farmer_bot/target/wasm32-wasip1/release` directory.












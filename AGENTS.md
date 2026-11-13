# Working in Fitness Tracker

- Read the [docs index](docs/README.md) for setup and project references. For app UI changes, use [PRODUCT.md](PRODUCT.md) and [DESIGN.md](DESIGN.md).
- Keep workout data local. Test with fictional records. When changing storage, follow the [migration steps](docs/development.md#change-the-database-schema) and check the [data formats](docs/data-formats.md).
- Run the relevant [host checks](docs/testing.md#run-host-checks) without waiting for a device choice. If a change needs a device and the user has not specified a target, ask which platform and emulator, simulator, or device to use. Continue work that does not depend on the answer.
- If `.local/testing.md` exists, read it for the user's saved device preferences. A current instruction takes precedence. Use [the example](docs/local-testing.example.md) when the user asks to save a choice. Keep machine paths, device IDs, and personal notes out of tracked files.
- Use the [screenshot command](docs/screenshots.md) when asked to refresh the README gallery. It uses a disposable iOS simulator with fictional data. Ask before running separate device checks if the target is unclear.
- Use the [official Flutter and Dart skills](docs/agent-setup.md) when relevant. Apply the project's architecture and test conventions when an upstream example uses a different stack.
- State which checks ran and which were skipped. Commit, push, or open a pull request only when the user asks.

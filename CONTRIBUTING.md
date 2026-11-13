# Contributing to Fitness Tracker

Bug reports, documentation fixes, and focused pull requests are welcome. For a larger change to app behavior, storage, or data formats, open an issue first so we can agree on the scope.

## Report a problem

Search existing issues first. For bugs, include the app version, platform and OS version, steps to reproduce, and the expected and actual results. For a feature request, describe the problem you want to solve and when you encounter it.

Use fictional workout data in examples. Remove names, profile photos, personal records, and credentials from logs and screenshots. Use the [private reporting instructions](SECURITY.md) for suspected security vulnerabilities. Follow the [code of conduct](CODE_OF_CONDUCT.md) when participating.

## Make and check a change

1. Install Flutter using the [local setup](README.md#run-locally). The [host checks](docs/testing.md#run-host-checks) are enough to get started. Set up Android or iOS when you need to run the app.
2. Keep the change focused. Add or update tests when behavior changes. Read the [development guide](docs/development.md) before changing the database or platform assets.
3. Run the relevant [checks](docs/testing.md). For UI or native changes, state the platform and device you checked. If you could not run a device check, say so.
4. Update affected docs. If one of the four README screens changed, [refresh the screenshots](docs/screenshots.md) on a Mac or note in the pull request that a maintainer should refresh them.

## Open a pull request

Describe what changed, why it matters, and how you checked it. Link any related issue and attach before and after images if they help explain a UI change. Flag changes to migrations, exports, or backup compatibility for reviewers.

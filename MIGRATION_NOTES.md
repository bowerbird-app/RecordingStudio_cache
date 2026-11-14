# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 6.1.0` (root and dummy GitHub tag `v6.14.0`). Dummy `config.authorize_write` uses Accessible; seeds bootstrap owner access before child recordings.
- Dummy includes Recording Studio migration `20261114090000_add_root_recording_id_to_recording_studio_events`. Core 6.9+ requires `recording_studio_events.root_recording_id` before events can be written. Core 6.11 through 6.14 add no further migrations.
- Accessible dummy tag `v0.41.0` (Accessible 0.40+ needs Recording Studio `>= 6.13.0`)
- Trashable dummy tag `v0.15.0` (`require: false`; Accessible loads `recording_studio_trashable/query` only)
- Root Switchable dummy tag `v0.15.0` (switcher lists Accessible `:view` roots)
- Metrics dummy tag `v0.8.0` (required by Root Switchable and Trashable; not on RubyGems)
- FlatPack tag `v0.1.374` (`>= 0.1.315`). Not a runtime dependency of this gem.
- `view_component` `>= 4.14, < 5` (via FlatPack)
- Public RubyGems and GitHub access for dependency installation
- For Redis-backed generation tests: `REDIS_URL` and the `redis` gem (dev/test)

## Verification

Install both bundles and run the complete gem and dummy app test path:

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```

Run the dummy app from its directory for browser verification:

```bash
cd test/dummy
bin/dev
```

Use the [FlatPack repository](https://github.com/bowerbird-app/flatpack) and the live FlatPack demo linked from the top-level README for current component documentation.

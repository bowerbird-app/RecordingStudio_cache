# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 6.1.0` (root and dummy GitHub tag `v6.1.0`)
- Accessible dummy tag `v0.22.0`
- Trashable dummy tag `v0.12.0` (`require: false`; Accessible loads `recording_studio_trashable/query` only)
- Root Switchable dummy tag `v0.11.0`
- Metrics dummy tag `v0.6.1` (required by Root Switchable and Trashable; not on RubyGems)
- FlatPack `0.1.319` at ref `1fcbafe94f8eb118f0a22182f63f5110fcc97a56` (`>= 0.1.315`). Not a runtime dependency of this gem.
- `view_component` `>= 4.14, < 5` (via FlatPack)
- Metrics `v0.6.1` still declares `recording_studio` `~> 4.2`. `test/support/widen_recording_studio_requirement.rb` relaxes that before Bundler setup so `6.1.0` resolves. Load it from the dummy Gemfile, `test/dummy/config/boot.rb`, and the Rakefile.
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

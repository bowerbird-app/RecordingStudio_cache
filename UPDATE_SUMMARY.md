# Recording Studio kit pin update

Copied addons now start on Recording Studio 6.1 and FlatPack 0.1.319.

- Gemspec: `add_dependency "recording_studio", ">= 6.1.0"`
- `flat_pack` stays out of this gemspec. Root and dummy Gemfiles pin `bowerbird-app/flatpack` ref `1fcbafe94f8eb118f0a22182f63f5110fcc97a56`.
- Dummy GitHub tags: Recording Studio `v6.1.0`, Accessible `v0.22.0`, Trashable `v0.12.0`, Root Switchable `v0.11.0`, Metrics `v0.6.1`
- `RecordingStudioCache::Configuration#layout` defaults to `nil` and accepts values through `RecordingStudio::Layout.accept`
- Authenticated dummy screens call `recording_studio_layout`. Devise keeps the `"application"` layout.
- Page headings use `content_for :title` and `content_for :subtitle`. Back/close uses `flat_pack_page_nav`. Right-side actions use `register_page_nav`.
- Metrics `v0.6.1` still caps `recording_studio` below 5. `test/support/widen_recording_studio_requirement.rb` lets Bundler activate 6.1.0.
- Hooks and BaseService come from core. Do not copy them into a new addon.
- Recordable declarations remain required.
- RecordingStudioCache is headless: no example capability, no engine UI mount, no addon pages migration, no Redis or Solid Cache runtime dependency.

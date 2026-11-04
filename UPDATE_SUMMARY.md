# Recording Studio kit pin update

Copied addons now start on Recording Studio 6.3 and FlatPack 0.1.341. The gemspec floor stays `recording_studio >= 6.1.0`.

- Gemspec: `add_dependency "recording_studio", ">= 6.1.0"`
- `flat_pack` stays out of this gemspec. Root and dummy Gemfiles pin `bowerbird-app/flatpack` tag `v0.1.341`.
- Dummy GitHub tags: Recording Studio `v6.3.0`, Accessible `v0.24.0`, Trashable `v0.12.0`, Root Switchable `v0.11.3`, Metrics `v0.7.1`
- `RecordingStudioCache::Configuration#layout` defaults to `nil` and accepts values through `RecordingStudio::Layout.accept`
- Authenticated dummy screens call `recording_studio_layout`. Devise keeps the `"application"` layout.
- Page headings use `content_for :title` and `content_for :subtitle`. Back/close uses `flat_pack_page_nav`. Right-side actions use `register_page_nav`.
- Hooks and BaseService come from core. Do not copy them into a new addon.
- Recordable declarations remain required.
- RecordingStudioCache is headless: no example capability, no engine UI mount, no addon pages migration, no Redis or Solid Cache runtime dependency.

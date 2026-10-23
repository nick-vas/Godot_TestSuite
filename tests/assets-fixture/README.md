Fixture for doctor's asset and pixel-art checks, used by `tests/Test-AssetManifest.ps1`. The test copies it and creates
the files the manifest describes (empty files: doctor reads only names), plus `.import` files as Godot writes them. It covers
one file of each licence problem (non-commercial, GPL, an unrecognised licence, an attribution licence, no entry, a manifest
entry with no source) and, since the project declares pixel art (Nearest filter), a sprite with mipmaps and one with VRAM
compression. Commissioned work: one entry with its paperwork (`art/enemy`), one with no agreement (`art/boss`), one with no
rights (`art/logo.png`), one licence with no uses (`music/theme.ogg`) and one licence with its uses (`music/menu.ogg`). An MPL-2.0 shader
(`shaders/noise.gdshader`). Placeholders: one in progress and due in 2099 (`art/stand_in`), one past due
(`audio/boss_theme.ogg`), one with a due date and a status that are not valid (`art/title.png`). Add-ons the test writes: one
with an MIT `LICENSE` and no entry (`addons/tween_kit`, for which doctor suggests the entry), one covered (`addons/covered`),
GUT (left out) and one without a licence file.

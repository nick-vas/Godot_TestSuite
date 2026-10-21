Fixture for doctor's asset and pixel-art checks, used by `tests/Test-AssetManifest.ps1`. The test copies it and creates
the files the manifest describes (empty files: doctor reads only names), plus `.import` files as Godot writes them. It covers
one file of each licence problem (non-commercial, GPL, an unrecognised licence, an attribution licence, no entry, a manifest
entry with no source) and, since the project declares pixel art (Nearest filter), a sprite with mipmaps and one with VRAM
compression.

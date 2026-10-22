# Self-hosted runners

The workflow and the action run on your own machines as they do on GitHub's: Linux, Windows or macOS with PowerShell
7.2+ and Git (Git LFS for `lfs: true`). `setup` installs Godot, its templates and, on Linux and macOS, the .NET SDK when
it is missing. What differs is that the machine keeps its files between jobs.

**Labels.** A runner registers with `self-hosted` and its OS and architecture (`Linux`, `X64`, ...); add your own when
you configure it (`./config.sh --labels godot`) and pass that one label to the workflow: `runs-on: godot`. A label that
only Godot machines carry keeps other repositories' jobs off them. With `run-exports: true` the export jobs still go to
`windows-latest` and `ubuntu-latest` to launch each build on its own OS, and iOS presets to `macos-latest`; to keep those
on your machines too, call the action from a workflow of your own.

**One workspace per runner.** Each registered runner works in its own `_work` folder and runs one job at a time. Run
several on one machine by registering each in its own folder, never two in one folder: two jobs would check out, import
and export into the same project. Godot's import cache (`.godot/`) is removed with the checkout's `git clean`, so
each job imports from scratch unless the action's import cache restores it.

**`~/.godot-ci` persists.** Godot and the kit's tools stay in `~/.godot-ci` (`GODOT_TOOLS_DIR` moves it), the export
templates in Godot's own folder (`~/.local/share/godot/export_templates`, `%APPDATA%\Godot\export_templates`,
`~/Library/Application Support/Godot/export_templates`), and NuGet packages in `~/.nuget/packages`. A second run finds
Godot and its templates and does not download them, so the action's cache steps are redundant there: they still restore
from and save to GitHub's cache over the network. Install the .NET 8 SDK on the machine itself (the kit's own install,
in `~/.godot-ci/dotnet`, is only on the `PATH` of the job that installed it). A Godot you installed yourself works too: set
`GODOT_BIN` in the runner's environment (exports then need its templates in the folder above).

**Disk clean-up.** Each Godot version and flavour (.NET or standard) adds a folder to `~/.godot-ci`, and each version's
templates take about a gigabyte. Delete the folders of versions you no longer use; the next run that needs one downloads
it again. Exports go to the job's temporary folder, which the runner empties after each job. An ephemeral runner
(`./config.sh --ephemeral`, one job and then it unregisters) starts clean every time, and then the cache steps are useful
again.

**Not for public repositories.** A pull request from a fork runs its own code on the machine, with whatever the machine
can reach; GitHub recommends self-hosted runners only for private repositories.

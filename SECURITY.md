# Security

The kit downloads Godot and tools from their official release locations, runs your project's code (tests execute it), and in
workflows uses the permissions the calling workflow grants. Run it only on code you trust, and give workflows the minimum
(`contents: read`; add `pull-requests: write` for the comment and `contents: write` only for releases). Do not commit signing keys or
store credentials; use Actions secrets.

Report vulnerabilities privately through GitHub's "Report a vulnerability" on this repository.

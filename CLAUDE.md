# Working on Spinforge

Read [README.md](README.md), [PROJECT.md](PROJECT.md) and, if present, [HANDOFF.md](HANDOFF.md) first. Update PROJECT.md
after meaningful work. Keep parts and designs original (no Beyblade names, designs or wiki data).

- Game rules live in `src/shared/Core/` as pure modules (no Roblox APIs) so they can be unit-tested. Keep it that way.
- After editing `src/`: run `python3 tools/run_tests.py` (needs the `luau` CLI on PATH) and regenerate the installer
  with `python3 tools/make_installer.py`. The tests fail if the committed installer is out of date.
- The smoke test runs the real scripts in a small Roblox mock (`tools/tests/roblox_mock.luau`). It proves wiring and
  logic, not physics or feel.
- Nothing has been verified in Roblox Studio unless the owner says so: say what was tested automatically, what is
  implemented but engine-unverified, and what is deferred. Never claim the feel works.
- Paid purchases stay disabled until the crate checklist in PROJECT.md is done.

# tools/replay — offline decision-logic harness

Runs the mod's real `main.lua` outside the game and feeds it recorded (or invented) sequences of
hit-react activations and damage events, then checks what it decided to suppress.

```bash
bash tools/replay/run.sh
```

Needs a Lua 5.x interpreter. If `lua` isn't on PATH, point at one: `LUA=/path/to/lua ./run.sh`.
Pass a different Scripts directory as `$1` to test a specific build — including one extracted from a
`dist/` zip, which is worth doing before shipping.

## Why this exists

The only real test of this mod is a manual in-game launch on someone else's machine, which costs a
day of round trip. Every bug found so far has been a **sub-millisecond ordering** bug — the kind
where the code is obviously correct right up until you see the timestamps. So the goal is to arrive
at each launch with the logic already as correct as it can be made from a desk.

## How it works

`main.lua` reaches the world through `RegisterHook` and UObject wrappers: every hook argument is
something you call `:get()` on, and every name comes back through
`GetClass():GetFName():ToString()`. None of that needs a game — it needs objects that answer the
same calls. [`stub.lua`](stub.lua) supplies them, along with a controllable `os.clock`, and then
`dofile`s the real unmodified `main.lua`.

- [`timelines.lua`](timelines.lua) — tester rounds transcribed verbatim from `UE4SS.log`, with the
  original timestamps, so inter-event gaps are the real ones. Each records how many activations that
  session *should* end up suppressing.
- [`scenarios.lua`](scenarios.lua) — synthetic cases that no log contains yet, mostly pinning down
  the edges of the v0.1.7 look-behind window.

Both exit non-zero on failure, so they work as a regression gate.

## What it proves, and what it doesn't

**Proves:** given a sequence of events, which ones the mod classifies into which family, and which
activations it decides to cancel. That is exactly where the v0.1.6 bug lived — and the harness
reproduces that bug from the recorded timeline, including its `expired unresolved (412 ms)` line,
before it reproduces the fix. A harness that can independently produce the known-bad answer is worth
trusting about the known-good one.

**Does not prove:** that `K2_CancelAbility` actually stops the montage rendering; that the hook
targets resolve against real UFunctions (they're strings here); that `GetAbilitySystemComponentFromActorInfo`
or gameplay-tag reads work on-box; or that a timing case exists which no log has yet shown. A green
run means "ship it to the tester", never "it works".

## Adding a round

Append a new entry to `timelines.lua` rather than editing an old one — previous rounds are the
regression cover. Transcribe the `activate:` and `damage:` lines with their timestamps; the damage
type spec is `{ class, super, full }`, all three printed on every `damage:` line.

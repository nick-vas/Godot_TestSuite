---
name: godot-llm
description: Use when a Godot game calls a large language model at run time, such as NPC dialogue, a coach or narrator, generated quests, items or descriptions, or players typing free text that a model answers.
---

# A language model inside the game (Godot 4.7, C#)

From Google for Games' GenAI-quickstart (an NPC chat with retrieval, a persona chat, Guess-the-Sketch) and homerun (a
baseball "coach" demo); the provider-specific parts (Vertex, Gemini, Spanner) are left out. Notes:
`${CLAUDE_PLUGIN_ROOT}/docs/googleforgames.md`. Steam asks about generative AI in its Content Survey (`godot-legal`).

## 1. The game's code is the referee

- The model proposes; code decides. homerun let the model compute the baseball outcome and carried about 30 hand-written
  rules in its prompt ("a home run NEVER results in an out"), each one a patch for a wrong answer. Its client applied
  the model's game state without checking it.
- So: keep the state and the rules in code. Ask the model to choose from a list of legal options (by index or id), or to
  word something the code has already decided. Parse its output into a record and reject anything outside the list.
- Ask for sections with tags (`<tactics>`, `<outcome>`) or JSON, and show each one as soon as it is complete. homerun
  shows the options before the outcomes have finished streaming.

## 2. Never wait on it

- Give every call a hard deadline, and have a fallback ready that the player cannot tell apart from a normal answer:
  canned lines, the last good answer, or a fixed choice. Guess-the-Sketch gives its scoring call 1 s, then carries on.
  homerun has no deadline: the game idles until the model answers.
- Start the next call while the current outcome animates. homerun asks for every combination of choices at once (nine
  outcomes for three choices a side), so a choice needs no new call.
- Never block the frame: `await` the HTTP call from a `Task`, and apply the result on the main thread.

## 3. What goes into the prompt

- A byte budget, enforced. The NPC chat caps the prompt at 6,500 bytes and keeps the last 10 messages. When over, it
  drops the oldest pair of messages first, never the facts.
- Keep where each fact came from: "You know..." for what the NPC saw, "You have heard..." with "X said: ..." for what
  others told it. The NPC can then doubt gossip, and the game can trace a wrong answer.
- Retrieve only facts close to the question (the sample uses at most 3, with an embedding distance under 0.5), not the
  whole world.
- The persona says what the character may not do: claim to be an AI, leave its place, know the future. The game must
  still check the output.
- Player text is data, never instructions. The persona chat put the player's own "character description" into the
  system context, so a player could rewrite the rules. Put player text only in the user turn, quoted, and cap its
  length.

## 4. Players and safety

- For a public or children's build, offer a menu of prompts instead of free text. Guess-the-Sketch's `LIMITED_PROMPTS`
  mode offers three fixed choices.
- Do not turn the provider's safety filters off: homerun sets all four Gemini categories to `BLOCK_NONE`. Filter what the
  model says, and filter what players type before it reaches the model; chat moderation is `godot-servers`.
- Show an acceptable-use note before free text (Guess-the-Sketch's consent page), and tell players a model wrote the
  answers.

## 5. Keys, cost and debugging

- The API key lives on a server you control, never in the client: homerun embeds one in its JavaScript, where anyone can
  read it. The game calls your server, and your server calls the provider, checks the player, and limits the rate per
  player (`RateLimiter`, `godot-servers`).
- Cache what repeats (descriptions of the same item, the same NPC greeting), and set a monthly spending cap with the
  provider. Neither sample has a cache or a cap.
- Version the prompts (homerun names them like `TACTICS_SELECTION_20250317_011`) and log each call's prompt version,
  input, output and time taken. A wrong answer can then be replayed, and a prompt change compared on the same inputs.

## 6. Prove it

- Unit-test the parser and the legal-move check on recorded model outputs, including truncated, empty and off-list
  ones.
- Run the game with the model replaced by the fallback, and by an answer that arrives after the deadline: both must
  play normally.
- Before a release, run a fixed set of inputs through the real model and diff the answers against the last release.

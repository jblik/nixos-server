# AI backend — Ollama vs llama.cpp

The question was "why Ollama, and should it be llama.cpp instead?". Short answer:
**on this box, llama.cpp — driven by llama-swap — is the better fit**, and the reason is
specifically that the GPU is shared. Keep both behind one option so the choice is
reversible.

## 1. Why Ollama was chosen originally

It is not a bad default, and the reasons still stand:

- `services.ollama.enable = true` and you are done.
- Model registry: `ollama pull qwen3` — no hunting for GGUF files or picking a quant.
- Automatic model load/unload (`keep_alive`) and hot-swapping between models per
  request, which is what makes Open WebUI's model dropdown work.
- OpenAI-compatible `/v1`, so every client just works.

## 2. What Ollama actually costs you here

- **It is a vendored fork of llama.cpp, and it lags upstream.** New model
  architectures, new quant formats and performance work land in llama.cpp first; Ollama
  picks them up later. You are running an older llama.cpp with a nicer wrapper.
- **VRAM management is a heuristic you cannot see.** Ollama decides how many layers to
  offload. That is fine on a dedicated GPU. On a card that is *simultaneously* running
  Immich ML and Plex NVENC, "it usually gets it right" turns into an OOM during a photo
  import or a failed transcode mid-stream.
- **Limited control over the flags that buy you VRAM.** KV-cache quantization,
  flash attention, explicit context size, batch and parallel settings — the levers that
  decide whether a 14B model fits in your remaining ~9 GB — are either unavailable or
  awkward environment variables.
- **Opaque model storage.** Models live in Ollama's own blob store under its own
  naming, not as GGUF files you chose. Pinning an exact quant means fighting the tool.
- **Its defaults are conservative.** Default context is small; people routinely run
  models at a fraction of their useful context without realising it.

None of this matters on a machine whose only job is LLM inference. All of it matters on
a machine where the GPU is a contended resource — which is exactly this one.
See [ARCHITECTURE.md](ARCHITECTURE.md) §3.

## 3. The llama.cpp path is first-class on NixOS

This is the part that changes the calculus. Verified present in the pinned
`nixos-26.05`:

- **`services.llama-cpp`** — `package`, `model`, `modelsDir`, `host`, `port`,
  `extraFlags`, `openFirewall`. Runs one `llama-server`.
- **`services.llama-swap`** — a proxy in front of llama.cpp with freeform YAML
  `settings`: a `models` map where each entry has its own `cmd`, `aliases`, `ttl` and
  optional `proxy`. It starts a `llama-server` on demand, serves the OpenAI API,
  exposes `/v1/models`, and stops an instance after its TTL expires.

llama-swap is the missing piece. It gives you the two things Ollama was actually
providing — pick-a-model-from-a-dropdown and unload-when-idle — while every model entry
is a full `llama-server` command line you control completely.

So the trade is no longer "convenience vs control". It is "someone else's heuristic vs
your explicit configuration", with the same ergonomics either way.

## 4. Why explicit control wins on a 12 GB shared card

The VRAM budget, roughly:

```
  12.0 GB  RTX 3060
 - 2.0 GB  Immich ML while indexing (CLIP + face detection)
 - 0.8 GB  Plex NVENC, a couple of concurrent transcodes
 - 0.5 GB  driver / headroom
 ─────────
 ≈ 8.7 GB  actually available to an LLM
```

With llama.cpp you set that budget rather than discover it:

- `-ngl N` — offload exactly N layers, keep the rest on CPU. Deterministic.
- `--ctx-size` — context is a real VRAM cost; choose it instead of inheriting it.
- `--cache-type-k q8_0 --cache-type-v q8_0` — quantized KV cache, often the difference
  between 8k and 32k context fitting on the same card.
- `--flash-attn` — supported on Ampere; less memory, faster.
- llama-swap `ttl` — the model unloads when idle, so a photo-import burst or a Plex
  transcode gets the VRAM back automatically.
- Any GGUF from Hugging Face at the exact quant you picked, no registry in between.

## 5. Recommendation

**Make the backend an option, default it to llama-swap, keep Ollama as one line away.**

```nix
host.ai.backend = "llama-swap";   # or "ollama"
```

Both expose the same OpenAI-compatible API on the same port, so Open WebUI and every
other client are unaffected by the choice. This means:

- Nothing about the migration blocks on this decision.
- If llama-swap misbehaves, `host.ai.backend = "ollama"` and rebuild.
- The GPU-release hook stops whichever unit is active, not a hardcoded `ollama.service`.

**Phasing:** during the server migration, run whichever is already working — the AI
backend is the least critical service on the box. Flip to llama-swap once the storage
and media stacks are stable. It is a config change, not a project.

## 6. Practical notes

**Build times.** Both `ollama-cuda` and a CUDA-enabled `llama-cpp`
(`llama-cpp.override { cudaSupport = true; }`) are unfree CUDA builds that the official
NixOS cache does not carry. Without a binary cache these compile locally, and on a
2700X that is *hours*. Add the CUDA community cache before the first rebuild:

```nix
nix.settings = {
  substituters = [ "https://cuda-maintainers.cachix.org" ];
  trusted-public-keys = [
    "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
  ];
};
```

**Model sizing on ~8.7 GB.** As a rule of thumb at `Q4_K_M`: an 8B model needs roughly
5 GB and leaves room for long context; a 12–14B model lands around 8–9 GB and needs
quantized KV cache to keep useful context; anything ≥24B requires `Q3` and a short
context, which usually costs more quality than the extra parameters buy. Check current
model releases at the time you configure this rather than trusting a list in a doc.

**Keep Open WebUI either way.** It talks to an OpenAI-compatible endpoint; it does not
care what is behind it.

**One endpoint, not two.** Do not run Ollama and llama-swap simultaneously "to compare"
— they will both try to allocate the GPU and you will spend an evening debugging OOMs
instead of comparing anything.

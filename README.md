# ai_basalt

My [Basalt](https://github.com/jesdga95/basalt) setup, shared between machines: Basalt pinned as a
submodule, plus one run config per hardware tier. It mirrors
[ai_strata](https://github.com/countzero/ai_strata) for the same model, so both servers can be
compared on one machine. Basalt runs only on NVIDIA Blackwell cards (sm_120). Model files live
outside the repository; each tier file names their paths.

## Usage

Start the server:

```
pwsh -NoExit -File <repo>\start.ps1
```

`<repo>` is where you cloned this repository. With several tier files, name one with
`-tier <tier>`. `start.ps1` checks that the engine is built, that the tier file's model exists and
that port 8084 is free; it never stops another server on it. ai_strata keeps port 8083, and each
tier file reports the model name of the matching ai_strata tier (`alias`), so a client switches
servers by its port alone. A tier file sets `"host": "0.0.0.0"`, so every device
on the network can use the server. A tier file sets no API key: clients need none, and the server
warns about it once at start.

## Tiers

Medians of `.\benchmark.ps1` (Strata's `tools\strata_bench.py`, default suite, 3 runs each, copied
into `tools\strata`) against a running server. The Strata rows are ai_strata's on the same machine.

| Tier file                                                  | Hardware                                                  | Server            | Chat decode | 16K prompt | Agent decode | Agent cache hit |
| ---------------------------------------------------------- | --------------------------------------------------------- | ----------------- | ----------- | ---------- | ------------ | --------------- |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM` | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores | Basalt `b6125f60` | 76.0 tok/s  | 3433 tok/s | 93.1 tok/s   | 71.1 %          |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM` | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores | Strata v0.2.4.2   | 73.6 tok/s  | 2555 tok/s | 50.0 tok/s   | 69.5 %          |

The Basalt row is one run without *Lock pages in memory*; its nine chat samples decoded at
70.5-79.6 tok/s. At `8d73a394` the chat decode was split between fast and slow runs, with medians
of 35.7 tok/s chat decode, 3263 tok/s 16K prompt and 58.7 tok/s agent decode. A Strata run of the same day gave 73.2 tok/s chat decode,
2568 tok/s 16K prompt and 46.2 tok/s agent decode.

## New machine

Needs Visual Studio 2022 with *Desktop development with C++*, the CUDA Toolkit 13 or newer with
its `bin\x64` on the PATH, Python 3.10 or newer, and PowerShell 7.

1. `git clone --recurse-submodules <url of this repository> <repo>`
2. `.\update_basalt.ps1 -commit (git -C vendor\basalt rev-parse HEAD)`: it creates
   `vendor\basalt\.venv` and builds the engine into `vendor\basalt\bin\` (the first build takes
   a long time). The build records the checkout's path: after moving `<repo>`, run it again.
3. Build the model pack as *Model pack* says, and copy the nearest tier file to a new tier name.
4. Optional, needs administrator rights: grant your account *Lock pages in memory*
   (`secpol.msc` -> *Local Policies* -> *User Rights Assignment*), then sign out and in. The engine
   then keeps its pinned memory in large pages instead of falling back to 4 KiB pages. Strata uses
   the privilege too.

## Model pack

Basalt reads one `.basalt` file per model. Its official packs have no UD-IQ4_XS, so the tier
converts Unsloth's GGUF, which ai_strata already uses, with the drafter, draft vocabulary and expert
profile from the official repository. The experts are copied byte for byte, so the quality is
ai_strata's.

1. Download the converter inputs (about 6 GiB) next to the GGUF:

   ```
   hf download jesdga/Qwen3.8-Flash-Next-Basalt --include "convert/mtp/*" --local-dir <models>\basalt
   hf download jesdga/Qwen3.8-Flash-Next-Basalt convert/draft_vocab.bin convert/profile.bin --local-dir <models>\basalt
   ```

2. Convert (90.3 GiB, about 12 minutes). In `vendor\basalt`:

   ```
   .\.venv\Scripts\python.exe tools\convert\convert.py --gguf <models>\UD-IQ4_XS\Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf --mmproj <models>\mmproj-BF16.gguf --mtp-source <models>\basalt\convert\mtp --mtp-dense <models>\basalt\convert\mtp\rt\dense.bin --draft-vocab <models>\basalt\convert\draft_vocab.bin --profile <models>\basalt\convert\profile.bin --compat-bf16 --name "Qwen3.8-Flash-Next UD-IQ4_XS" --out <models>\basalt\Qwen3.8-FN-UD-IQ4_XS.basalt
   ```

   `--compat-bf16` converts the hyper-connection matrices, which the GGUF stores as Q8_0, to the
   BF16 the engine reads. The converter warns that a pack built this way is slower than the official
   ones: it lacks the official 8-bit hyper-connection copies, which the engine then makes at every
   start.

## Update Basalt

1. Stop the server.
2. `.\update_basalt.ps1`, or `.\update_basalt.ps1 -commit <sha|main>`. Without `-commit` it takes
   the newest commit of upstream's `main` whose `ci` run passed. It checks out the commit in
   `vendor\basalt`, installs Basalt's Python packages and builds the engine (the old `bin\` goes to
   `build\bin.previous\`). Read the changes it links: upstream renames and removes settings, and an
   unknown key in a tier file stops the server.
3. Start, check that the model loads, and run `.\benchmark.ps1`. It writes to
   `.tmp\bench\basalt-<commit>\` and prints the numbers for *Tiers*; `-compare .tmp\bench\<older
   folder>` puts an earlier run beside it, also one of ai_strata. VRAM taken by other programs
   lowers the numbers: when they differ from the old row, run the old commit in the same session
   before calling it a regression. Put the numbers in *Tiers*.
4. `git add vendor/basalt presets README.md` and commit as "Update Basalt to <short sha>".

Rollback: `git checkout <last commit> -- presets`, then
`.\update_basalt.ps1 -commit (git ls-tree <last commit> vendor/basalt).Split()[2]`.

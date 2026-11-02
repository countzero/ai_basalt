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

Medians of Strata's `tools\strata_bench.py` (default suite, copied into `tools\strata`) against a
running server, 3 runs per row: Basalt through `.\benchmark.ps1`, Strata through ai_strata's, one
server at a time.

| Tier file                                                  | Hardware                                                  | Server            | Chat decode | 16K prompt | Agent decode | Agent cache hit |
| ---------------------------------------------------------- | --------------------------------------------------------- | ----------------- | ----------- | ---------- | ------------ | --------------- |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM` | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores | Basalt `a04edb96` | 77.5 tok/s  | 3307 tok/s | 99.3 tok/s   | 71.1 %          |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM` | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores | Strata v0.2.9     | 74.7 tok/s  | 2780 tok/s | 84.4 tok/s   | 69.1 %          |

Both rows ran on driver 597.30, on the migrated version 2 pack, one server at a time. The
`71116cc3` row they replace gave 78.1 tok/s chat decode, 3438 tok/s 16K prompt, 118.3 tok/s agent
decode and 70.9 % cache hit through `.\experiment.ps1`, the `v0.2.4.2` row of Strata 73.6, 2555,
50.0 and 69.5. Chat decode stays within the same day's baseline spread of 71.1-75.1 tok/s, agent
decode within 84.4-98.4 tok/s, and 16K prompt reads 4 % lower: it was not re-measured on `71116cc3`
in the same session, so that is not called a regression. Without `"ple-io": "ram"` the first prompt after
start reads at about 2090 tok/s. Agent decode varies by turn, from about 50 to over 170 tok/s
within one run.

## Try other engine settings

`.\experiment.ps1` measures the tier with changed engine settings, one arm at a time: the tier as
it is (first and last), `ple-io ram`, `pool-affinity p-cores`, `vram-reserve-mib 700`,
`kv-resident 32768`, and `custom` with the settings given as `-custom @{ "name" = value }`. It
starts each arm from a throwaway config under `.tmp\bench\experiment-<date>\` on `127.0.0.1` in a
hidden window, and stops it afterwards. It refuses to start while port 8084 is taken or another
program uses the GPU, and never stops a server it did not start. `-check` only writes and checks
the configs; `-arms baseline,pleram` runs a part. `summary.md` in the run folder holds the table.

`vram-reserve-mib 700` and `kv-resident` gave no clear gain, and both change which experts the GPU
rounds. `relaxed-drafting 0.5` (`basalt-bench`, sampled fixtures, two runs each) raised draft
acceptance by up to 4 points but decode speed only within the noise. It changes the sampled
output, so the tier leaves it off.

## New machine

Needs Visual Studio 2022 with *Desktop development with C++*, the CUDA Toolkit 13 or newer with
its `bin\x64` on the PATH, Python 3.10 or newer, and PowerShell 7.

1. `git clone --recurse-submodules <url of this repository> <repo>`
2. `.\update_basalt.ps1 -commit (git -C vendor\basalt rev-parse HEAD)`: it creates
   `vendor\basalt\.venv` and builds the engine into `vendor\basalt\bin\` (the first build takes
   a long time). The build records the checkout's path: after moving `<repo>`, run it again.
3. Build the model pack as *Model pack* says, and copy the nearest tier file to a new tier name.
4. Optional, needs administrator rights: grant your account *Lock pages in memory*
   (`secpol.msc` -> *Local Policies* -> *User Rights Assignment*), then sign out and in. No account
   holds it by default. It does not give this tier large pages: the experts it keeps in RAM are
   ordinary memory registered with the driver, which stays in 4 KiB pages. Strata uses the
   privilege.

## Model pack

Basalt reads one `.basalt` file per model. Its official packs have no UD-IQ4_XS, so the tier
converts Unsloth's GGUF, which ai_strata already uses, with the drafter, draft vocabulary and expert
profile from the official repository. The experts are copied byte for byte, so the quality is
ai_strata's.

1. Download the converter inputs (about 6 GiB) next to the GGUF:

   ```
   hf download jesdga/Qwen3.8-Flash-Next-Basalt --include "convert/mtp/*" --local-dir <models>\basalt
   hf download jesdga/Qwen3.8-Flash-Next-Basalt convert/draft_vocab.bin --local-dir <models>\basalt
   ```

2. Convert (90.3 GiB, about 12 minutes). In `vendor\basalt`:

   ```
   .\.venv\Scripts\python.exe tools\convert\convert.py --gguf <models>\UD-IQ4_XS\Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf --mmproj <models>\mmproj-BF16.gguf --mtp-source <models>\basalt\convert\mtp --mtp-dense <models>\basalt\convert\mtp\rt\dense.bin --draft-vocab <models>\basalt\convert\draft_vocab.bin --compat-bf16 --name "Qwen3.8-Flash-Next UD-IQ4_XS" --out <models>\basalt\Qwen3.8-FN-UD-IQ4_XS.basalt
   ```

   `--compat-bf16` converts the hyper-connection matrices, which the GGUF stores as Q8_0, to the
   BF16 the engine reads, and the converter writes the pack's `hc8` section from them: the table the
   engine used to compute at every start. The converter still warns that a self-converted pack is
   slower than an official one, which it says of a pack without the official drafter; this one
   copies it. The expert profile is no longer a converter input: the engine ships it as
   `data\profiles\qwen4exp-48x512.prof`.

## Update Basalt

1. Stop the server.
2. `.\update_basalt.ps1`, or `.\update_basalt.ps1 -commit <sha|main>`. Without `-commit` it takes
   the newest commit of upstream's `main` whose `ci` run passed. It checks out the commit in
   `vendor\basalt`, installs Basalt's Python packages and builds the engine (the old `bin\` goes to
   `build\bin.previous\`). The build shows one progress line with the time left, predicted from
   the previous build's step times, and only errors; the full compiler output, warnings included,
   goes to `.tmp\build\basalt-<commit>.log`. Read the changes it links: upstream renames and
   removes settings, and an unknown key in a tier file stops the server.
3. Start, check that the model loads, and run `.\benchmark.ps1`. A start that refuses the pack's
   `.basalt` version names its migration in `vendor\basalt\tools\migrations\`: migrate the pack,
   do not re-convert it, and keep room for a second copy of the file; the weights are copied byte
   for byte. It writes to
   `.tmp\bench\basalt-<commit>\` and prints the numbers for *Tiers*; `-compare .tmp\bench\<older
   folder>` puts an earlier run beside it, also one of ai_strata. VRAM taken by other programs
   lowers the numbers: when they differ from the old row, run the old commit in the same session
   before calling it a regression. Put the numbers in *Tiers*.
4. `git add vendor/basalt presets README.md` and commit as "Update Basalt to <short sha>".

Rollback: `git checkout <last commit> -- presets`, then
`.\update_basalt.ps1 -commit (git ls-tree <last commit> vendor/basalt).Split()[2]`.

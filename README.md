# ai_basalt

My [Basalt](https://github.com/jesdga95/basalt) setup, shared between machines: Basalt pinned as a
submodule, plus one run config per hardware tier. For Qwen3.8-Flash-Next it mirrors
[ai_strata](https://github.com/countzero/ai_strata), so both servers can be compared on one
machine; Inkling 2 Mini runs only here. Basalt runs only on NVIDIA Blackwell cards (sm_120). Model files live
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
servers by its port alone. A tier without one reports `<model>-<quant>` from its file name, such as
`inkling-2-mini-nvfp4-q8`. A tier file sets `"host": "0.0.0.0"`, so every device
on the network can use the server. A tier file sets no API key: clients need none, and the server
warns about it once at start. Images from other devices must come as base64 `data:` URLs; an image
URL or file path from them gets a 400 unless its host is listed in `image-url-host` or its folder
in `image-dir`, which the tier files leave unset.

## Tiers

Medians of Strata's `tools\strata_bench.py` (default suite, copied into `tools\strata`) against a
running server, 3 runs per row: Basalt through `.\benchmark.ps1`, Strata through ai_strata's, one
server at a time.

| Tier file                                                  | Hardware                                                  | Server            | Chat decode | 16K prompt | Agent decode | Agent cache hit |
| ---------------------------------------------------------- | --------------------------------------------------------- | ----------------- | ----------- | ---------- | ------------ | --------------- |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM` | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores | Basalt `a388da24` | 73.0 tok/s  | 3464 tok/s | 97.9 tok/s   | 71.1 %          |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM` | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores | Strata v0.2.9     | 74.7 tok/s  | 2780 tok/s | 84.4 tok/s   | 69.1 %          |
| `inkling-2-mini.nvfp4-q8.24GB_VRAM_192GB_RAM`              | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores | Basalt `a388da24` | 149.3 tok/s | 4731 tok/s | 143.8 tok/s  | 69.3 %          |

The Basalt rows ran on driver 621.14, the Strata row on 597.30. The `f19f69e6` row the Qwen row
replaces gave 69.0 tok/s chat decode, 3400 tok/s 16K prompt and 119.9 tok/s agent decode. Agent
decode varies by turn and by run (63-156 tok/s within this run, 96-120 tok/s as the median of
earlier ones), so its drop is not a regression; the others did not fall. The first benchmark after
start is the one recorded: later ones on the same server read chat decode anywhere in 54-70 tok/s.
Without `"ple-io": "ram"` the first prompt after start reads at about 2090 tok/s.

The Inkling tier runs `kv fp8`. Against `fp16` (`experiment.ps1`, 5 runs, same session) it read
16K prompts at 4703 instead of 3641 tok/s, decoded agent turns at 158.1 instead of 136.5 tok/s and
answered a chat question in 0.18 instead of 0.49 s. With `fp16` the engine plans for the full
context and keeps 276 of the 3,072 experts in RAM, so every 4,096-token prompt chunk copies them
over the bus again; with `fp8` every expert sits on the card until a conversation's caches need the
room. Upstream measured no quality figure for `fp8`; it finds needles at 131K and 400K with it. A
shorter context gains little more: `max-context` 131072 and 65536, the latter without any expert
in RAM, read 16K prompts at 4814 and 4850 tok/s, so prompts top out near 4,800 tok/s on this card
(an RTX 5090 reads 12,310). `spec 4` and `vram-reserve-mib`, which Inkling does not read, changed
nothing. Inkling re-reads 325 tokens per agent session, Qwen 5: the benchmark cuts each reply at
64 tokens and sends no thinking back, so the server cannot continue the turn it left.

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

Basalt reads one `.basalt` file per model and loads no GGUF: a tier's pack is converted here or
downloaded.

### Qwen3.8-Flash-Next

The tier converts Unsloth's GGUF, which ai_strata already uses, with the drafter, draft vocabulary
and expert profile from the official repository. The experts are copied byte for byte, so the
quality is ai_strata's. When the tier was set up the official packs had no UD-IQ4_XS; Basalt
`46f1e3ff` added one (`jesdga/Qwen3.8-Flash-Next-Basalt`), not yet compared with this pack.

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

### Inkling 2 Mini

Thinking Machines released Inkling 2 Mini only in NVFP4 and MXFP8, the precision it was trained
in; there are no BF16 weights. The converter keeps the NVFP4 experts of layers 0-19 bit for bit,
rounds the MXFP8 experts of layers 20-23 and the attention projections to Q8_0, and takes the
drafter, vision encoder, tokenizer and template from the release: no other input. Needs Basalt
0.5.5 (`ff0b978d`) or later.

1. Download the release (20.2 GB, 14 files) at its first commit, which the official pack was built
   from, into a folder named `Inkling-2-Mini`, whose name the pack records:

   ```
   hf download thinkingmachines/Inkling-2-Mini --revision 1fb4134b9a74f9681054f4ef82e4bf1f458a2337 --local-dir <models>\Inkling-2-Mini
   ```

   Not with `git clone`: Git for Windows sets `core.autocrlf=true` and writes the release's text
   files, the chat template among them, with Windows line endings, which the converter copies into
   the pack. A clone needs `git -c core.autocrlf=false clone`.

2. Convert (18.4 GiB, about 2.5 minutes). The converter puts its temporary files in `%TEMP%`. In
   `vendor\basalt`:

   ```
   $env:TEMP = $env:TMP = (New-Item -ItemType Directory -Force <repo>\.tmp\convert).FullName
   .\.venv\Scripts\python.exe tools\convert\convert.py --checkpoint <models>\Inkling-2-Mini --name "Inkling 2 Mini" --out <models>\basalt\Inkling-2-Mini-NVFP4-q8.basalt
   ```

The pack is then byte for byte the official one, `jesdga/Inkling-2-Mini-Basalt` (SHA-256
`f7b4e5f8e17681c4735a7dfc51ffd8e805c44184fad4e1778b13187d79dc3787`), so downloading that gives the
same file. The release's next commit, `ed40e7da`, only adds `"dtype"` to `config.json`, which the
converter does not read but records in `meta`: from it the file hash differs.

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
   for byte. A start that refuses a tier file's config version names its migration there too: run
   it on every tier file and replace the tier file with its output, under the same name. A start
   that stops with `merge 0 names a token outside the vocabulary: 'Ġ Ġ\r'` means a pack converted
   before Basalt `6749fc77`, whose tokenizer has Windows line endings: convert it again as *Model
   pack* says, with `--force`. The benchmark writes to
   `.tmp\bench\basalt-<commit>\` and prints the numbers for *Tiers*; `-compare .tmp\bench\<older
   folder>` puts an earlier run beside it, also one of ai_strata. VRAM taken by other programs
   lowers the numbers: when they differ from the old row, run the old commit in the same session
   before calling it a regression. Put the numbers in *Tiers*.
4. `git add vendor/basalt presets README.md` and commit as "Update Basalt to <short sha>".

Rollback: `git checkout <last commit> -- presets`, then
`.\update_basalt.ps1 -commit (git ls-tree <last commit> vendor/basalt).Split()[2]`.

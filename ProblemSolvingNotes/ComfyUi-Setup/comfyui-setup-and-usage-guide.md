# ComfyUI Setup and Usage Guide

This guide summarizes a practical Linux-based ComfyUI setup and troubleshooting workflow for running ComfyUI in a Python virtual environment, fixing dependency problems, and using ComfyUI for basic image editing with inpainting.[cite:73][cite:233]

## Folder layout
A clean manual install typically separates the project folder and the virtual environment, then launches ComfyUI from the project using the venv’s Python interpreter.[cite:73]

Example layout used here:

```text
~/MyScripts/LocalRepos/runway/comfyui/
├── .venv/
└── ComfyUI/
```

In this structure, `.venv` contains the Python environment and `ComfyUI/` contains the cloned application source including `main.py` and `requirements.txt`.[cite:73]

## Python version
ComfyUI dependency compatibility is more reliable on Python 3.12 than Python 3.13 for several users, especially where `torchvision` and related compiled components are involved.[cite:283][cite:250]

On Arch Linux, the practical way to keep Python 3.12 alongside the system Python is to install the `python312` AUR package and use `python3.12` explicitly for the ComfyUI virtual environment.[cite:101][cite:319][cite:103]

Example install methods on Arch:

```bash
yay -S python312
```

or

```bash
git clone https://aur.archlinux.org/python312.git
cd python312
makepkg -si
```

Verify it with:

```bash
python3.12 --version
```

## Create the virtual environment
A venv should be created only once, then reused on later launches.[cite:73][cite:378]

From the parent folder:

```bash
cd ~/MyScripts/LocalRepos/runway/comfyui
python3.12 -m venv .venv
```

Activate it with:

```bash
source .venv/bin/activate
```

Confirm the active interpreter before installing anything:

```bash
which python
python --version
python -m pip --version
python -c "import sys; print(sys.executable)"
```

The Python path should point into `.venv/bin/python`, not `/usr/bin/python` or another system path.[cite:73][cite:326]

## Important Arch Linux note
Arch uses PEP 668 protection for the system Python environment, so bare `pip install ...` may fail with `externally-managed-environment` if the shell is using the wrong interpreter or wrong `pip` executable.[cite:326][cite:327]

Inside this setup, the safe pattern is to always use:

```bash
python -m pip ...
```

instead of bare `pip ...`, because `python -m pip` guarantees that pip runs in the currently selected interpreter environment.[cite:326][cite:347]

## Start ComfyUI after reboot
After a reboot, the venv is no longer active automatically. The usual fix is to reactivate the venv before launching ComfyUI.[cite:378][cite:381]

Use this every time:

```bash
cd ~/MyScripts/LocalRepos/runway/comfyui
source .venv/bin/activate
cd ComfyUI
python main.py
```

If ComfyUI reports missing packages like `sqlalchemy`, that usually means the wrong Python was used or the active environment is incomplete.[cite:379][cite:375]

## Make startup easier
A small shell script avoids repeating the commands manually.[cite:378][cite:380]

Create `start-comfy.sh` in the parent folder:

```bash
#!/bin/bash
cd ~/MyScripts/LocalRepos/runway/comfyui
source .venv/bin/activate
cd ComfyUI
python main.py
```

Make it executable:

```bash
chmod +x start-comfy.sh
```

Then start ComfyUI with:

```bash
./start-comfy.sh
```

## Installing dependencies
ComfyUI’s manual install process uses `requirements.txt` from inside the `ComfyUI/` directory, not the parent folder.[cite:73]

Run:

```bash
cd ~/MyScripts/LocalRepos/runway/comfyui
source .venv/bin/activate
cd ComfyUI
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r requirements.txt
```

If a core dependency such as `sqlalchemy` is missing, reinstalling the requirements in the active venv is the normal fix.[cite:379][cite:375]

## PyTorch installation guidance
ComfyUI’s dependencies can pull in a very large modern CUDA stack, and newer wheels may target CUDA 13-era packages, which increases disk usage dramatically during installation.[cite:351][cite:356]

A separate manual install of `torch` and `torchvision` inside the venv is often used when controlling the CUDA build explicitly.[cite:73][cite:297]

Example pattern:

```bash
python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
```

In this conversation, `torchaudio` repeatedly caused trouble and was not necessary for basic image-generation use, so avoiding it was the preferred path unless audio-specific nodes are required.[cite:251][cite:244]

## Torchaudio and audio-related issues
ComfyUI imported audio-related modules that pulled in `torchaudio`, which then caused CUDA runtime mismatches or missing-wheel issues.[cite:241][cite:242]

When `torchaudio` was absent or incompatible, the practical workaround was to disable the audio-related import path so image workflows could still run.[cite:275][cite:281]

A lightweight patch in `comfy/sd.py` can make the audio import optional:

```python
try:
    import comfy.ldm.lightricks.vae.audio_vae
except Exception as e:
    logging.warning(f"Audio VAE disabled: {e}")
```

This works because the crash happened at import time, while the audio VAE module itself depends on `torchaudio` and audio-specific processing functionality.[cite:275][cite:281]

## Torchvision and Python 3.13 issues
A major source of breakage was Python 3.13 combined with incomplete or mismatched `torchvision` support, especially for compiled modules like `torchvision.ops`.[cite:283][cite:288]

That is why the environment was moved to Python 3.12 and rebuilt cleanly rather than patched indefinitely.[cite:250][cite:283]

## When pip says packages are not installed
If `python -m pip uninstall -y torch torchvision torchaudio` says packages are not installed even though ComfyUI logs show PyTorch activity, the environment is likely inconsistent or partially reset.[cite:338][cite:344]

In that case, the most reliable recovery is to rebuild the venv from scratch instead of chasing individual leftovers.[cite:344][cite:233]

Typical rebuild flow:

```bash
deactivate
rm -rf .venv
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
cd ComfyUI
python -m pip install -r requirements.txt
```

## Disk quota / no space problems
Installing recent PyTorch builds can download several very large wheels including CUDA runtime packages, cuDNN, NCCL, Triton, and related dependencies, which can exceed temporary storage quotas.[cite:356][cite:351]

A practical workaround is to move pip’s temporary directory and clear the pip cache before retrying.[cite:353][cite:354]

Example:

```bash
mkdir -p ~/pip-tmp
export TMPDIR=~/pip-tmp
python -m pip cache purge
python -m pip install -r requirements.txt
```

If needed, also clear old pip cache files:

```bash
rm -rf ~/.cache/pip
rm -rf ~/pip-tmp/*
```

## Typical launch checklist
Use this quick checklist each time ComfyUI fails to start:

1. Confirm the venv is activated.[cite:378][cite:73]
2. Confirm `which python` points to `.venv/bin/python`.[cite:73]
3. Run `python -m pip --version` and ensure it points into the same `.venv`.[cite:326]
4. Launch from inside the `ComfyUI/` directory where `main.py` and `requirements.txt` exist.[cite:73]
5. If a core package is missing, run `python -m pip install -r requirements.txt` in the active venv.[cite:379][cite:375]

## Using ComfyUI to edit an image
For changing part of an existing image, the standard ComfyUI method is **inpainting**: load the image, paint a mask over the region to change, prompt for the replacement, then generate.[cite:205][cite:366][cite:363]

### Basic node set
A minimal inpainting workflow typically uses these nodes:[cite:205][cite:363]

- `Load Checkpoint`
- `Load Image`
- `CLIP Text Encode` for positive prompt
- `CLIP Text Encode` for negative prompt
- `VAE Encode (for Inpainting)` or `Set Latent Noise Mask`
- `KSampler`
- `VAE Decode`
- `Save Image`

### Basic editing steps
1. Add `Load Image` and choose the source image.[cite:205][cite:363]
2. Right-click the image node and open the Mask Editor.[cite:205]
3. Paint over only the area to be changed.[cite:366][cite:373]
4. Save the mask back to the node.[cite:205]
5. Write a prompt that describes the replacement content only.[cite:366]
6. Generate and adjust denoise if needed.[cite:366][cite:373]

### Starter settings
Good initial inpainting settings are commonly:[cite:366]

- Steps: 20 to 30
- CFG: 7 to 9
- Denoise: 0.3 to 0.5 for subtle edits
- Denoise: 0.7 to 1.0 for larger replacements

A slightly larger mask than the target object often improves blending at the edges.[cite:366][cite:373]

## Editing text in a document image
ComfyUI can remove or alter printed text via inpainting, but exact letter-perfect text generation is unreliable with standard diffusion models.[cite:205][cite:366]

For document edits, the practical workflow is usually:

1. Mask the old text.[cite:205]
2. Inpaint the area to restore the paper/background texture.[cite:366]
3. Add the new text afterward in a normal editor for sharp, accurate lettering.[cite:205][cite:366]

A useful prompt for removing a word from a document image is:

```text
clean white paper background, printed document texture
```

A helpful negative prompt is:

```text
blurry, warped letters, extra text
```

## Practical usage advice for a 4 GB GPU
A Quadro P1000-class GPU is usable for lightweight image work, but it benefits from simple workflows, smaller models, and avoiding unnecessary extras.[cite:168][cite:205]

For this kind of setup, the safest practical approach is:

- Use Python 3.12 instead of 3.13.[cite:283]
- Keep ComfyUI inside a dedicated venv.[cite:73]
- Avoid `torchaudio` unless you need audio features.[cite:251][cite:244]
- Use standard image workflows such as SD 1.5-style inpainting rather than heavy experimental stacks.[cite:205][cite:366]
- Expect limited VRAM headroom and prefer minimal workflows.[cite:168]

## Copy-paste startup commands
These are the most useful everyday commands from this setup.

Activate and launch:

```bash
cd ~/MyScripts/LocalRepos/runway/comfyui
source .venv/bin/activate
cd ComfyUI
python main.py
```

Reinstall requirements in the correct venv:

```bash
cd ~/MyScripts/LocalRepos/runway/comfyui
source .venv/bin/activate
cd ComfyUI
python -m pip install -r requirements.txt
```

Check the active interpreter:

```bash
which python
python --version
python -m pip --version
python -c "import sys; print(sys.executable)"
```

Use a larger temp directory for heavy installs:

```bash
mkdir -p ~/pip-tmp
export TMPDIR=~/pip-tmp
python -m pip cache purge
```

## Troubleshooting summary
The recurring pattern across the setup was not ComfyUI itself, but environment mismatch: wrong Python version, wrong pip, missing activation after reboot, optional audio imports causing hard failures, and very large PyTorch dependencies exhausting temporary storage.[cite:73][cite:233][cite:326][cite:351]

The stable path that emerged was:

- install Python 3.12 on Arch via `python312`.[cite:101][cite:319]
- create one dedicated `.venv`.[cite:73]
- always activate it before launch.[cite:378]
- run installs with `python -m pip`.[cite:326]
- reinstall `requirements.txt` when core modules are missing.[cite:379]
- use inpainting for editing images, especially for selective changes.[cite:205][cite:366]


## GPU compatibility update for Quadro P1000
A later test showed that ComfyUI could start successfully, but generation failed at `KSampler` with `torch.AcceleratorError: CUDA error: no kernel image is available for execution on the device`.[cite:389]

The system log identified the GPU as a **Quadro P1000** with compute capability **6.1 (sm_61)**, while the installed PyTorch build was `2.13.0+cu130` and only included kernels for newer architectures such as sm_75, sm_80, sm_86, sm_90, sm_100, and sm_120.[cite:389]

That means the installation was launching correctly, but the PyTorch CUDA build itself was not compatible with the P1000’s Pascal-era architecture.[cite:389][cite:405]

### What suits the P1000
NVIDIA’s legacy CUDA capability listing places the Quadro P1000 in the **compute capability 6.1** family.[cite:405] The P1000 is a Pascal GPU with 4 GB of GDDR5 VRAM and is better suited to lightweight image-generation workflows than newer, heavier model stacks.[cite:404][cite:414]

For this card, the practical target is an **older CUDA-enabled PyTorch wheel** that still includes `sm_61` support. The most sensible first choice is **cu118**, followed by **cu121** if needed.[cite:416][cite:413]

### Exact recovery steps for the P1000
If ComfyUI starts but crashes when sampling on the GPU, use these steps exactly:

```bash
cd ~/MyScripts/LocalRepos/runway/comfyui
source .venv/bin/activate
cd ComfyUI
python -m pip uninstall -y torch torchvision torchaudio
python -m pip cache purge
python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

Then verify the install:

```bash
python -c "import torch; print(torch.__version__); print(torch.version.cuda); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0)); print(torch.cuda.get_device_capability(0))"
```

The expected result is that CUDA is available, the device name is `Quadro P1000`, and the device capability reports `(6, 1)`.[cite:404][cite:405]

If `cu118` still fails, retry with `cu121`:

```bash
python -m pip uninstall -y torch torchvision torchaudio
python -m pip cache purge
python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```

### Workflow caution
One failing workflow mixed a **Z-Image-Turbo / AuraFlow** template with an SD1.5 checkpoint loader and also showed prompt-validation errors for missing `model` and `vae` inputs before the CUDA crash.[cite:389]

For this machine, the safer first test is a plain SD1.5 workflow instead of the heavier or mixed template stack.[cite:389][cite:205]

Use this minimal graph for testing:

- `CheckpointLoaderSimple`
- `CLIPTextEncode`
- `EmptyLatentImage`
- `KSampler`
- `VAEDecode`
- `SaveImage`

### Suggested starter settings for the P1000
For the first successful GPU test, keep the workload small:[cite:205][cite:404]

- Model: SD1.5 checkpoint
- Resolution: 512x512 or 768x768
- Steps: 20
- CFG: 7
- Use a standard text-to-image workflow only

### CPU fallback
If GPU compatibility is still unresolved, ComfyUI can be launched in CPU mode to confirm the rest of the environment is correct, though performance will be much slower.[cite:73]

```bash
cd ~/MyScripts/LocalRepos/runway/comfyui
source .venv/bin/activate
cd ComfyUI
python main.py --cpu
```

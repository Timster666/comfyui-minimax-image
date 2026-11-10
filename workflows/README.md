# ComfyUI + MiniMax-H3-Image — RunPod template

A RunPod pod template that boots straight into ComfyUI with the
[Comfy-Org/MiniMax-H3-Image](https://huggingface.co/Comfy-Org/MiniMax-H3-Image) text-to-image models.

- ComfyUI (latest at build time) + ComfyUI-Manager + JupyterLab (no password), PyTorch for CUDA 13.0
- Choose which model files download with true/false environment variables — no rebuild needed
- Models download to `/workspace` on first boot; files already there are skipped on later boots

## Model switches

| Variable | Default | File | Size |
|---|---|---|---|
| **Diffusion models** (pick at least one) | | | |
| `DIT_W4A8` | `false` | `minimax_h3_image_pruned_w4a8` | 12.5 GB |
| `DIT_INT8` | `true` | `minimax_h3_image_pruned_int8_convrot` | 21.0 GB |
| `DIT_BF16` | `false` | `minimax_h3_image_pruned_bf16` | 40.2 GB |
| **Text encoders** (pick at least one Qwen3-VL 32B) | | | |
| `TE_NVFP4` | `true` | `qwen3vl_32b_minimax_h3_nvfp4_awq` | 15.7 GB |
| `TE_INT8` | `false` | `qwen3vl_32b_minimax_h3_int8_convrot` | 27.1 GB |
| `PROMPT_ENHANCER` | `true` | `qwen3.5_9b_w4a8_gptq` (for the Generate Text node) | 7.3 GB |
| **VAE** | always | `minimax_h3_image_vae_fp16` | small |

Defaults download about **44 GB**. Everything switched on is about **124 GB**.
The NVFP4 text encoder does **not** need a Blackwell GPU.

## Other environment variables

| Variable | Default | Options |
|---|---|---|
| `SKIP_DOWNLOAD` | `false` | `true` starts ComfyUI without checking models |
| `COMFY_ARGS` | *(empty)* | Extra ComfyUI flags, e.g. `--lowvram` |
| `ENABLE_JUPYTER` | `true` | `false` turns JupyterLab off |
| `JUPYTER_PASSWORD` | *(empty)* | Empty = JupyterLab opens with no login |
| `HF_TOKEN` | *(empty)* | Hugging Face token, if downloads are rate-limited |

## RunPod template settings

| Field | Value |
|---|---|
| Container image | `timster666/comfyui-minimax:vN` (version from the GitHub Actions summary) |
| Container disk | 30 GB |
| Volume disk | 75 GB for the defaults (≈150 GB if you switch everything on) |
| Volume mount path | `/workspace` |
| HTTP ports | `8188` (ComfyUI), `8888` (Jupyter) |
| TCP ports | `22` (SSH) |

Deploy with the **CUDA version filter at 13.0+**.

**GPU:** this is a big model. A **48 GB card** (L40S, A6000) or larger is recommended for the defaults.
On a 32 GB RTX 5090, or to save memory, use `DIT_W4A8=true` and `DIT_INT8=false`.
Pick a pod with plenty of system RAM (64 GB+), since ComfyUI moves the text encoder out of VRAM
after encoding the prompt.

## Where things live

| Path | Persists on volume |
|---|---|
| `/workspace/models/...` | ✅ models (add your own LoRAs to `/workspace/models/loras`) |
| `/workspace/ComfyUI/output` | ✅ generated images |
| `/workspace/ComfyUI/user` | ✅ saved workflows & settings |
| `/opt/ComfyUI/custom_nodes` | ❌ nodes installed via Manager are lost on pod reset |

JupyterLab opens in `/workspace`. A new terminal opens in the folder the file browser shows.

## Workflows

Put workflow `.json` files in this repo's `workflows/` folder. They're built into the image and
appear in ComfyUI's **Workflows** panel on every new pod. You can also check
**Workflow → Browse Templates** in ComfyUI for an official MiniMax-H3-Image workflow.

## Updating

Every change to `Dockerfile`, `start.sh`, `extra_model_paths.yaml` or `workflows/` on GitHub
rebuilds the image. **Actions → Build and push image → Run workflow** rebuilds without changes,
which also picks up the newest ComfyUI.

## License

The MiniMax-H3 weights use the **MiniMax H3 Community License Agreement** — check its terms
before any commercial use: <https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/LICENSE>

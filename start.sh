#!/usr/bin/env bash
# Startup script for the ComfyUI + MiniMax-H3-Image RunPod template.
set -euo pipefail

WS="${WORKSPACE:-/workspace}"
COMFY="$WS/ComfyUI"            # the whole ComfyUI install lives on the volume
MODELS="$COMFY/models"
REPO="Comfy-Org/MiniMax-H3-Image"

# ---- Model switches (set true/false as RunPod environment variables) -------
# Diffusion models — pick at least one
DIT_W4A8="${DIT_W4A8:-false}"               # minimax_h3_image_pruned_w4a8          12.5 GB
DIT_INT8="${DIT_INT8:-true}"                # minimax_h3_image_pruned_int8_convrot  21.0 GB
DIT_BF16="${DIT_BF16:-false}"               # minimax_h3_image_pruned_bf16          40.2 GB
# Text encoders — pick at least one of the two Qwen3-VL 32B files
TE_NVFP4="${TE_NVFP4:-false}"               # qwen3vl_32b_minimax_h3_nvfp4_awq      15.7 GB
TE_INT8="${TE_INT8:-true}"                  # qwen3vl_32b_minimax_h3_int8_convrot   27.1 GB
PROMPT_ENHANCER="${PROMPT_ENHANCER:-true}"  # qwen3.5_9b_w4a8_gptq (Generate Text)   7.3 GB
# VAE (minimax_h3_image_vae_fp16) is always downloaded — every workflow needs it.

# ---- Other settings ---------------------------------------------------------
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"
UPDATE_COMFYUI="${UPDATE_COMFYUI:-false}"    # true = git pull ComfyUI + Manager on boot
INSTALL_NODE_REQS="${INSTALL_NODE_REQS:-true}" # reinstall custom nodes' Python packages on boot
COMFY_ARGS="${COMFY_ARGS:-}"                 # extra flags, e.g. --lowvram
ENABLE_JUPYTER="${ENABLE_JUPYTER:-true}"     # JupyterLab on port 8888
JUPYTER_PASSWORD="${JUPYTER_PASSWORD:-}"     # optional login token; empty = opens with no login
# -----------------------------------------------------------------------------

# SSH (RunPod injects PUBLIC_KEY from your account settings)
if [[ -n "${PUBLIC_KEY:-}" ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
  ssh-keygen -A >/dev/null 2>&1 || true
  /usr/sbin/sshd || echo "[start] sshd failed to start (continuing)"
fi

mkdir -p "$WS"

# ---- ComfyUI on the volume --------------------------------------------------
# First boot: copy the ComfyUI install from the image to /workspace/ComfyUI, the
# same layout as most ComfyUI templates (custom_nodes, models, input, output...).
# Later boots reuse it, so custom nodes and settings survive.
if [[ ! -f "$COMFY/main.py" ]]; then
  echo "[start] First boot: copying ComfyUI to $COMFY ..."
  mkdir -p "$COMFY"
  cp -an /opt/ComfyUI/. "$COMFY/"    # -n: never overwrite input/output/user already there
fi

# Older versions of this template kept models in /workspace/models — move them in.
if [[ -d "$WS/models" && ! -L "$WS/models" ]]; then
  echo "[start] Moving models from $WS/models to $MODELS ..."
  for d in "$WS/models"/*/; do
    [[ -d "$d" ]] || continue
    mkdir -p "$MODELS/$(basename "$d")"
    cp -anl "$d". "$MODELS/$(basename "$d")/" 2>/dev/null || cp -an "$d". "$MODELS/$(basename "$d")/"
  done
  rm -rf "$WS/models"
fi

# JupyterLab — started before the model download so it's usable right away.
# Launched from $WS on purpose: Jupyter resolves a new terminal's folder against
# its OWN working directory first, so starting it anywhere else sent terminals to
# the wrong folder — the MOSS bug.
if [[ "$ENABLE_JUPYTER" == "true" ]]; then
  echo "[start] Starting JupyterLab on port 8888"
  (cd "$WS" && nohup jupyter lab --ip='*' --port=8888 --no-browser --allow-root \
    --IdentityProvider.token="$JUPYTER_PASSWORD" --ServerApp.password='' \
    --ServerApp.allow_origin='*' --ServerApp.allow_remote_access=True \
    --ServerApp.disable_check_xsrf=True --ServerApp.root_dir="$WS" \
    > /var/log/jupyter.log 2>&1 &)
fi

mkdir -p "$MODELS"/{diffusion_models,text_encoders,vae,loras,checkpoints,controlnet,upscale_models,embeddings,clip_vision} \
         "$COMFY/output" "$COMFY/input" "$COMFY/user" "$COMFY/custom_nodes"

# ---- Optional update + Python packages --------------------------------------
if [[ "$UPDATE_COMFYUI" == "true" ]]; then
  echo "[start] Updating ComfyUI and ComfyUI-Manager ..."
  git -C "$COMFY" pull --ff-only || echo "[start] ComfyUI update failed (continuing)"
  git -C "$COMFY/custom_nodes/ComfyUI-Manager" pull --ff-only 2>/dev/null || true
fi
# Keep the image's Python packages in step with the ComfyUI version on the volume
pip install -q -r "$COMFY/requirements.txt" || echo "[start] ComfyUI requirements install failed (continuing)"
# Custom nodes' Python packages live in the image, not on the volume, so a new
# pod needs them reinstalled.
if [[ "$INSTALL_NODE_REQS" == "true" ]]; then
  for req in "$COMFY"/custom_nodes/*/requirements.txt; do
    [[ -f "$req" ]] || continue
    echo "[start] Installing packages for custom node: $(basename "$(dirname "$req")")"
    pip install -q -r "$req" || echo "[start]   failed (continuing)"
  done
fi

# Bundled workflows → ComfyUI's Workflows panel. Never overwrites a workflow
# you've edited and saved under the same name.
WF_DIR="$COMFY/user/default/workflows"
mkdir -p "$WF_DIR"
for wf in /opt/default_workflows/*.json; do
  [[ -e "$wf" ]] || continue
  if [[ ! -e "$WF_DIR/$(basename "$wf")" ]]; then
    cp "$wf" "$WF_DIR/" && echo "[start] Added workflow: $(basename "$wf")"
  fi
done

# ---- Build the file list from the switches ----------------------------------
FILES=()
is_on() { [[ "${1,,}" == "true" || "$1" == "1" || "${1,,}" == "yes" ]]; }

is_on "$DIT_W4A8" && FILES+=("diffusion_models/minimax_h3_image_pruned_w4a8.safetensors")
is_on "$DIT_INT8" && FILES+=("diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors")
is_on "$DIT_BF16" && FILES+=("diffusion_models/minimax_h3_image_pruned_bf16.safetensors")
is_on "$TE_NVFP4" && FILES+=("text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors")
is_on "$TE_INT8"  && FILES+=("text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors")
is_on "$PROMPT_ENHANCER" && FILES+=("text_encoders/qwen3.5_9b_w4a8_gptq.safetensors")
FILES+=("vae/minimax_h3_image_vae_fp16.safetensors")

is_on "$DIT_W4A8" || is_on "$DIT_INT8" || is_on "$DIT_BF16" || \
  echo "[start] !!! No diffusion model selected (DIT_W4A8 / DIT_INT8 / DIT_BF16 are all false)."
is_on "$TE_NVFP4" || is_on "$TE_INT8" || \
  echo "[start] !!! No Qwen3-VL text encoder selected (TE_NVFP4 / TE_INT8 are both false)."

# ---- Download (skips files already on the volume) ---------------------------
wait_for_network() {
  # Pod networking can take a few seconds to come up after the container starts.
  for i in $(seq 1 60); do
    getent hosts huggingface.co >/dev/null 2>&1 && return 0
    echo "[start] Waiting for network ($i/60)..."
    sleep 2
  done
  return 1
}

missing_files() {
  local f
  for f in "${FILES[@]}"; do [[ -s "$MODELS/$f" ]] || echo "$f"; done
}

if [[ "$SKIP_DOWNLOAD" != "true" ]]; then
  export HF_HUB_DISABLE_TELEMETRY=1
  if ! wait_for_network; then
    echo "[start] !!! No network after 2 minutes — skipping model download."
  else
    for attempt in 1 2 3; do
      mapfile -t TODO < <(missing_files)
      (( ${#TODO[@]} == 0 )) && break
      echo "[start] Downloading ${#TODO[@]} file(s) from $REPO (attempt $attempt) ..."
      hf download "$REPO" "${TODO[@]}" --local-dir "$MODELS" || true
    done
  fi

  # Verify — hf can report success without downloading when it's offline.
  mapfile -t STILL_MISSING < <(missing_files)
  if (( ${#STILL_MISSING[@]} )); then
    echo "[start] !!! These model files are MISSING:"
    printf '[start] !!!   %s\n' "${STILL_MISSING[@]}"
    echo "[start] !!! ComfyUI will start anyway — restart the pod to retry the download."
  else
    echo "[start] All model files present:"
    for f in "${FILES[@]}"; do echo "[start]   ✓ $f ($(du -h "$MODELS/$f" | cut -f1))"; done
  fi
fi

# ---- Launch ComfyUI ---------------------------------------------------------
cd "$COMFY"
echo "[start] Starting ComfyUI on port 8188 from $COMFY"
# --enable-cors-header: lets requests through RunPod's proxy (otherwise ComfyUI answers 403)
# shellcheck disable=SC2086
exec python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header $COMFY_ARGS

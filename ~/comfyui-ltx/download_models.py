#!/usr/bin/env python3
"""Download LTX-2.3 models from Hugging Face to Samsung T5 SSD"""

from huggingface_hub import hf_hub_download
import os

REPO = "ChrisColeTech/LTX-2.3-uncensored-v1.4-FP8"
BASE = "/Volumes/Samsung_T5/ComfyUI_models"

files = [
    # Main UNet - Using Q4_K_M (~9GB) instead of Q6_K (~14GB) for 32GB RAM
    ("split/diffusion_models/ltxv23_uncensored_v1.4_Q4_K_M.gguf", "unet"),
    # Text Encoder (Gemma 3 12B)
    ("split/text_encoders/gemma-3-12b-it-ablit-norms-biproj-Q4_K_M.gguf", "clip"),
    # Projections
    ("split/text_encoders/ltxv23_uncensored_v1.4_projections.safetensors", "clip"),
    # Video VAE
    ("split/vae/ltxv23_uncensored_v1.4_video_vae.safetensors", "vae"),
    # Audio VAE
    ("split/vae/ltxv23_uncensored_v1.4_audio_vae.safetensors", "vae"),
    # Spatial Upscaler (v1.0 in repo, workflow references v1.1)
    ("split/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.0.safetensors", "upscale_models"),
]

print(f"Downloading {len(files)} model files to {BASE}")
print("=" * 60)

for fname, subdir in files:
    dest = os.path.join(BASE, subdir)
    os.makedirs(dest, exist_ok=True)
    print(f"\nDownloading: {fname}")
    print(f"  -> {dest}")
    try:
        hf_hub_download(
            repo_id=REPO,
            filename=fname,
            local_dir=dest,
            local_dir_use_symlinks=False,
            resume_download=True,
        )
        print(f"  ✓ Done")
    except Exception as e:
        print(f"  ✗ Error: {e}")

print("\n" + "=" * 60)
print("All downloads complete!")
print("\nModel locations:")
print(f"  UNet (Q4_K_M):     {BASE}/unet/ltxv23_uncensored_v1.4_Q4_K_M.gguf")
print(f"  Text Encoder:      {BASE}/clip/gemma-3-12b-it-ablit-norms-biproj-Q4_K_M.gguf")
print(f"  Projections:       {BASE}/clip/ltxv23_uncensored_v1.4_projections.safetensors")
print(f"  Video VAE:         {BASE}/vae/ltxv23_uncensored_v1.4_video_vae.safetensors")
print(f"  Audio VAE:         {BASE}/vae/ltxv23_uncensored_v1.4_audio_vae.safetensors")
print(f"  Upscaler (v1.0):   {BASE}/upscale_models/ltx-2.3-spatial-upscaler-x2-1.0.safetensors")
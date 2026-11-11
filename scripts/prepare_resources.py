#!/usr/bin/env python3
"""Build-time only: download pinned Kokoro weights/voices. Run from the repository root with .venv/bin/python scripts/prepare_resources.py."""
import hashlib
import pathlib
import urllib.request
import numpy as np
import torch

ROOT = pathlib.Path(__file__).resolve().parents[1] / 'Bookreader' / 'Resources'
ROOT.mkdir(parents=True, exist_ok=True)
MODEL = ROOT / 'kokoro-v1_0.safetensors'
EXPECTED = '4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8'
if not MODEL.exists():
    urllib.request.urlretrieve('https://media.githubusercontent.com/media/mlalma/KokoroTestApp/9dcd3b06468a3c1ecee6d09a33ca687c8e708566/Resources/kokoro-v1_0.safetensors', MODEL)
if hashlib.sha256(MODEL.read_bytes()).hexdigest() != EXPECTED:
    raise RuntimeError('Model checksum mismatch; remove the incomplete model and retry.')
voices = {}
for name in ('ef_dora', 'em_alex', 'em_santa', 'af_heart'):
    path = ROOT / (name + '.pt')
    urllib.request.urlretrieve('https://huggingface.co/hexgrad/Kokoro-82M/resolve/f3ff3571791e39611d31c381e3a41a3af07b4987/voices/' + name + '.pt', path)
    voices[name] = torch.load(path, map_location='cpu', weights_only=True).numpy()
    path.unlink()
np.savez(ROOT / 'voices.npz', **voices)
print('Verified model and prepared voices:', ', '.join(voices))

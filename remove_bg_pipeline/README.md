# Grounded SAM2 API

Modal-hosted API that detects an object via text prompt (Grounding DINO) and segments it (SAM2), returning the masked cutout as a transparent PNG.

## Deploy
```bash
modal deploy grounded_sam2_api.py
```

## Usage
POST to the endpoint with `{"image_base64": "...", "prompt": "mushroom", "threshold": 0.3}`.

Returns `masked_image_base64` (RGBA cutout of the top detection), `visualization_base64` (debug overlay), bounding boxes, scores, and labels.
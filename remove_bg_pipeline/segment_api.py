import modal
import io
import base64
from typing import Optional

app = modal.App("grounded-sam2-api")

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install('git')
    .pip_install(
        "fastapi[standard]",
        "torch==2.4.1",
        "torchvision==0.19.1",
        "transformers",
        "pillow",
        "numpy",
        "matplotlib",
        "opencv-python-headless",
    )
    .pip_install(
        "git+https://github.com/facebookresearch/segment-anything-2.git"
    )
)

@app.function(
    image=image,
    gpu="T4",
    timeout=300,
)
def segment_objects_internal(
    image_bytes: bytes,
    text_prompt: str,
    box_threshold: float = 0.3,
    return_visualization: bool = True,
) -> dict:
    """Core segmentation function"""
    import torch
    import numpy as np
    from PIL import Image
    from transformers import AutoProcessor, AutoModelForZeroShotObjectDetection
    from sam2.sam2_image_predictor import SAM2ImagePredictor
    import matplotlib.pyplot as plt
    
    device = "cuda" if torch.cuda.is_available() else "cpu"
    
    # Load image from bytes
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    
    # Format text prompt
    if not text_prompt.endswith('.'):
        text_prompt = text_prompt + '.'
    text_prompt = text_prompt.lower()
    
    # Step 1: Grounding DINO
    gd_model_id = "IDEA-Research/grounding-dino-tiny"
    gd_processor = AutoProcessor.from_pretrained(gd_model_id)
    gd_model = AutoModelForZeroShotObjectDetection.from_pretrained(gd_model_id).to(device)
    
    inputs = gd_processor(images=image, text=text_prompt, return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = gd_model(**inputs)
    
    results = gd_processor.post_process_grounded_object_detection(
        outputs,
        threshold=box_threshold,
        target_sizes=[image.size[::-1]],
    )[0]
    
    boxes = results["boxes"].cpu().numpy()
    scores = results["scores"].cpu().numpy()
    labels = results["text_labels"]
    
    # Step 2: SAM2
    sam2_predictor = SAM2ImagePredictor.from_pretrained("facebook/sam2-hiera-large")
    sam2_predictor.set_image(image)
    
    masks_list = []
    for box in boxes:
        masks, mask_scores, _ = sam2_predictor.predict(
            box=box,
            multimask_output=False,
        )
        masks_list.append(masks[0])
    
    masks_array = np.array(masks_list).astype(bool) if masks_list else np.array([])
    
    result = {
        "num_objects": len(masks_array),
        "boxes": boxes.tolist(),
        "scores": scores.tolist(),
        "labels": labels,
    }
    
    if len(masks_array) > 0:
        # Use only the first (highest confidence) mask
        combined_mask = masks_array[0]
        
        # Apply mask to original image: RGBA with transparent background
        img_array = np.array(image)
        masked_rgba = np.zeros((*img_array.shape[:2], 4), dtype=np.uint8)
        masked_rgba[combined_mask] = np.concatenate([
            img_array[combined_mask],
            np.full((combined_mask.sum(), 1), 255, dtype=np.uint8)
        ], axis=1)
        
        masked_image = Image.fromarray(masked_rgba, "RGBA")
        buf = io.BytesIO()
        masked_image.save(buf, format="PNG")
        buf.seek(0)
        result["masked_image_base64"] = base64.b64encode(buf.read()).decode()
        
        # Visualization with overlay
        if return_visualization:
            fig, ax = plt.subplots(1, 1, figsize=(10, 10))
            ax.imshow(image)
            
            for i, mask in enumerate(masks_array):
                colored_mask = np.zeros((*mask.shape, 4))
                colored_mask[mask] = [1, 0, 0, 0.4]
                ax.imshow(colored_mask)
                
                x1, y1, x2, y2 = boxes[i]
                ax.add_patch(plt.Rectangle((x1, y1), x2 - x1, y2 - y1,
                                            fill=False, edgecolor="lime", linewidth=2))
                ax.text(x1, y1 - 5, f"{labels[i]} {scores[i]:.2f}",
                        color="lime", fontsize=12, weight="bold")
            
            ax.axis("off")
            plt.tight_layout()
            
            buf = io.BytesIO()
            plt.savefig(buf, format='png', dpi=150, bbox_inches="tight")
            buf.seek(0)
            result["visualization_base64"] = base64.b64encode(buf.read()).decode()
            plt.close(fig)
    
    return result


@app.function(image=image, gpu="T4", timeout=300)
@modal.fastapi_endpoint(method="POST")
def segment(data: dict):
    """
    REST API endpoint for image segmentation
    
    Request body:
    {
        "image_base64": "base64_encoded_image_string",
        "prompt": "mushroom",
        "threshold": 0.3  // optional, default 0.3
    }
    
    Response:
    {
        "num_objects": 2,
        "labels": ["mushroom", "mushroom"],
        "scores": [0.95, 0.87],
        "boxes": [[x1, y1, x2, y2], ...],
        "masked_image_base64": "base64_png_original_with_mask_applied_transparent_bg",
        "visualization_base64": "base64_encoded_overlay_image"
    }
    """
    try:
        # Validate input
        if "image_base64" not in data:
            return {"error": "Missing 'image_base64' field"}, 400
        if "prompt" not in data:
            return {"error": "Missing 'prompt' field"}, 400
        
        # Decode image
        image_bytes = base64.b64decode(data["image_base64"])
        
        # Run segmentation
        result = segment_objects_internal.local(
            image_bytes=image_bytes,
            text_prompt=data["prompt"],
            box_threshold=data.get("threshold", 0.3),
            return_visualization=True,
        )
        
        return result
    
    except Exception as e:
        return {"error": str(e)}, 500
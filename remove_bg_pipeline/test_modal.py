import modal

app = modal.App("test_app")


image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "fastapi[standard]",
    )
)

@app.function(image=image, gpu=["L4", "T4", "A10G", "A100"], timeout=300)
@modal.fastapi_endpoint(method="POST")
def segment(data: dict):
    return {"status": "ok", "gpu": "allocated"}
from ultralytics import YOLO

# Loop through all YOLO11 model sizes
for size in ("n", "s", "m", "l", "x"):
    # Load a YOLO11 PyTorch model
    model = YOLO(f"yolo11{size}.pt")

    # Export the PyTorch model to CoreML INT8 format with NMS layers
    model.export(format="coreml", int8=True, nms=True, imgsz=[640, 384])
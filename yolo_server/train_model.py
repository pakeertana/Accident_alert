from ultralytics import YOLO

# Load base YOLO model
model = YOLO("yolov8n.pt")

# Train on your dataset
model.train(
    data="yolo_server/dataset.yaml",
    epochs=50,
    imgsz=640
)

# server.py
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO
from PIL import Image
import numpy as np
import io

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# 1) load model ONCE (adjust path to your best.pt)
model = YOLO("best.pt")  # -> change to actual path if different

@app.post("/detect")
async def detect(file: UploadFile = File(...), conf: float = 0.35):
    # Read uploaded image
    contents = await file.read()
    img = Image.open(io.BytesIO(contents)).convert("RGB")
    np_img = np.array(img)

    # Run inference (use imgsz and conf as needed)
    results = model(np_img, conf=conf, imgsz=640)  # returns a Results list
    r = results[0].cpu()  # get first result, move to cpu

    detections = []
    if hasattr(r, "boxes") and r.boxes is not None and len(r.boxes) > 0:
        xyxy = r.boxes.xyxy.cpu().numpy()   # Nx4
        confs = r.boxes.conf.cpu().numpy()  # N
        cls_ids = r.boxes.cls.cpu().numpy().astype(int)  # N
        names = r.names  # mapping id -> label
        for box, c, cls in zip(xyxy, confs, cls_ids):
            label = names[int(cls)] if int(cls) in names else str(int(cls))
            detections.append({
                "bbox": [float(box[0]), float(box[1]), float(box[2]), float(box[3])],
                "conf": float(c),
                "class_id": int(cls),
                "label": label
            })

    return {"detections": detections}

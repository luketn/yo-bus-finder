from ultralytics import YOLO
import  cv2
import cvzone
import math

# Load a COCO-pretrained YOLO11n model
model = YOLO("yolo11n.pt")

# Train the model on the COCO8 example dataset for 100 epochs
# results = model.train(data="coco8.yaml", epochs=100, imgsz=640)

# save
# model.save("yolo11n")

# Run inference with the YOLO11n model on the 'bus.jpg' image
img = cv2.imread("/Users/luketn/Desktop/bus.jpg")
results = model(img)

print(results)

for result in results:
    for box in result.boxes:
        x1, y1, x2, y2 = box.xyxy[0]
        x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
        w, h = x2 - x1, y2 - y1

        cvzone.cornerRect(img, (x1, y1, w, h))
        conf = math.ceil((box.conf[0] * 100)) / 100
        cls = box.cls[0]
        name = result.names[int(cls)]
        cvzone.putTextRect(img, f'{name}', (max(0, x1), max(35, y1)))


cv2.imshow("Image", img)
cv2.waitKey(0)
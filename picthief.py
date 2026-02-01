import cv2
import numpy as np
from ultralytics import YOLO
from paddleocr import PaddleOCR
from rapidfuzz import fuzz
import re
import json
import os
from PIL import Image
import sys
import traceback
import hashlib
from flask import Flask, request, jsonify  
import tempfile  
import shutil   
from lib.log_cat import * 
import logging
log = LogCat()
logging.getLogger("ppocr").setLevel(logging.ERROR) 
logging.getLogger("paddle").setLevel(logging.ERROR)  

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024  
SUPPORTED_FORMATS = (".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".gif")
LOGO = '''⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣶⣤⣀⣀⣤⣶⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⣾⣷⣶⣶⣶⣦⣤⠀⢤⣤⣈⣉⠙⠛⠛⠋⣉⣁⣤⡤⠀⣤⣴⣶⣶⣶⣾⣷⠀
⠀⠈⠻⢿⣿⣿⣿⣿⣶⣤⣄⣉⣉⣉⣛⣛⣉⣉⣉⣠⣤⣶⣿⣿⣿⣿⡿⠟⠁⠀
⠀⠀⠀⠀⠀⠉⠙⠛⠛⠿⠿⠿⢿⣿⣿⣿⣿⡿⠿⠿⠿⠛⠛⠋⠉⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢿⣷⠦⠄⢀⣠⡀⠠⣄⡀⠠⠴⣾⡿⠀⠀⠀⠀⠀⣀⡀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢤⣤⣴⣾⣿⣿⣷⣤⣙⣿⣷⣦⣤⡤⠀⠴⠶⠟⠛⠉⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀⠺⣷⣄⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢈⣙⣛⣻⣿⣿⣿⡿⠃⠐⠿⠿⣾⣿⣷⡄⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⣿⣿⠿⠋⠀⠀⠀⠀⠀⠀⠀⠈⠁⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⣿⣿⣾⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠛⠛⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
Maptnh@S-H4CK13 | picthief  | https://github.com/MartinxMax/'''
 
YOLO_MODEL = "main.pt"
YOLO_CONF = 0.35
KEYWORDS = [
    "id", "cert", "doc", "identity", "permit", "license", "passport", "card", "bank",
    "debit", "credit", "unionpay", "swift", "iban", "pay",
    "62", "51", "52", "43", "60", "95",
    "sfz", "yhk", "szh", "jzz", "hz", "jsz",
    "pwd", "pass", "pin", "verify", "code", "auth", "valid", "sign", "certi","adm","root","user"
]
FUZZ_THRESHOLD = 85
CARD_MIN_AREA = 2000

 
yolo = YOLO(YOLO_MODEL)
ocr = PaddleOCR(lang='en', use_angle_cls=False,show_log=False)  

 
def get_image_md5(img_path):
    md5_obj = hashlib.md5()
    try:
        with open(img_path, 'rb') as f:
            while chunk := f.read(4096):
                md5_obj.update(chunk)
        return md5_obj.hexdigest()
    except Exception as e:
        log.error(f"Failed to calculate MD5：{str(e)}")
        return ""

def detect_people(img_bgr):
    res = yolo(img_bgr, conf=YOLO_CONF)[0]
    people = []
    for box in res.boxes:
        cls_id = int(box.cls[0])
        name = yolo.names[cls_id]
        conf = float(box.conf[0])
        if name == "person" and conf >= YOLO_CONF:
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            people.append({"bbox": [x1, y1, x2, y2], "conf": round(conf, 3)})
    return people

def find_rectangles_cv(img_bgr):
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    edged = cv2.Canny(blur, 50, 150)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    dil = cv2.dilate(edged, kernel, iterations=1)
    contours, _ = cv2.findContours(dil, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    rects = []
    for cnt in contours:
        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.02 * peri, True)
        if len(approx) == 4:
            x, y, w, h = cv2.boundingRect(approx)
            area = w * h
            if area > CARD_MIN_AREA:
                rects.append([x, y, x + w, y + h])
    return rects

def preprocess_for_ocr(crop_bgr, mode="adaptive"):
    gray = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2GRAY)
    if mode == "none":
        return cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
    if mode == "binarize":
        _, th = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        return th
    th = cv2.adaptiveThreshold(
        gray, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31, 9
    )
    th = cv2.medianBlur(th, 3)
    return th

def _parse_ocr_result(raw):
    texts = []
    try:
        if isinstance(raw, list) and len(raw) > 0 and isinstance(raw[0], list):
            lines = raw[0]
            for ln in lines:
                if len(ln) >= 2:
                    info = ln[1]
                    if isinstance(info, (list, tuple)):
                        txt = info[0]
                        texts.append(str(txt))
                    elif isinstance(info, str):
                        texts.append(info)
        else:
            texts.append(str(raw))
    except Exception:
        try:
            for entry in raw:
                if isinstance(entry, (list, tuple)) and len(entry) >= 2:
                    cand = entry[1]
                    if isinstance(cand, (list, tuple)):
                        texts.append(str(cand[0]))
                    else:
                        texts.append(str(cand))
        except Exception:
            pass
    return texts

def call_ocr(image):
    try:
        return ocr.ocr(image)
    except TypeError:
        try:
            return ocr.predict(image)
        except Exception:
            try:
                pil = Image.fromarray(image if image.ndim == 2 else cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
                return ocr.ocr(np.array(pil))
            except Exception as e:
                raise e
    except Exception as e:
        raise e

def crop_and_ocr(img_bgr, bbox, ocr_mode="adaptive"):
    x1, y1, x2, y2 = bbox
    h, w = img_bgr.shape[:2]
    x1, y1 = max(0, x1), max(0, y1)
    x2, y2 = min(w, x2), min(h, y2)
    if x2 <= x1 or y2 <= y1:
        return ""
    crop = img_bgr[y1:y2, x1:x2]
    prep = preprocess_for_ocr(crop, mode=ocr_mode)
    if prep.ndim == 2:
        ocr_input = prep
    else:
        if prep.shape[2] == 3:
            ocr_input = cv2.cvtColor(prep, cv2.COLOR_BGR2RGB)
        else:
            ocr_input = prep
    raw = call_ocr(ocr_input)
    texts = _parse_ocr_result(raw)
    return " ".join([t for t in texts if t])

def find_keywords_in_text(text):
    found = []
    for kw in KEYWORDS:
        if re.search(re.escape(kw), text, flags=re.IGNORECASE):
            found.append((kw, "exact"))
        else:
            words = re.findall(r"\w+", text)
            for w in words:
                score = fuzz.ratio(kw.lower(), w.lower())
                if score >= FUZZ_THRESHOLD:
                    found.append((kw, f"fuzzy({score})"))
                    break
    return found

def analyze_image(path, ocr_mode="adaptive"):
    img_bgr = cv2.imread(path)
    if img_bgr is None:
        raise FileNotFoundError(f"Unable to read image: {path}")
    out = {"people_count": 0, "keyword_matches": []}

    try:
        people = detect_people(img_bgr)
        out["people_count"] = len(people)
        rects = find_rectangles_cv(img_bgr)
        for bbox in rects:
            text = crop_and_ocr(img_bgr, bbox, ocr_mode=ocr_mode)
            matches = find_keywords_in_text(text)
            if matches:
                out["keyword_matches"].extend(matches)
        if not out["keyword_matches"]:
            whole_prep = preprocess_for_ocr(img_bgr, mode=ocr_mode)
            ocr_input = whole_prep if whole_prep.ndim == 2 else cv2.cvtColor(whole_prep, cv2.COLOR_BGR2RGB)
            raw_whole = call_ocr(ocr_input)
            whole_lines = _parse_ocr_result(raw_whole)
            whole_text = " ".join([t for t in whole_lines if t])
            whole_matches = find_keywords_in_text(whole_text)
            if whole_matches:
                out["keyword_matches"] = whole_matches

    except Exception as e:
        log.error(f"Failed to analyze image：{traceback.format_exc()}")
        out["error"] = str(e)
    return out

@app.route('/scan', methods=['POST'])
def scan_image():
    if 'file' not in request.files:
        return jsonify({"type": "NA", "error": "???"}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({"type": "NA", "error": "???"}), 400

 
    if not file.filename.lower().endswith(SUPPORTED_FORMATS):
        return jsonify({"type": "NA", "error": f"???"}), 400

   
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as tmp_file:
            file.save(tmp_file.name)
            tmp_path = tmp_file.name
 
        ocr_mode = request.form.get('ocr_mode', 'adaptive')   
        analyze_result = analyze_image(tmp_path, ocr_mode=ocr_mode)

 
        people_count = analyze_result.get("people_count", 0)
        has_sensitive = 1 if analyze_result.get("keyword_matches", []) else 0

        if people_count > 0 or has_sensitive == 1:
            response = {
                "type": "sense",
                "data": {
                    "people": people_count,
                    "cred": has_sensitive,
                    "hash": get_image_md5(tmp_path)
                }
            }
        else:
 
            response = {"type": "NA"}
        log.info(f"{response}")
        return jsonify(response)

    except Exception as e:
        log.error(f"API processing failed：{traceback.format_exc()}")
        return jsonify({"type": "NA", "error": "???"}), 500

    finally:
        if 'tmp_path' in locals():
            try:
                os.unlink(tmp_path)
            except Exception as e:
                log.error(f"Deleting temporary files failed：{str(e)}")
 


if __name__ == "__main__":
    print(LOGO)
    app.run(host='0.0.0.0', port=5000, debug=False)
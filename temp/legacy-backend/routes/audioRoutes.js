const express = require("express");
const multer = require("multer");

const { uploadAudio, processCloudAudio } = require("../controllers/audioController");

const router = express.Router();

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, "uploads/");
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `${uniqueSuffix}-${file.originalname}`);
  },
});

const upload = multer({ storage });

router.post("/api/v1/audio/upload", upload.single("meeting_audio"), uploadAudio);
router.post("/api/v1/audio/process", express.json(), processCloudAudio);

module.exports = router;

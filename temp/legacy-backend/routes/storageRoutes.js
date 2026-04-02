const express = require("express");

const { getSignedUploadUrl } = require("../controllers/storageController");

const router = express.Router();

router.get("/api/v1/storage/upload-url", getSignedUploadUrl);

module.exports = router;

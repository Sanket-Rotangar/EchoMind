const express = require("express");

const { getMeetings, getMeetingById } = require('../controllers/meetingController');

const router = express.Router();

router.get('/api/v1/meetings', getMeetings);

router.get('/api/v1/meetings/:id', getMeetingById);

module.exports = router;

const fs = require("fs");

const { transcribeAudio, transcribeAudioFromUrl } = require("../services/assemblyService");
const { getSignedDownloadUrl, createProcessingMeeting, updateMeetingData, markMeetingFailed } = require("../services/supabaseService");
const { extractMeetingInsights } = require("../services/geminiService");

const uploadAudio = async (req, res) => {
  if (!req.file) {
    return res.status(400).json({
      success: false,
      message: "No file provided",
    });
  }

  try {
    const transcript = await transcribeAudio(req.file.path);
    const insights = await extractMeetingInsights(transcript);

    return res.status(200).json({
      success: true,
      data: insights,
    });
  } catch (error) {
    console.error("Processing failed:", error.message);

    return res.status(500).json({
      success: false,
      message: "Failed to process audio",
    });
  } finally {
    if (req.file.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
  }
};

// This runs asynchronously in the background. The phone DOES NOT wait for this.
const runBackgroundPipeline = async (meetingId, path) => {
    try {
        console.log(`[BACKGROUND] Starting AI Pipeline for Meeting: ${meetingId}`);
        const signedUrl = await getSignedDownloadUrl(path);
        const transcriptArray = await transcribeAudioFromUrl(signedUrl);
        const insights = await extractMeetingInsights(transcriptArray);
        
        await updateMeetingData(meetingId, insights);
        console.log(`[BACKGROUND] ✅ SUCCESS: Meeting ${meetingId} completed and saved.`);
    } catch (error) {
        console.error(`[BACKGROUND] ❌ FAILED for Meeting ${meetingId}:`, error);
        await markMeetingFailed(meetingId);
    }
};

// This is the immediate response back to the Flutter app.
const processCloudAudio = async (req, res) => {
    try {
        const { path } = req.body;
        const activeUserId = process.env.DUMMY_USER_ID; 

        if (!activeUserId) throw new Error("DUMMY_USER_ID is missing from .env");

        // 1. Instantly create the "Processing" row in Supabase
        const meeting = await createProcessingMeeting(activeUserId, path);

        // 2. Release the Flutter app immediately (HTTP 202 Accepted)
        res.status(202).json({ 
            success: true, 
            message: "Audio received. Processing in background.",
            meetingId: meeting.id
        });

        // 3. Fire the heavy AI lifting without 'await' so it runs independently
        runBackgroundPipeline(meeting.id, path);

    } catch (error) {
        console.error("❌ INGESTION ERROR:", error);
        return res.status(500).json({ success: false, message: error.message });
    }
};

module.exports = {
  uploadAudio,
  processCloudAudio,
};

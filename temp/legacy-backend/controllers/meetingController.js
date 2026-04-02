const { getUserMeetings, getMeetingDetails } = require("../services/supabaseService");

const getMeetings = async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 8;
        const offset = parseInt(req.query.offset) || 0;
        const meetings = await getUserMeetings(process.env.DUMMY_USER_ID, limit, offset);
        res.status(200).json({ success: true, data: meetings });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

const getMeetingById = async (req, res) => {
    try {
        const meeting = await getMeetingDetails(req.params.id);
        res.status(200).json({ success: true, data: meeting });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

module.exports = { getMeetings, getMeetingById };
require("dotenv").config();

const { createClient } = require("@supabase/supabase-js");

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error("SUPABASE_URL and SUPABASE_ANON_KEY must be set in environment variables");
}

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const generateUploadUrl = async (fileName) => {
  const { data, error } = await supabase.storage
    .from("meetings")
    .createSignedUploadUrl(fileName);

  if (error) {
    throw new Error(error.message);
  }

  return data;
};

const getSignedDownloadUrl = async (filePath) => {
  const { data, error } = await supabase.storage
    .from("meetings")
    .createSignedUrl(filePath, 3600);

  if (error) {
    throw new Error(error.message);
  }

  return data.signedUrl;
};

// 1. Instantly creates a placeholder so the UI has something to show
const createProcessingMeeting = async (userId, path) => {
    const { data, error } = await supabase
        .from('meetings')
        .insert({
            user_id: userId,
            title: 'Processing Meeting...',
            status: 'processing',
            audio_storage_path: path
        })
        .select()
        .single();

    if (error) throw new Error(`Create Meeting Failed: ${error.message}`);
    return data;
};

// 2. Injects the Gemini data once the background job finishes
const updateMeetingData = async (meetingId, insights) => {
    const { error: meetingError } = await supabase
        .from('meetings')
        .update({
            title: insights.bottom_line?.substring(0, 40) + "..." || 'Untitled Meeting',
            status: 'completed',
            intelligence_data: insights
        })
        .eq('id', meetingId);

    if (meetingError) throw new Error(`Update Meeting Failed: ${meetingError.message}`);

    if (insights.action_matrix && insights.action_matrix.length > 0) {
        const actionItemsToInsert = insights.action_matrix.map(item => ({
            meeting_id: meetingId,
            assignee: item.assignee,
            task_description: item.task,
            deadline: item.deadline
        }));

        const { error: actionError } = await supabase.from('action_items').insert(actionItemsToInsert);
        if (actionError) throw new Error(`Action Items Insert Failed: ${actionError.message}`);
    }
};

// 3. Catches AI errors so the UI doesn't spin forever
const markMeetingFailed = async (meetingId) => {
    await supabase.from('meetings').update({ status: 'failed' }).eq('id', meetingId);
};

const getUserMeetings = async (userId, limit = 8, offset = 0) => {
    const { data, error } = await supabase
        .from('meetings')
        .select('id, title, status, created_at')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1); // <--- THIS IS THE PAGINATION
    
    if (error) throw new Error(error.message);
    return data;
};

const getMeetingDetails = async (meetingId) => {
    const { data, error } = await supabase
        .from('meetings')
        .select(`*, action_items (*)`) // Fetches meeting AND related tasks
        .eq('id', meetingId)
        .single();
    if (error) throw new Error(error.message);
    return data;
};

module.exports = { 
    generateUploadUrl,
    getSignedDownloadUrl, 
    createProcessingMeeting, 
    updateMeetingData, 
    markMeetingFailed,
    getUserMeetings,
    getMeetingDetails
};

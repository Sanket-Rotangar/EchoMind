const { generateUploadUrl } = require("../services/supabaseService");

const getSignedUploadUrl = async (req, res) => {
  try {
    const randomPart = Math.random().toString(36).slice(2, 10);
    const path = `${Date.now()}-${randomPart}`;
    const signedUploadData = await generateUploadUrl(path);

    return res.status(200).json({
      success: true,
      uploadUrl: signedUploadData.signedUrl,
      path,
    });
  } catch (error) {
    console.error("Failed to generate upload URL:", error.message);

    return res.status(500).json({
      success: false,
      message: "Failed to generate upload URL",
    });
  }
};

module.exports = {
  getSignedUploadUrl,
};

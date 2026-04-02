require("dotenv").config();

const { AssemblyAI } = require("assemblyai");

const apiKey = process.env.ASSEMBLYAI_API_KEY;

if (!apiKey) {
  throw new Error("ASSEMBLYAI_API_KEY is not set in environment variables");
}

const client = new AssemblyAI({
  apiKey,
});

const transcribeAudio = async (filePath) => {
  const transcript = await client.transcripts.transcribe({
    audio: filePath,
    speech_models: ["universal-2"],
    speaker_labels: true,
  });

  const formattedUtterances = (transcript.utterances || []).map((utterance) => {
    const speakerLabel = utterance.speaker || "Unknown";
    return `Speaker ${speakerLabel}: ${utterance.text}`;
  });

  return formattedUtterances;
};

const transcribeAudioFromUrl = async (audioUrl) => {
  const transcript = await client.transcripts.transcribe({
    audio: audioUrl,
    speaker_labels: true,
    speech_models: ["universal-2"],
  });

  const formattedUtterances = (transcript.utterances || []).map((utterance) => {
    const speakerLabel = utterance.speaker || "Unknown";
    return `Speaker ${speakerLabel}: ${utterance.text}`;
  });

  return formattedUtterances;
};

module.exports = {
  transcribeAudio,
  transcribeAudioFromUrl,
};

// EchoMind Offscreen Document - Handles actual audio recording
// This runs in a separate context that can access getUserMedia and play audio

let mediaRecorder = null;
let audioChunks = [];
let tabStream = null;
let micStream = null;
let combinedStream = null;
let audioContext = null;
let recordingStartTime = null;
let isRecordingActive = false;
let audioPlaybackElement = null;

console.log('Offscreen document loaded');

// Get the audio playback element
document.addEventListener('DOMContentLoaded', () => {
  audioPlaybackElement = document.getElementById('audio-playback');
  console.log('Audio playback element ready:', !!audioPlaybackElement);
});

// Listen for messages from background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // Only handle messages targeted at offscreen
  if (message.target !== 'offscreen') {
    return false;
  }
  
  console.log('Offscreen received message:', message.action);
  
  switch (message.action) {
    case 'START_CAPTURE':
      startCapture(message.streamId, message.tabId)
        .then(() => {
          console.log('Capture started successfully');
          sendResponse({ success: true });
        })
        .catch(error => {
          console.error('Capture failed:', error);
          sendResponse({ success: false, error: error.message });
        });
      return true; // Keep channel open for async response
      
    case 'STOP_CAPTURE':
      console.log('STOP_CAPTURE received, mediaRecorder state:', mediaRecorder?.state, 'isRecordingActive:', isRecordingActive);
      stopCapture()
        .then((result) => {
          console.log('Capture stopped successfully, result:', result);
          sendResponse({ success: true, ...result });
        })
        .catch(error => {
          console.error('Stop capture failed:', error);
          sendResponse({ success: false, error: error.message });
        });
      return true; // Keep channel open for async response
    
    case 'GET_STATE':
      sendResponse({
        isRecording: isRecordingActive && mediaRecorder?.state === 'recording',
        recorderState: mediaRecorder?.state,
        chunks: audioChunks.length,
        duration: recordingStartTime ? Math.floor((Date.now() - recordingStartTime) / 1000) : 0
      });
      return false;
      
    default:
      console.log('Unknown action:', message.action);
      return false;
  }
});

async function startCapture(streamId, tabId) {
  console.log('Starting capture with streamId:', streamId);
  
  // Clean up any existing recording first
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    console.log('Stopping existing recording first...');
    mediaRecorder.stop();
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  cleanupStreams();
  
  try {
    // Capture tab audio using the stream ID
    console.log('Getting tab audio stream...');
    
    tabStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        mandatory: {
          chromeMediaSource: 'tab',
          chromeMediaSourceId: streamId
        }
      },
      video: false
    });
    
    console.log('Tab audio stream obtained, tracks:', tabStream.getAudioTracks().length);
    
    // === AUDIO PLAYBACK: Play the captured tab audio back to the user ===
    // This works because offscreen documents can play audio
    if (!audioPlaybackElement) {
      audioPlaybackElement = document.getElementById('audio-playback');
    }
    
    if (audioPlaybackElement) {
      // Create a clone of the tab stream for playback (so we don't interfere with recording)
      const playbackStream = tabStream.clone();
      audioPlaybackElement.srcObject = playbackStream;
      audioPlaybackElement.volume = 1.0;
      
      // Try to play (may need user gesture, but offscreen should work)
      try {
        await audioPlaybackElement.play();
        console.log('Audio playback started - user should hear tab audio');
      } catch (playError) {
        console.warn('Could not auto-play audio:', playError.message);
        // Still continue with recording even if playback fails
      }
    } else {
      console.warn('Audio playback element not found');
    }
    
    // Create audio context for mixing audio streams for RECORDING
    audioContext = new AudioContext();
    const tabSource = audioContext.createMediaStreamSource(tabStream);
    
    // Create a destination for recording
    const recordingDestination = audioContext.createMediaStreamDestination();
    
    // Connect tab audio to recording destination
    tabSource.connect(recordingDestination);
    
    // Try to capture microphone for user's voice
    try {
      console.log('Getting microphone stream...');
      micStream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: false
      });
      console.log('Microphone stream obtained, tracks:', micStream.getAudioTracks().length);
      
      // Add microphone to recording
      const micSource = audioContext.createMediaStreamSource(micStream);
      micSource.connect(recordingDestination);
      
    } catch (micError) {
      console.warn('Could not capture microphone (recording tab audio only):', micError.message);
      micStream = null;
    }
    
    combinedStream = recordingDestination.stream;
    console.log('Audio streams combined for recording');
    
    // Start recording
    audioChunks = [];
    recordingStartTime = Date.now();
    isRecordingActive = true;
    
    // Check supported mime types
    let mimeType = 'audio/webm;codecs=opus';
    if (!MediaRecorder.isTypeSupported(mimeType)) {
      mimeType = 'audio/webm';
      if (!MediaRecorder.isTypeSupported(mimeType)) {
        mimeType = 'audio/mp4';
        if (!MediaRecorder.isTypeSupported(mimeType)) {
          mimeType = ''; // Let browser choose
        }
      }
    }
    
    console.log('Using mimeType:', mimeType || 'default');
    
    const recorderOptions = mimeType ? {
      mimeType: mimeType,
      audioBitsPerSecond: 128000
    } : {};
    
    mediaRecorder = new MediaRecorder(combinedStream, recorderOptions);
    
    mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        audioChunks.push(event.data);
        console.log('Data chunk received, size:', event.data.size, 'total chunks:', audioChunks.length);
      }
    };
    
    mediaRecorder.onstop = async () => {
      isRecordingActive = false;
      const duration = recordingStartTime ? Math.floor((Date.now() - recordingStartTime) / 1000) : 0;
      console.log('MediaRecorder onstop triggered, chunks:', audioChunks.length, 'duration:', duration, 'seconds');
      
      // Check minimum recording duration (at least 3 seconds)
      if (duration < 3) {
        console.error('Recording too short:', duration, 'seconds');
        notifyBackground('RECORDING_ERROR', { error: `Recording too short (${duration}s). Please record for at least 3 seconds.` });
        cleanupStreams();
        return;
      }
      
      if (audioChunks.length === 0) {
        console.error('No audio chunks recorded');
        notifyBackground('RECORDING_ERROR', { error: 'No audio data recorded' });
        cleanupStreams();
        return;
      }
      
      // Combine all chunks into a single blob
      const audioBlob = new Blob(audioChunks, { type: mimeType || 'audio/webm' });
      console.log('Audio blob created, size:', audioBlob.size, 'bytes');
      
      // Check minimum file size (at least 10KB for a valid recording)
      if (audioBlob.size < 10000) {
        console.error('Audio file too small:', audioBlob.size, 'bytes');
        notifyBackground('RECORDING_ERROR', { error: 'Recording file too small. Please try again.' });
        cleanupStreams();
        return;
      }
      
      // Convert to base64 for sending to background script
      const reader = new FileReader();
      reader.onloadend = () => {
        const base64 = reader.result.split(',')[1];
        console.log('Sending audio to background, base64 length:', base64.length, 'duration:', duration);
        notifyBackground('RECORDING_STOPPED', { audioBlob: base64, duration: duration });
      };
      reader.onerror = (error) => {
        console.error('FileReader error:', error);
        notifyBackground('RECORDING_ERROR', { error: 'Failed to process audio data' });
      };
      reader.readAsDataURL(audioBlob);
      
      // Clean up streams
      cleanupStreams();
    };
    
    mediaRecorder.onerror = (event) => {
      console.error('MediaRecorder error:', event.error);
      isRecordingActive = false;
      notifyBackground('RECORDING_ERROR', { error: event.error?.message || 'Recording error' });
      cleanupStreams();
    };
    
    // Start recording with 1 second chunks
    mediaRecorder.start(1000);
    console.log('MediaRecorder started, state:', mediaRecorder.state, 'isRecordingActive:', isRecordingActive);
    
  } catch (error) {
    console.error('Failed to start capture:', error);
    isRecordingActive = false;
    cleanupStreams();
    throw error;
  }
}

function notifyBackground(action, data = {}) {
  try {
    chrome.runtime.sendMessage({
      target: 'background',
      action: action,
      ...data
    }, (response) => {
      if (chrome.runtime.lastError) {
        console.error('Message send error:', chrome.runtime.lastError);
      } else {
        console.log(action, 'message sent, response:', response);
      }
    });
  } catch (e) {
    console.error('Failed to send message:', action, e);
  }
}

async function stopCapture() {
  console.log('stopCapture called, mediaRecorder:', mediaRecorder ? 'exists' : 'null', 'state:', mediaRecorder?.state, 'isRecordingActive:', isRecordingActive);
  
  const duration = recordingStartTime ? Math.floor((Date.now() - recordingStartTime) / 1000) : 0;
  
  return new Promise((resolve) => {
    if (mediaRecorder && mediaRecorder.state === 'recording') {
      // Set up one-time handler for when stop completes
      const originalOnStop = mediaRecorder.onstop;
      mediaRecorder.onstop = async (event) => {
        // Call the original handler which processes the audio
        if (originalOnStop) {
          await originalOnStop(event);
        }
        resolve({ stopped: true, duration: duration });
      };
      
      mediaRecorder.stop();
      console.log('MediaRecorder.stop() called, duration:', duration, 'seconds');
    } else {
      console.log('MediaRecorder not recording, state:', mediaRecorder?.state, 'isRecordingActive:', isRecordingActive);
      isRecordingActive = false;
      cleanupStreams();
      
      // DON'T send RECORDING_STOPPED with null - that causes confusion
      // Just resolve and let background handle the state
      resolve({ stopped: false, wasNotRecording: true, duration: 0 });
    }
  });
}

function cleanupStreams() {
  console.log('Cleaning up streams...');
  
  // Stop audio playback
  if (audioPlaybackElement) {
    audioPlaybackElement.pause();
    audioPlaybackElement.srcObject = null;
    console.log('Audio playback stopped');
  }
  
  if (tabStream) {
    tabStream.getTracks().forEach(track => {
      track.stop();
      console.log('Tab track stopped');
    });
    tabStream = null;
  }
  
  if (micStream) {
    micStream.getTracks().forEach(track => {
      track.stop();
      console.log('Mic track stopped');
    });
    micStream = null;
  }
  
  if (audioContext && audioContext.state !== 'closed') {
    audioContext.close().catch(e => console.log('AudioContext close error:', e));
    audioContext = null;
  }
  
  combinedStream = null;
  mediaRecorder = null;
  audioChunks = [];
  recordingStartTime = null;
  isRecordingActive = false;
  
  console.log('Cleanup complete');
}

// EchoMind Background Service Worker
// Handles audio recording and communication with the backend

const BACKEND_URL = 'http://localhost:8000';
const KEEP_ALIVE_ALARM = 'echomind-keep-alive';

// In-memory state (will be synced with storage)
let isRecording = false;
let recordingTabId = null;
let recordingStartTime = null;

// Initialize - restore state from storage when service worker starts
async function initializeState() {
  console.log('Initializing background service worker...');
  
  try {
    const data = await chrome.storage.local.get(['echomind_recording_state']);
    const state = data.echomind_recording_state;
    
    if (state && state.isRecording) {
      console.log('Restoring recording state from storage:', state);
      isRecording = true;
      recordingTabId = state.tabId;
      recordingStartTime = state.startTime;
      
      // Check if offscreen document still exists
      const hasOffscreen = await hasOffscreenDocument();
      console.log('Offscreen document exists:', hasOffscreen);
      
      if (hasOffscreen) {
        // Recording is still active, update badge
        chrome.action.setBadgeText({ text: 'REC' });
        chrome.action.setBadgeBackgroundColor({ color: '#E9A28B' });
        
        // Ensure keep-alive alarm is running
        startKeepAliveAlarm();
      } else {
        // Offscreen document gone but state says recording - clean up
        console.log('Offscreen document lost, cleaning up state');
        await resetRecordingState();
      }
    } else {
      console.log('No active recording state');
      isRecording = false;
      recordingTabId = null;
      recordingStartTime = null;
    }
  } catch (error) {
    console.error('Error initializing state:', error);
  }
}

// Run initialization
initializeState();

// Initialize extension on install
chrome.runtime.onInstalled.addListener(() => {
  console.log('EchoMind Extension installed');
  
  // Set default settings
  chrome.storage.local.get(['echomind_settings'], (result) => {
    if (!result.echomind_settings) {
      chrome.storage.local.set({
        echomind_settings: {
          inputDeviceId: 'default',
          outputDeviceId: 'default',
          autoUpload: true
        }
      });
    }
  });
});

// Keep-alive alarm to prevent service worker from dying during recording
function startKeepAliveAlarm() {
  chrome.alarms.create(KEEP_ALIVE_ALARM, { periodInMinutes: 0.4 }); // Every 24 seconds
  console.log('Keep-alive alarm started');
}

function stopKeepAliveAlarm() {
  chrome.alarms.clear(KEEP_ALIVE_ALARM);
  console.log('Keep-alive alarm stopped');
}

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === KEEP_ALIVE_ALARM) {
    console.log('Keep-alive ping, isRecording:', isRecording);
    
    // Check if we should still be recording
    const data = await chrome.storage.local.get(['echomind_recording_state']);
    const state = data.echomind_recording_state;
    
    if (!state || !state.isRecording) {
      console.log('Storage says not recording, stopping alarm');
      stopKeepAliveAlarm();
      isRecording = false;
      chrome.action.setBadgeText({ text: '' });
    } else {
      // Update badge to show we're still alive
      chrome.action.setBadgeText({ text: 'REC' });
    }
  }
});

// Listen for messages from popup and offscreen document
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('Background received message:', message.action, 'from:', sender.url || 'popup');
  
  // Handle messages from offscreen document
  if (message.target === 'background') {
    if (message.action === 'RECORDING_STOPPED') {
      console.log('Received RECORDING_STOPPED from offscreen, duration:', message.duration);
      handleRecordingStopped(message.audioBlob, message.duration);
      sendResponse({ received: true });
      return;
    }
    if (message.action === 'RECORDING_ERROR') {
      console.error('Recording error from offscreen:', message.error);
      resetRecordingState();
      // Show notification about the error
      chrome.notifications.create({
        type: 'basic',
        iconUrl: 'icons/icon128.png',
        title: 'EchoMind - Recording Error',
        message: message.error || 'Recording failed'
      });
      sendResponse({ received: true });
      return;
    }
  }
  
  // Handle messages from popup
  switch (message.action) {
    case 'GET_RECORDING_STATE':
      // First sync with storage in case we're out of sync
      chrome.storage.local.get(['echomind_recording_state'], (data) => {
        const state = data.echomind_recording_state;
        if (state && state.isRecording) {
          isRecording = true;
          recordingTabId = state.tabId;
          recordingStartTime = state.startTime;
        }
        const duration = recordingStartTime ? Math.floor((Date.now() - recordingStartTime) / 1000) : 0;
        console.log('GET_RECORDING_STATE response:', { isRecording, recordingTabId, duration, startTime: recordingStartTime });
        sendResponse({ isRecording, recordingTabId, duration, startTime: recordingStartTime });
      });
      return true; // Async response
      
    case 'START_RECORDING':
      startRecording(message.tabId).then(result => {
        sendResponse(result);
      }).catch(error => {
        sendResponse({ success: false, error: error.message });
      });
      return true;
      
    case 'STOP_RECORDING':
      stopRecording().then(result => {
        sendResponse(result);
      }).catch(error => {
        sendResponse({ success: false, error: error.message });
      });
      return true;
      
    default:
      break;
  }
});

// Helper to reset recording state (both memory and storage)
async function resetRecordingState() {
  console.log('Resetting recording state');
  isRecording = false;
  recordingTabId = null;
  recordingStartTime = null;
  chrome.action.setBadgeText({ text: '' });
  stopKeepAliveAlarm();
  
  await chrome.storage.local.set({
    echomind_recording_state: {
      isRecording: false,
      processing: false
    }
  });
}

// Check if offscreen document exists
async function hasOffscreenDocument() {
  try {
    const contexts = await chrome.runtime.getContexts({
      contextTypes: ['OFFSCREEN_DOCUMENT']
    });
    return contexts.length > 0;
  } catch (e) {
    console.error('Error checking offscreen document:', e);
    return false;
  }
}

// Create offscreen document for audio processing
async function createOffscreenDocument() {
  if (await hasOffscreenDocument()) {
    console.log('Offscreen document already exists');
    return;
  }
  
  try {
    await chrome.offscreen.createDocument({
      url: 'offscreen.html',
      reasons: ['USER_MEDIA'],
      justification: 'Recording audio from tab and microphone for meeting transcription'
    });
    console.log('Offscreen document created');
  } catch (error) {
    if (error.message.includes('Only a single offscreen')) {
      console.log('Offscreen document already exists (from error)');
    } else {
      console.error('Failed to create offscreen document:', error);
      throw error;
    }
  }
}

// Start recording
async function startRecording(tabId) {
  console.log('startRecording called, current isRecording:', isRecording);
  
  // Check storage state too
  const data = await chrome.storage.local.get(['echomind_recording_state']);
  if (data.echomind_recording_state?.isRecording) {
    console.log('Storage says already recording');
    return { success: false, error: 'Already recording. Stop the current recording first.' };
  }
  
  if (isRecording) {
    return { success: false, error: 'Already recording' };
  }
  
  try {
    // Check if user is authenticated
    const auth = await chrome.storage.local.get(['echomind_auth_token', 'echomind_user']);
    if (!auth.echomind_auth_token || !auth.echomind_user) {
      return { success: false, error: 'Please sign in first' };
    }
    
    // Get the current tab if not provided
    if (!tabId) {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      tabId = tab.id;
    }
    
    console.log('Starting recording for tab:', tabId);
    
    // Clean up any existing offscreen document first
    if (await hasOffscreenDocument()) {
      console.log('Cleaning up existing offscreen document...');
      try {
        await chrome.offscreen.closeDocument();
        await new Promise(resolve => setTimeout(resolve, 200));
      } catch (e) {
        console.log('Error closing offscreen document:', e.message);
      }
    }
    
    // Create fresh offscreen document
    await createOffscreenDocument();
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Capture tab audio
    const streamId = await chrome.tabCapture.getMediaStreamId({
      targetTabId: tabId
    });
    
    console.log('Got stream ID:', streamId);
    
    // Send stream ID to offscreen document to start recording
    const response = await chrome.runtime.sendMessage({
      target: 'offscreen',
      action: 'START_CAPTURE',
      streamId: streamId,
      tabId: tabId
    });
    
    console.log('Offscreen response:', response);
    
    if (response && response.error) {
      throw new Error(response.error);
    }
    
    // Update state
    isRecording = true;
    recordingTabId = tabId;
    recordingStartTime = Date.now();
    
    // Update badge
    chrome.action.setBadgeText({ text: 'REC' });
    chrome.action.setBadgeBackgroundColor({ color: '#E9A28B' });
    
    // CRITICAL: Save recording state to storage for persistence
    await chrome.storage.local.set({
      echomind_recording_state: {
        isRecording: true,
        tabId: tabId,
        startTime: recordingStartTime
      }
    });
    
    // Start keep-alive alarm to prevent service worker from dying
    startKeepAliveAlarm();
    
    console.log('Recording started successfully at:', recordingStartTime);
    return { success: true };
    
  } catch (error) {
    console.error('Failed to start recording:', error);
    await resetRecordingState();
    return { success: false, error: error.message };
  }
}

// Stop recording
async function stopRecording() {
  console.log('stopRecording called, isRecording:', isRecording);
  
  // Check storage state
  const data = await chrome.storage.local.get(['echomind_recording_state']);
  const storageState = data.echomind_recording_state;
  
  if (!isRecording && (!storageState || !storageState.isRecording)) {
    console.log('Not recording (both memory and storage say no)');
    await resetRecordingState();
    return { success: true, message: 'Not recording' };
  }
  
  // Sync from storage if memory state is wrong
  if (!isRecording && storageState?.isRecording) {
    console.log('Memory says not recording but storage says yes - syncing');
    isRecording = true;
    recordingTabId = storageState.tabId;
    recordingStartTime = storageState.startTime;
  }
  
  try {
    console.log('Stopping recording...');
    
    const hasOffscreen = await hasOffscreenDocument();
    console.log('Offscreen document exists:', hasOffscreen);
    
    if (!hasOffscreen) {
      console.error('Offscreen document not found!');
      await resetRecordingState();
      return { success: false, error: 'Recording context lost. Please try again.' };
    }
    
    // Tell offscreen document to stop recording
    const response = await Promise.race([
      new Promise((resolve) => {
        chrome.runtime.sendMessage({
          target: 'offscreen',
          action: 'STOP_CAPTURE'
        }, (resp) => {
          if (chrome.runtime.lastError) {
            console.error('Message error:', chrome.runtime.lastError);
            resolve({ error: chrome.runtime.lastError.message });
          } else {
            resolve(resp);
          }
        });
      }),
      new Promise((resolve) => setTimeout(() => resolve({ timeout: true }), 5000))
    ]);
    
    console.log('Stop response:', response);
    
    if (response?.timeout) {
      console.warn('Stop message timed out, forcing cleanup');
      await resetRecordingState();
      return { success: true, message: 'Recording stopped (timeout)' };
    }
    
    if (response?.wasNotRecording) {
      console.log('Offscreen was not recording, cleaning up state');
      await resetRecordingState();
      return { success: true, message: 'Recording was not active' };
    }
    
    // Recording will be processed via RECORDING_STOPPED message
    return { success: true, message: 'Stopping recording...' };
    
  } catch (error) {
    console.error('Failed to stop recording:', error);
    await resetRecordingState();
    return { success: false, error: error.message };
  }
}

// Handle recording stopped and upload
async function handleRecordingStopped(audioBase64, duration) {
  console.log('handleRecordingStopped called, audio length:', audioBase64?.length || 0, 'duration:', duration);
  
  // Stop keep-alive alarm
  stopKeepAliveAlarm();
  
  // Reset state
  isRecording = false;
  recordingTabId = null;
  recordingStartTime = null;
  chrome.action.setBadgeText({ text: '' });
  
  // Close offscreen document
  try {
    if (await hasOffscreenDocument()) {
      await chrome.offscreen.closeDocument();
      console.log('Offscreen document closed');
    }
  } catch (e) {
    console.log('Error closing offscreen document:', e.message);
  }
  
  // If no audio data, just clean up
  if (!audioBase64) {
    console.log('No audio data to upload');
    await chrome.storage.local.set({
      echomind_recording_state: { isRecording: false, processing: false }
    });
    return;
  }
  
  // Update storage to show processing
  await chrome.storage.local.set({
    echomind_recording_state: { isRecording: false, processing: true }
  });
  
  try {
    console.log('Uploading recording...');
    
    const auth = await chrome.storage.local.get(['echomind_auth_token', 'echomind_user']);
    if (!auth.echomind_auth_token || !auth.echomind_user) {
      throw new Error('Not authenticated');
    }
    
    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${auth.echomind_auth_token}`,
      'x-user-id': auth.echomind_user.id
    };
    
    // Get upload URL
    console.log('Getting upload URL...');
    const uploadUrlResponse = await fetch(`${BACKEND_URL}/api/v1/storage/upload-url`, {
      method: 'GET',
      headers
    });
    
    if (!uploadUrlResponse.ok) {
      const errorText = await uploadUrlResponse.text();
      throw new Error(`Failed to get upload URL: ${errorText}`);
    }
    
    const { uploadUrl, path } = await uploadUrlResponse.json();
    console.log('Got upload URL, path:', path);
    
    // Convert base64 to blob
    const binaryString = atob(audioBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    const audioBlob = new Blob([bytes], { type: 'audio/webm' });
    console.log('Audio blob size:', audioBlob.size, 'duration:', duration);
    
    // Upload audio
    console.log('Uploading audio...');
    const uploadResponse = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'audio/webm' },
      body: audioBlob
    });
    
    if (!uploadResponse.ok) {
      throw new Error('Failed to upload audio');
    }
    
    console.log('Audio uploaded, triggering processing...');
    
    // Trigger processing
    const processResponse = await fetch(`${BACKEND_URL}/api/meetings/process`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ path })
    });
    
    if (!processResponse.ok) {
      const errorText = await processResponse.text();
      throw new Error(`Failed to process meeting: ${errorText}`);
    }
    
    const result = await processResponse.json();
    console.log('Meeting processing started:', result);
    
    // Show notification
    chrome.notifications.create({
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: 'EchoMind',
      message: 'Recording uploaded! Processing in background. Check the app for your meeting summary.'
    });
    
    // Update storage
    await chrome.storage.local.set({
      echomind_recording_state: {
        isRecording: false,
        processing: false,
        lastMeetingId: result.meetingId
      }
    });
    
  } catch (error) {
    console.error('Failed to upload recording:', error);
    
    chrome.notifications.create({
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: 'EchoMind - Error',
      message: `Failed to upload recording: ${error.message}`
    });
    
    await chrome.storage.local.set({
      echomind_recording_state: {
        isRecording: false,
        processing: false,
        error: error.message
      }
    });
  }
}

// Clean up when extension is disabled/unloaded
chrome.runtime.onSuspend.addListener(() => {
  console.log('Service worker suspending...');
  // Note: We don't stop recording here because we want it to persist
  // The state is saved in storage and will be restored
});

// EchoMind Extension - Popup Script

const BACKEND_URL = 'http://localhost:8000';
const GOOGLE_CLIENT_ID = '892230117968-s3n9bugmvj04n8dfb9056vc0gc2ve0p3.apps.googleusercontent.com';

// DOM Elements
const loadingView = document.getElementById('loading-view');
const loginView = document.getElementById('login-view');
const registerView = document.getElementById('register-view');
const mainView = document.getElementById('main-view');
const errorMessage = document.getElementById('error-message');

// Login elements
const loginForm = document.getElementById('login-form');
const loginEmail = document.getElementById('login-email');
const loginPassword = document.getElementById('login-password');
const googleSigninBtn = document.getElementById('google-signin-btn');
const showRegisterLink = document.getElementById('show-register');

// Register elements
const registerForm = document.getElementById('register-form');
const registerName = document.getElementById('register-name');
const registerEmail = document.getElementById('register-email');
const registerPassword = document.getElementById('register-password');
const showLoginLink = document.getElementById('show-login');

// Main view elements
const userAvatar = document.getElementById('user-avatar');
const userName = document.getElementById('user-name');
const userEmail = document.getElementById('user-email');
const recordBtn = document.getElementById('record-btn');
const recordStatus = document.getElementById('record-status');
const recordTime = document.getElementById('record-time');
const statusMessage = document.getElementById('status-message');
const settingsBtn = document.getElementById('settings-btn');
const signoutBtn = document.getElementById('signout-btn');

// State
let isRecording = false;
let recordingStartTime = null;
let recordingTimer = null;

// Initialize
document.addEventListener('DOMContentLoaded', init);

async function init() {
  showView('loading');
  
  try {
    // Check if user is logged in
    const result = await chrome.storage.local.get(['echomind_user', 'echomind_auth_token']);
    
    if (result.echomind_user && result.echomind_auth_token) {
      // User is logged in
      await loadMainView(result.echomind_user);
    } else {
      // Show login
      showView('login');
    }
  } catch (error) {
    console.error('Init error:', error);
    showView('login');
  }
}

// View switching
function showView(view) {
  loadingView.classList.add('hidden');
  loginView.classList.add('hidden');
  registerView.classList.add('hidden');
  mainView.classList.add('hidden');
  hideError();
  
  switch (view) {
    case 'loading':
      loadingView.classList.remove('hidden');
      break;
    case 'login':
      loginView.classList.remove('hidden');
      break;
    case 'register':
      registerView.classList.remove('hidden');
      break;
    case 'main':
      mainView.classList.remove('hidden');
      break;
  }
}

// Error handling
function showError(message) {
  errorMessage.textContent = message;
  errorMessage.classList.remove('hidden');
}

function hideError() {
  errorMessage.classList.add('hidden');
}

function showStatus(message, type = 'info') {
  statusMessage.textContent = message;
  statusMessage.className = `status-message ${type}`;
  statusMessage.classList.remove('hidden');
}

function hideStatus() {
  statusMessage.classList.add('hidden');
}

// Event Listeners
showRegisterLink.addEventListener('click', (e) => {
  e.preventDefault();
  showView('register');
});

showLoginLink.addEventListener('click', (e) => {
  e.preventDefault();
  showView('login');
});

// Login form
loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  hideError();
  
  const email = loginEmail.value.trim();
  const password = loginPassword.value;
  
  if (!email || !password) {
    showError('Please enter email and password');
    return;
  }
  
  try {
    loginForm.querySelector('button').disabled = true;
    
    const response = await fetch(`${BACKEND_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    
    const data = await response.json();
    
    if (!response.ok) {
      throw new Error(data.detail || 'Login failed');
    }
    
    // Save auth data
    await chrome.storage.local.set({
      echomind_user: data.user,
      echomind_auth_token: data.access_token
    });
    
    await loadMainView(data.user);
    
  } catch (error) {
    showError(error.message);
  } finally {
    loginForm.querySelector('button').disabled = false;
  }
});

// Register form
registerForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  hideError();
  
  const name = registerName.value.trim();
  const email = registerEmail.value.trim();
  const password = registerPassword.value;
  
  if (!name || !email || !password) {
    showError('Please fill in all fields');
    return;
  }
  
  if (password.length < 6) {
    showError('Password must be at least 6 characters');
    return;
  }
  
  try {
    registerForm.querySelector('button').disabled = true;
    
    const response = await fetch(`${BACKEND_URL}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, email, password })
    });
    
    const data = await response.json();
    
    if (!response.ok) {
      throw new Error(data.detail || 'Registration failed');
    }
    
    // Save auth data
    await chrome.storage.local.set({
      echomind_user: data.user,
      echomind_auth_token: data.access_token
    });
    
    await loadMainView(data.user);
    
  } catch (error) {
    showError(error.message);
  } finally {
    registerForm.querySelector('button').disabled = false;
  }
});

// Google Sign In using chrome.identity.getAuthToken (simpler approach)
googleSigninBtn.addEventListener('click', async () => {
  hideError();
  
  try {
    googleSigninBtn.disabled = true;
    
    // Get the redirect URL for this extension
    const redirectUrl = chrome.identity.getRedirectURL();
    console.log('Extension redirect URL:', redirectUrl);
    
    // Use Chrome Identity API with launchWebAuthFlow
    // The redirect URI format is: https://<extension-id>.chromiumapp.org/
    const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?` +
      `client_id=${GOOGLE_CLIENT_ID}&` +
      `response_type=token&` +
      `redirect_uri=${encodeURIComponent(redirectUrl)}&` +
      `scope=${encodeURIComponent('email profile')}`;
    
    console.log('Auth URL:', authUrl);
    
    chrome.identity.launchWebAuthFlow(
      { url: authUrl, interactive: true },
      async (responseUrl) => {
        if (chrome.runtime.lastError) {
          const errorMsg = chrome.runtime.lastError.message;
          console.error('Auth error:', errorMsg);
          
          // If redirect_uri_mismatch, show helpful message
          if (errorMsg.includes('redirect_uri_mismatch') || errorMsg.includes('invalid')) {
            showError(`Google OAuth not configured. Add this redirect URI to Google Cloud Console:\n${redirectUrl}`);
            
            // Also copy to clipboard
            navigator.clipboard.writeText(redirectUrl).then(() => {
              console.log('Redirect URI copied to clipboard');
            });
          } else {
            showError(errorMsg);
          }
          googleSigninBtn.disabled = false;
          return;
        }
        
        if (!responseUrl) {
          showError('Authentication was cancelled');
          googleSigninBtn.disabled = false;
          return;
        }
        
        try {
          // Extract access token from redirect URL
          const params = new URLSearchParams(responseUrl.split('#')[1]);
          const accessToken = params.get('access_token');
          
          if (!accessToken) {
            throw new Error('No access token received');
          }
          
          // Get user info from Google
          const userInfoResponse = await fetch(
            `https://www.googleapis.com/oauth2/v2/userinfo?access_token=${accessToken}`
          );
          const userInfo = await userInfoResponse.json();
          
          console.log('Google user info:', userInfo);
          
          // Call our backend extension auth endpoint with Google access token
          const response = await fetch(`${BACKEND_URL}/auth/google/extension`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ 
              access_token: accessToken,
              email: userInfo.email,
              name: userInfo.name,
              google_id: userInfo.id,
              picture: userInfo.picture
            })
          });
          
          const data = await response.json();
          
          if (!response.ok) {
            throw new Error(data.detail || 'Google authentication failed');
          }
          
          // Save auth data
          await chrome.storage.local.set({
            echomind_user: data.user,
            echomind_auth_token: data.access_token
          });
          
          await loadMainView(data.user);
          
        } catch (error) {
          showError(error.message);
        } finally {
          googleSigninBtn.disabled = false;
        }
      }
    );
    
  } catch (error) {
    showError(error.message);
    googleSigninBtn.disabled = false;
  }
});

// Load main view
async function loadMainView(user) {
  // Update user info
  userName.textContent = user.name || 'User';
  userEmail.textContent = user.email;
  userAvatar.textContent = (user.name || user.email)[0].toUpperCase();
  
  // Check current recording state from background (source of truth)
  try {
    const state = await chrome.runtime.sendMessage({ action: 'GET_RECORDING_STATE' });
    console.log('Recording state from background:', state);
    isRecording = state?.isRecording || false;
    
    // If recording, restore the timer using the actual start time
    if (isRecording && state?.startTime) {
      recordingStartTime = state.startTime;
      startTimer();
      showStatus('Recording in progress', 'info');
    }
  } catch (e) {
    console.error('Error getting recording state:', e);
    isRecording = false;
  }
  
  updateRecordingUI();
  
  showView('main');
}

// Recording
recordBtn.addEventListener('click', async () => {
  // Always get fresh state from background before acting
  const state = await chrome.runtime.sendMessage({ action: 'GET_RECORDING_STATE' });
  console.log('Current recording state:', state);
  isRecording = state?.isRecording || false;
  
  if (isRecording) {
    await stopRecording();
  } else {
    await startRecording();
  }
});

async function startRecording() {
  try {
    recordBtn.disabled = true;
    showStatus('Starting recording...', 'info');
    
    // Get current tab
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    
    if (!tab) {
      throw new Error('No active tab found');
    }
    
    // Send message to background to start recording
    const result = await chrome.runtime.sendMessage({
      action: 'START_RECORDING',
      tabId: tab.id
    });
    
    if (!result.success) {
      throw new Error(result.error || 'Failed to start recording');
    }
    
    isRecording = true;
    recordingStartTime = Date.now();
    startTimer();
    updateRecordingUI();
    showStatus('Recording started!', 'success');
    
    // Hide status after 3 seconds
    setTimeout(hideStatus, 3000);
    
  } catch (error) {
    showStatus(error.message, 'error');
    console.error('Start recording error:', error);
  } finally {
    recordBtn.disabled = false;
  }
}

async function stopRecording() {
  try {
    recordBtn.disabled = true;
    showStatus('Stopping recording...', 'info');
    
    const result = await chrome.runtime.sendMessage({ action: 'STOP_RECORDING' });
    console.log('Stop recording result:', result);
    
    // Always reset local state after stop attempt
    isRecording = false;
    stopTimer();
    updateRecordingUI();
    
    if (!result.success) {
      showStatus(result.error || 'Failed to stop recording', 'error');
    } else if (result.message === 'Not recording' || result.message === 'Recording was not active') {
      showStatus('Recording was not active', 'info');
    } else {
      showStatus('Recording stopped. Uploading...', 'success');
    }
    
  } catch (error) {
    // Even on error, reset local state
    isRecording = false;
    stopTimer();
    updateRecordingUI();
    showStatus(error.message, 'error');
    console.error('Stop recording error:', error);
  } finally {
    recordBtn.disabled = false;
  }
}

function updateRecordingUI() {
  if (isRecording) {
    recordBtn.classList.add('recording');
    recordStatus.textContent = 'Recording in progress...';
    recordTime.classList.remove('hidden');
  } else {
    recordBtn.classList.remove('recording');
    recordStatus.textContent = 'Tap to start recording';
    recordTime.classList.add('hidden');
    recordTime.textContent = '00:00';
  }
}

function startTimer() {
  recordingTimer = setInterval(() => {
    if (!recordingStartTime) return;
    
    const elapsed = Math.floor((Date.now() - recordingStartTime) / 1000);
    const minutes = Math.floor(elapsed / 60).toString().padStart(2, '0');
    const seconds = (elapsed % 60).toString().padStart(2, '0');
    recordTime.textContent = `${minutes}:${seconds}`;
  }, 1000);
}

function stopTimer() {
  if (recordingTimer) {
    clearInterval(recordingTimer);
    recordingTimer = null;
  }
  recordingStartTime = null;
}

// Settings
settingsBtn.addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
});

// Sign out
signoutBtn.addEventListener('click', async () => {
  try {
    // Check actual recording state from background
    const state = await chrome.runtime.sendMessage({ action: 'GET_RECORDING_STATE' });
    
    // Stop recording if actually active
    if (state?.isRecording) {
      await stopRecording();
    }
    
    // Clear storage
    await chrome.storage.local.remove(['echomind_user', 'echomind_auth_token']);
    
    // Reset local state
    isRecording = false;
    stopTimer();
    
    // Show login
    showView('login');
    
  } catch (error) {
    showError(error.message);
  }
});

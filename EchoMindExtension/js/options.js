// EchoMind Extension - Options/Settings Script

const DEFAULT_SETTINGS = {
  inputDeviceId: 'default',
  outputDeviceId: 'default',
  backendUrl: 'https://echomind-tvw1.onrender.com',
  autoUpload: true
};

// DOM Elements
const inputDevice = document.getElementById('input-device');
const outputDevice = document.getElementById('output-device');
const refreshDevicesBtn = document.getElementById('refresh-devices');
const backendUrl = document.getElementById('backend-url');
const connectionStatus = document.getElementById('connection-status');
const testConnectionBtn = document.getElementById('test-connection');
const autoUpload = document.getElementById('auto-upload');
const saveSettingsBtn = document.getElementById('save-settings');
const resetSettingsBtn = document.getElementById('reset-settings');
const statusMessage = document.getElementById('status-message');

// Permission elements
const micPermissionStatus = document.getElementById('mic-permission-status');
const requestMicPermissionBtn = document.getElementById('request-mic-permission');
const notifPermissionStatus = document.getElementById('notif-permission-status');
const requestNotifPermissionBtn = document.getElementById('request-notif-permission');

// Initialize
document.addEventListener('DOMContentLoaded', init);

async function init() {
  await checkPermissions();
  await loadSettings();
  await loadDevices();
  await testConnection();
}

// Check and display permission status
async function checkPermissions() {
  // Check microphone permission
  try {
    const micPermission = await navigator.permissions.query({ name: 'microphone' });
    updateMicPermissionUI(micPermission.state);
    
    // Listen for permission changes
    micPermission.onchange = () => {
      updateMicPermissionUI(micPermission.state);
      if (micPermission.state === 'granted') {
        loadDevices(); // Reload devices when permission is granted
      }
    };
  } catch (error) {
    console.warn('Could not query microphone permission:', error);
    // Try to detect by attempting to get devices
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      const hasLabels = devices.some(d => d.kind === 'audioinput' && d.label);
      updateMicPermissionUI(hasLabels ? 'granted' : 'prompt');
    } catch (e) {
      updateMicPermissionUI('denied');
    }
  }

  // Check notification permission
  if ('Notification' in window) {
    updateNotifPermissionUI(Notification.permission);
  } else {
    updateNotifPermissionUI('not-supported');
  }
}

function updateMicPermissionUI(state) {
  if (state === 'granted') {
    micPermissionStatus.textContent = 'Granted';
    micPermissionStatus.className = 'status-badge granted';
    requestMicPermissionBtn.style.display = 'none';
  } else if (state === 'denied') {
    micPermissionStatus.textContent = 'Denied';
    micPermissionStatus.className = 'status-badge denied';
    requestMicPermissionBtn.textContent = 'Open Settings';
    requestMicPermissionBtn.style.display = 'inline-block';
  } else {
    micPermissionStatus.textContent = 'Not granted';
    micPermissionStatus.className = 'status-badge pending';
    requestMicPermissionBtn.textContent = 'Grant Access';
    requestMicPermissionBtn.style.display = 'inline-block';
  }
}

function updateNotifPermissionUI(state) {
  if (state === 'granted') {
    notifPermissionStatus.textContent = 'Enabled';
    notifPermissionStatus.className = 'status-badge granted';
    requestNotifPermissionBtn.style.display = 'none';
  } else if (state === 'denied') {
    notifPermissionStatus.textContent = 'Blocked';
    notifPermissionStatus.className = 'status-badge denied';
    requestNotifPermissionBtn.textContent = 'Open Settings';
    requestNotifPermissionBtn.style.display = 'inline-block';
  } else if (state === 'not-supported') {
    notifPermissionStatus.textContent = 'Not supported';
    notifPermissionStatus.className = 'status-badge denied';
    requestNotifPermissionBtn.style.display = 'none';
  } else {
    notifPermissionStatus.textContent = 'Not enabled';
    notifPermissionStatus.className = 'status-badge pending';
    requestNotifPermissionBtn.textContent = 'Enable';
    requestNotifPermissionBtn.style.display = 'inline-block';
  }
}

// Request microphone permission
async function requestMicrophonePermission() {
  try {
    // Always try to request permission first - Chrome will show the prompt
    // if it hasn't been permanently denied
    showStatus('Requesting microphone permission...', 'info');
    
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      
      // Permission granted! Stop the stream immediately
      stream.getTracks().forEach(track => track.stop());
      
      showStatus('Microphone permission granted!', 'success');
      updateMicPermissionUI('granted');
      
      // Reload devices to get proper labels
      await loadDevices();
      return;
      
    } catch (error) {
      console.log('getUserMedia error:', error.name, error.message);
      
      if (error.name === 'NotAllowedError' || error.name === 'PermissionDeniedError') {
        // Permission was denied - check if it's permanent
        let isPermanentlyDenied = false;
        try {
          const permission = await navigator.permissions.query({ name: 'microphone' });
          isPermanentlyDenied = permission.state === 'denied';
        } catch (e) {
          // Can't query, assume denied
          isPermanentlyDenied = true;
        }

        if (isPermanentlyDenied) {
          updateMicPermissionUI('denied');
          // Show instructions since we can't open chrome:// URLs
          showPermissionInstructions('microphone');
        } else {
          // User just dismissed the prompt
          showStatus('Microphone permission was not granted. Please try again and click "Allow".', 'warning');
        }
      } else if (error.name === 'NotFoundError') {
        showStatus('No microphone found. Please connect a microphone and try again.', 'error');
      } else {
        showStatus('Could not access microphone: ' + error.message, 'error');
      }
    }
    
  } catch (error) {
    console.error('Microphone permission error:', error);
    showStatus('Error requesting microphone permission: ' + error.message, 'error');
  }
}

// Show permission instructions modal
function showPermissionInstructions(type) {
  const instructions = type === 'microphone' 
    ? `To enable microphone access:

1. Click the lock/tune icon in Chrome's address bar (left of the URL)
2. Find "Microphone" in the permissions list
3. Change it from "Block" to "Allow"
4. Refresh this page

Or go to: chrome://settings/content/microphone
and add this extension to the allowed list.`
    : `To enable notifications:

1. Click the lock/tune icon in Chrome's address bar
2. Find "Notifications" in the permissions list  
3. Change it to "Allow"
4. Refresh this page`;

  // Create modal
  const modal = document.createElement('div');
  modal.className = 'permission-modal';
  modal.innerHTML = `
    <div class="permission-modal-content">
      <h3>Permission Required</h3>
      <pre>${instructions}</pre>
      <div class="permission-modal-actions">
        <button class="btn btn-secondary" onclick="navigator.clipboard.writeText('chrome://settings/content/${type}').then(() => this.textContent = 'Copied!')">Copy Settings URL</button>
        <button class="btn btn-primary" onclick="this.closest('.permission-modal').remove()">Got it</button>
      </div>
    </div>
  `;
  document.body.appendChild(modal);
}

// Request notification permission
async function requestNotificationPermission() {
  try {
    if (!('Notification' in window)) {
      showStatus('Notifications are not supported in this browser', 'error');
      return;
    }

    if (Notification.permission === 'denied') {
      showPermissionInstructions('notifications');
      return;
    }

    const permission = await Notification.requestPermission();
    updateNotifPermissionUI(permission);
    
    if (permission === 'granted') {
      showStatus('Notifications enabled!', 'success');
      // Show a test notification
      new Notification('EchoMind', {
        body: 'Notifications are now enabled!',
        icon: 'icons/icon128.png'
      });
    } else {
      showStatus('Notification permission was not granted', 'warning');
    }
  } catch (error) {
    console.error('Notification permission error:', error);
    showStatus('Could not request notification permission: ' + error.message, 'error');
  }
}

// Load settings from storage
async function loadSettings() {
  try {
    const result = await chrome.storage.local.get(['echomind_settings']);
    const settings = { ...DEFAULT_SETTINGS, ...result.echomind_settings };
    
    backendUrl.value = settings.backendUrl;
    autoUpload.checked = settings.autoUpload;
    
    // Device IDs will be set after loading devices
    inputDevice.dataset.savedValue = settings.inputDeviceId;
    outputDevice.dataset.savedValue = settings.outputDeviceId;
    
  } catch (error) {
    console.error('Failed to load settings:', error);
  }
}

// Load audio devices
async function loadDevices() {
  try {
    // Check if we have microphone permission first
    let hasPermission = false;
    try {
      const permission = await navigator.permissions.query({ name: 'microphone' });
      hasPermission = permission.state === 'granted';
    } catch (e) {
      // Fallback: try to enumerate devices and check for labels
      const devices = await navigator.mediaDevices.enumerateDevices();
      hasPermission = devices.some(d => d.kind === 'audioinput' && d.label);
    }

    if (!hasPermission) {
      // Don't request permission here, just show a message
      console.log('Microphone permission not granted yet');
      inputDevice.innerHTML = '<option value="default">Default Microphone (permission required)</option>';
      return;
    }

    const devices = await navigator.mediaDevices.enumerateDevices();
    
    // Clear existing options
    inputDevice.innerHTML = '<option value="default">Default Microphone</option>';
    outputDevice.innerHTML = '<option value="default">Default Output (Tab Audio)</option>';
    
    // Add input devices (microphones)
    const audioInputs = devices.filter(d => d.kind === 'audioinput');
    audioInputs.forEach(device => {
      if (device.deviceId === 'default') return;
      
      const option = document.createElement('option');
      option.value = device.deviceId;
      option.textContent = device.label || `Microphone ${inputDevice.options.length}`;
      inputDevice.appendChild(option);
    });
    
    // Add output devices (for reference - tab capture doesn't use these)
    const audioOutputs = devices.filter(d => d.kind === 'audiooutput');
    audioOutputs.forEach(device => {
      if (device.deviceId === 'default') return;
      
      const option = document.createElement('option');
      option.value = device.deviceId;
      option.textContent = device.label || `Output ${outputDevice.options.length}`;
      outputDevice.appendChild(option);
    });
    
    // Set saved values if they exist
    if (inputDevice.dataset.savedValue) {
      const savedInput = inputDevice.dataset.savedValue;
      if ([...inputDevice.options].some(o => o.value === savedInput)) {
        inputDevice.value = savedInput;
      }
    }
    
    if (outputDevice.dataset.savedValue) {
      const savedOutput = outputDevice.dataset.savedValue;
      if ([...outputDevice.options].some(o => o.value === savedOutput)) {
        outputDevice.value = savedOutput;
      }
    }
    
  } catch (error) {
    console.error('Failed to load devices:', error.message || error);
    showStatus('Could not load audio devices: ' + (error.message || 'Unknown error'), 'error');
  }
}

// Test backend connection
async function testConnection() {
  const url = backendUrl.value.trim();
  
  setConnectionStatus('checking', 'Checking connection...');
  
  try {
    const response = await fetch(`${url}/health`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000)
    });
    
    if (response.ok) {
      setConnectionStatus('connected', 'Connected to backend');
    } else {
      setConnectionStatus('disconnected', 'Backend returned an error');
    }
  } catch (error) {
    setConnectionStatus('disconnected', 'Cannot connect to backend');
  }
}

function setConnectionStatus(status, text) {
  connectionStatus.className = `connection-status ${status}`;
  connectionStatus.querySelector('.status-text').textContent = text;
}

// Save settings
async function saveSettings() {
  try {
    const settings = {
      inputDeviceId: inputDevice.value,
      outputDeviceId: outputDevice.value,
      backendUrl: backendUrl.value.trim(),
      autoUpload: autoUpload.checked
    };
    
    await chrome.storage.local.set({ echomind_settings: settings });
    
    showStatus('Settings saved successfully!', 'success');
    
    // Re-test connection with new URL
    await testConnection();
    
  } catch (error) {
    showStatus('Failed to save settings: ' + error.message, 'error');
  }
}

// Reset settings
async function resetSettings() {
  try {
    await chrome.storage.local.set({ echomind_settings: DEFAULT_SETTINGS });
    
    backendUrl.value = DEFAULT_SETTINGS.backendUrl;
    autoUpload.checked = DEFAULT_SETTINGS.autoUpload;
    inputDevice.value = 'default';
    outputDevice.value = 'default';
    
    showStatus('Settings reset to defaults', 'success');
    
    await testConnection();
    
  } catch (error) {
    showStatus('Failed to reset settings: ' + error.message, 'error');
  }
}

// Show status message
function showStatus(message, type) {
  statusMessage.textContent = message;
  statusMessage.className = `status-message ${type}`;
  statusMessage.classList.remove('hidden');
  
  // Auto-hide after longer time for warnings/errors
  const hideDelay = (type === 'error' || type === 'warning') ? 6000 : 3000;
  setTimeout(() => {
    statusMessage.classList.add('hidden');
  }, hideDelay);
}

// Event Listeners
refreshDevicesBtn.addEventListener('click', loadDevices);
testConnectionBtn.addEventListener('click', testConnection);
saveSettingsBtn.addEventListener('click', saveSettings);
resetSettingsBtn.addEventListener('click', resetSettings);
requestMicPermissionBtn.addEventListener('click', requestMicrophonePermission);
requestNotifPermissionBtn.addEventListener('click', requestNotificationPermission);

// Auto-save backend URL on change
backendUrl.addEventListener('change', testConnection);

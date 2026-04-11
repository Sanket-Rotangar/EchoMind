// EchoMind Extension Configuration
const CONFIG = {
  // Backend URL - defaults to production, can be overridden in settings
  BACKEND_URL: 'https://echomind-tvw1.onrender.com',
  
  // Google OAuth Client ID (same as mobile app - Web client ID)
  GOOGLE_CLIENT_ID: '892230117968-s3n9bugmvj04n8dfb9056vc0gc2ve0p3.apps.googleusercontent.com',
  
  // Storage keys
  STORAGE_KEYS: {
    USER: 'echomind_user',
    AUTH_TOKEN: 'echomind_auth_token',
    SETTINGS: 'echomind_settings',
    RECORDING_STATE: 'echomind_recording_state'
  },
  
  // Default settings
  DEFAULT_SETTINGS: {
    inputDeviceId: 'default',
    outputDeviceId: 'default',
    autoUpload: true
  },
  
  // Audio recording settings
  AUDIO_CONFIG: {
    mimeType: 'audio/webm;codecs=opus',
    audioBitsPerSecond: 128000
  }
};

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = CONFIG;
}

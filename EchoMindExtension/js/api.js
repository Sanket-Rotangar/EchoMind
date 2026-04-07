// EchoMind API Service - Communicates with the backend
class ApiService {
  constructor() {
    this.baseUrl = 'http://localhost:8000';
  }

  async setBaseUrl(url) {
    this.baseUrl = url;
  }

  async getAuthHeaders() {
    const result = await chrome.storage.local.get(['echomind_auth_token', 'echomind_user']);
    const token = result.echomind_auth_token;
    const user = result.echomind_user;

    if (!token || !user) {
      throw new Error('Not authenticated');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      'x-user-id': user.id
    };
  }

  // Authentication
  async registerWithEmail(email, password, name) {
    const response = await fetch(`${this.baseUrl}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, name })
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || 'Registration failed');
    }

    return data;
  }

  async loginWithEmail(email, password) {
    const response = await fetch(`${this.baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || 'Login failed');
    }

    return data;
  }

  async loginWithGoogle(idToken) {
    const response = await fetch(`${this.baseUrl}/auth/google`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id_token: idToken })
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || 'Google login failed');
    }

    return data;
  }

  // Get upload URL for audio
  async getUploadUrl() {
    const headers = await this.getAuthHeaders();
    const response = await fetch(`${this.baseUrl}/api/v1/storage/upload-url`, {
      method: 'GET',
      headers
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || 'Failed to get upload URL');
    }

    return data;
  }

  // Upload audio file to storage
  async uploadAudio(uploadUrl, audioBlob) {
    const response = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'audio/webm' },
      body: audioBlob
    });

    if (!response.ok) {
      throw new Error('Failed to upload audio');
    }

    return true;
  }

  // Process meeting audio
  async processMeeting(path) {
    const headers = await this.getAuthHeaders();
    const response = await fetch(`${this.baseUrl}/api/meetings/process`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ path })
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || 'Failed to process meeting');
    }

    return data;
  }

  // Get user profile
  async getUserProfile() {
    const headers = await this.getAuthHeaders();
    const response = await fetch(`${this.baseUrl}/api/v1/user/profile`, {
      method: 'GET',
      headers
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || 'Failed to get profile');
    }

    return data;
  }

  // Health check
  async healthCheck() {
    try {
      const response = await fetch(`${this.baseUrl}/health`);
      return response.ok;
    } catch {
      return false;
    }
  }
}

// Export singleton
const apiService = new ApiService();

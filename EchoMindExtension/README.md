# EchoMind Chrome Extension

AI-powered meeting intelligence - Record and transcribe your meetings directly from your browser.

## Features

- **Sign In with Email/Password or Google** - Uses the same authentication as the mobile app
- **Record Tab Audio** - Captures audio from Google Meet, Zoom, Teams, or any other meeting platform
- **Record Microphone** - Also captures your voice during meetings
- **Auto-Upload** - Automatically uploads recordings to the backend for processing
- **Device Selection** - Choose your preferred microphone in settings
- **Real-time Status** - See recording status with timer

## Installation

### 1. Load the Extension in Chrome

1. Open Chrome and go to `chrome://extensions/`
2. Enable **Developer mode** (toggle in the top-right corner)
3. Click **Load unpacked**
4. Select the `EchoMindExtension` folder (`D:\PHANTOM_CODEEE\EchoMind\EchoMindExtension`)
5. The EchoMind icon should appear in your extensions bar

### 2. Start the Backend

Make sure your EchoMind backend is running:

```bash
cd D:\PHANTOM_CODEEE\EchoMind\meeting_backend
python main.py
```

The backend should be running at `http://localhost:8000`

### 3. Configure the Extension (if needed)

1. Click the EchoMind extension icon
2. If the backend is not at `localhost:8000`, click **Settings**
3. Update the **Backend URL** to match your setup
4. Click **Save Settings**

## Usage

### Sign In

1. Click the EchoMind extension icon
2. Sign in with your email/password or use Google Sign In
3. Use the same credentials as the mobile app

### Recording a Meeting

1. Join your meeting (Google Meet, Zoom, etc.) in a browser tab
2. Click the EchoMind extension icon
3. Click the record button (large circle)
4. The button will pulse and show "Recording in progress..."
5. A timer shows how long you've been recording
6. When done, click the button again to stop
7. The recording will automatically upload and process
8. Check the EchoMind mobile app for your meeting summary!

### Settings

Click **Settings** in the extension popup to:
- Select your microphone device
- Change the backend URL
- Enable/disable auto-upload

## How It Works

1. **Tab Capture** - The extension uses Chrome's tabCapture API to record audio from the current tab
2. **Microphone Capture** - Optionally captures your microphone input
3. **Audio Mixing** - Combines both audio sources into a single recording
4. **Upload** - Sends the recording to the EchoMind backend
5. **Processing** - Backend transcribes and analyzes the meeting with AI
6. **View Results** - Open the EchoMind app to see the summary, action items, and more

## Troubleshooting

### "Cannot connect to backend"
- Make sure the backend is running at the configured URL
- Check if `http://localhost:8000/health` returns a response

### "Please sign in first"
- Click the extension and sign in with your credentials

### Audio not being captured
- Make sure you're on the correct tab when starting recording
- Check that your microphone permissions are granted
- Try refreshing the page and starting again

### Recording fails to upload
- Check your internet connection
- Verify the backend is running
- Check the browser console for error details

## Development

The extension consists of:
- `manifest.json` - Extension configuration
- `popup.html/js/css` - Main popup UI
- `options.html/js/css` - Settings page
- `background.js` - Service worker for recording logic
- `offscreen.html/js` - Offscreen document for audio capture

## Privacy

- All recordings are sent to YOUR local backend
- No data is sent to external servers (except Google for authentication)
- Recordings are only captured when you explicitly start recording

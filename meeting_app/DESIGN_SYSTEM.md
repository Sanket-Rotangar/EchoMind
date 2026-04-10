# EchoMind Design System
## Premium AI Product UI/UX

---

## 🎨 Design Philosophy

EchoMind uses a **hybrid design system** combining:
- **Dark Luxury UI** - Premium, executive-grade aesthetics
- **Glassmorphism** - Frosted glass effects with blur
- **Minimalism** - Clean, uncluttered interfaces
- **Bento Grid** - Modern tile-based layouts
- **Soft Neumorphism** - Subtle depth for interactive elements
- **Claymorphism** - 3D icons for branding
- **Y2K Gradients** - Soft gradient accents
- **Micro-animations** - Smooth, calm interactions

---

## 🎨 Color Palette

```dart
// Backgrounds
background: #0B0B0F  // Deep dark base
surface: #111117     // Elevated surfaces
glassSurface: rgba(255,255,255,0.05)  // Frosted glass

// Accents
primaryAccent: #FF9A8B   // Coral pink
secondaryAccent: #6DD5FA // Sky blue
accentPink: #FF6A88      // Hot pink

// Text
textPrimary: #FFFFFF     // Pure white
textSecondary: #9CA3AF   // Soft gray

// Gradients
primaryGradient: #FF9A8B → #FF6A88
secondaryGradient: #6DD5FA → #2193B0
```

---

## 📐 Typography

**Font Family:** Inter / SF Pro

**Scale:**
- Display: 32px, Bold, 1.2 letter-spacing
- Title: 24px, Bold, 0.5 letter-spacing
- Heading: 18px, SemiBold
- Body: 15px, Regular, 1.5 line-height
- Caption: 13px, Regular

---

## 🧩 Component Library

### 1. GlassCard
Frosted glass container with blur effect.

**Usage:**
```dart
GlassCard(
  padding: EdgeInsets.all(24),
  borderRadius: 24,
  blur: 30,
  child: YourContent(),
)
```

**Properties:**
- Blur: 20-40px
- Border: 1px rgba(255,255,255,0.1)
- Shadow: Soft layered shadows
- Hover: Subtle elevation

---

### 2. BentoTile
Modern tile for grid layouts with hover effects.

**Usage:**
```dart
BentoTile(
  width: 200,
  height: 150,
  showGradientBorder: true,
  onTap: () {},
  child: YourContent(),
)
```

**Features:**
- Hover elevation (-4px translate)
- Gradient border option
- Smooth animations
- Glass background

---

### 3. GradientButton
Primary action button with gradient and glow.

**Usage:**
```dart
GradientButton(
  text: 'Sign In',
  icon: Icons.login,
  onPressed: () {},
  isLoading: false,
)
```

**Features:**
- Gradient background
- Glow shadow
- Press depth animation
- Loading state

---

### 4. NeumorphicButton
Soft neumorphic button for secondary actions.

**Usage:**
```dart
NeumorphicButton(
  width: 200,
  height: 56,
  onPressed: () {},
  child: Text('Action'),
)
```

**Features:**
- Soft shadows (inner/outer)
- Press depth effect
- Subtle elevation

---

### 5. GlowIcon
Icon with animated glow effect.

**Usage:**
```dart
GlowIcon(
  icon: Icons.mic,
  size: 48,
  color: AppColors.primaryAccent,
  animate: true,
)
```

**Features:**
- Pulsing glow animation
- Customizable color
- Size variants

---

### 6. AssistantMessageBubble
Chat message bubble for AI assistant.

**Usage:**
```dart
AssistantMessageBubble(
  message: 'Hello!',
  isUser: false,
  isTyping: false,
)
```

**Features:**
- Gradient for AI messages
- Glass for user messages
- Typing indicator animation
- Smooth appearance

---

## 🎬 Animation Guidelines

### Timing
- **Fast:** 150ms - Button presses, toggles
- **Medium:** 200-300ms - Card hovers, transitions
- **Slow:** 600ms+ - Page transitions, complex animations

### Curves
- **easeInOut:** General purpose
- **easeOut:** Entrances
- **easeIn:** Exits
- **elasticOut:** Playful interactions

### Effects
1. **Hover Elevation:** -4px Y translate
2. **Button Press:** 0.98 scale
3. **Card Entrance:** Fade + slide from bottom
4. **Glow Pulse:** Opacity 0.5 → 1.0 (2s loop)
5. **Recording Pulse:** Scale 1.0 → 1.1 (1s loop)

---

## 📱 Screen Layouts

### Login Screen
```
┌─────────────────────────┐
│                         │
│      [LOGO + GLOW]      │
│                         │
│   ┌─────────────────┐   │
│   │  Glass Card     │   │
│   │  - Title        │   │
│   │  - Google Btn   │   │
│   └─────────────────┘   │
│                         │
└─────────────────────────┘
```

**Components:**
- Centered layout
- Large glowing logo
- Glass login card
- Gradient sign-in button

---

### Record Screen
```
┌─────────────────────────┐
│   [Logo]    [Settings]  │
│                         │
│                         │
│     ┌─────────────┐     │
│     │   Glowing   │     │
│     │  Microphone │     │
│     │     Orb     │     │
│     └─────────────┘     │
│                         │
│   [Status Text]         │
│   [Upload Button]       │
│                         │
└─────────────────────────┘
```

**Components:**
- Large glowing orb (160px)
- Pulsing animation when recording
- Gradient ring
- Glass status card
- Floating upload button

---

### Meetings List (Bento Grid)
```
┌─────────────────────────┐
│  [Header]               │
│                         │
│  ┌────────┐  ┌────────┐ │
│  │Meeting │  │Meeting │ │
│  │  Card  │  │  Card  │ │
│  └────────┘  └────────┘ │
│                         │
│  ┌────────┐  ┌────────┐ │
│  │Meeting │  │Meeting │ │
│  │  Card  │  │  Card  │ │
│  └────────┘  └────────┘ │
│                         │
└─────────────────────────┘
```

**Components:**
- Bento grid layout (2 columns)
- Glass meeting cards
- Status badges with glow
- Hover elevation
- Gradient indicators

---

### Meeting Summary
```
┌─────────────────────────┐
│  [Back] [Title] [Share] │
│                         │
│  ┌─────────────────────┐│
│  │ Executive Summary   ││
│  └─────────────────────┘│
│                         │
│  ┌──────┐  ┌──────────┐ │
│  │Metric│  │ Metrics  │ │
│  └──────┘  └──────────┘ │
│                         │
│  ┌─────────────────────┐│
│  │   Action Items      ││
│  └─────────────────────┘│
│                         │
│  ┌─────────────────────┐│
│  │  Decisions Made     ││
│  └─────────────────────┘│
│                         │
└─────────────────────────┘
```

**Components:**
- Bento tile sections
- Glass cards with icons
- Gradient status badges
- Smooth scroll
- Collapsible sections

---

### AI Assistant Chat
```
┌─────────────────────────┐
│  [Back]  AI Assistant   │
│                         │
│  ┌─────────────────┐    │
│  │ AI Message      │    │
│  │ (Gradient)      │    │
│  └─────────────────┘    │
│                         │
│         ┌───────────┐   │
│         │User Msg   │   │
│         │(Glass)    │   │
│         └───────────┘   │
│                         │
│  ┌─────────────────┐    │
│  │ AI Response     │    │
│  └─────────────────┘    │
│                         │
│  ┌─────────────────────┐│
│  │ [Input] [Send Glow] ││
│  └─────────────────────┘│
└─────────────────────────┘
```

**Components:**
- Gradient AI bubbles
- Glass user bubbles
- Typing indicator
- Floating glass input
- Glowing send button

---

### Settings Screen
```
┌─────────────────────────┐
│  [Back]  Settings       │
│                         │
│  ┌─────────────────────┐│
│  │  Profile Section    ││
│  │  - Avatar           ││
│  │  - Name/Email       ││
│  └─────────────────────┘│
│                         │
│  ┌─────────────────────┐│
│  │  Calendar Connect   ││
│  │  - Google Cal       ││
│  │  - Outlook          ││
│  └─────────────────────┘│
│                         │
│  ┌─────────────────────┐│
│  │  Preferences        ││
│  │  - Toggles          ││
│  │  - Options          ││
│  └─────────────────────┘│
│                         │
└─────────────────────────┘
```

**Components:**
- Glass section panels
- Glowing toggle switches
- Neumorphic buttons
- Smooth transitions

---

## 🎯 Implementation Checklist

### Phase 1: Design System Setup
- [x] Create color constants
- [x] Create reusable components
- [x] Set up animation controllers
- [x] Define typography scale

### Phase 2: Screen Redesign
- [ ] Login screen
- [ ] Record screen
- [ ] Meetings list (Bento grid)
- [ ] Meeting summary
- [ ] AI chat
- [ ] Settings

### Phase 3: Polish
- [ ] Add micro-animations
- [ ] Implement hover states
- [ ] Add loading states
- [ ] Test on devices
- [ ] Performance optimization

---

## 📦 File Structure

```
lib/
├── design_system/
│   ├── colors.dart
│   ├── glass_card.dart
│   ├── bento_tile.dart
│   ├── gradient_button.dart
│   ├── neumorphic_button.dart
│   ├── glow_icon.dart
│   └── assistant_message_bubble.dart
├── screens/
│   ├── login_screen.dart (redesigned)
│   ├── home_record_screen.dart (redesigned)
│   ├── meetings_list_screen.dart (redesigned)
│   ├── summary_screen.dart (redesigned)
│   ├── chat_screen.dart (redesigned)
│   └── settings_screen.dart (redesigned)
└── core/
    └── theme.dart (updated)
```

---

## 🚀 Next Steps

1. **Import design system components** into existing screens
2. **Replace old UI elements** with new components
3. **Add animations** to interactions
4. **Test on multiple devices**
5. **Gather feedback** and iterate

---

## 💡 Design Principles

1. **Clarity over Complexity** - Every element serves a purpose
2. **Consistency** - Reuse components across screens
3. **Feedback** - Visual response to every interaction
4. **Performance** - Smooth 60fps animations
5. **Accessibility** - Readable text, sufficient contrast
6. **Delight** - Subtle animations that feel premium

---

## 🎨 Inspiration References

- **Linear** - Clean, minimal, fast
- **Raycast** - Glassmorphism, smooth animations
- **Arc Browser** - Premium feel, attention to detail
- **Notion AI** - AI-native interactions
- **Apple Design** - Refined, polished

---

**Design System Version:** 1.0  
**Last Updated:** April 2026  
**Maintained by:** EchoMind Design Team

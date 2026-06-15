# MissRirica - Developer Guide

MissRirica is a mobile iOS/Android client for Misskey social network software, built with Capacitor and Vue 3. It provides almost the same UI as Misskey Web (v13) with mobile-specific optimizations and push notification support.

## Project Overview

**Type**: Hybrid Mobile App (Capacitor + Vue 3 + TypeScript)
**Version**: 1.5.3
**Target Platforms**: iOS and Android
**Base**: Misskey v13 client with mobile modifications

### Key Features
- Near-identical UI to Misskey Web (v13)
- Push notifications via OneSignal
- Native mobile app experience
- Multi-instance Misskey support
- Theme system with dark/light modes

## Common Commands

### Development
```bash
# Start development server with live reload
npm run dev

# Type checking
npm run lint

# Preview built application
npm run preview
```

### Building
```bash
# Production build
npm run build

# Development build (with debug info)
npm run devbuild
```

### Mobile Development
```bash
# Open iOS project in Xcode
npm run ios

# Open Android project in Android Studio
npm run android
```

## Architecture & Tech Stack

### Core Technologies
- **Frontend**: Vue 3.2.47 with Composition API
- **Build Tool**: Vite 4.1.1
- **Language**: TypeScript 4.9.5
- **Mobile Framework**: Capacitor 4.5.0
- **UI Components**: Custom Vue components
- **State Management**: Custom reactive store (Pizzax)
- **Routing**: Custom router (Nirax)
- **Styling**: SCSS with CSS custom properties

### Key Dependencies
- **Misskey Integration**: `misskey-js` for API communication
- **Push Notifications**: OneSignal + Capacitor Push Notifications
- **Charts**: Chart.js with various plugins
- **UI Enhancements**:
  - Canvas Confetti for animations
  - PhotoSwipe for image galleries
  - Cropper.js for image editing
  - GSAP for advanced animations
- **Text Processing**:
  - MFM (Misskey Flavored Markdown) support
  - Twemoji for emoji rendering
  - Prism.js for syntax highlighting

### Project Structure

```
src/
├── components/          # Reusable Vue components
├── pages/              # Route-based page components
├── ui/                 # UI layout components (universal, deck, classic, visitor)
├── directives/         # Custom Vue directives
├── themes/             # Theme definitions (JSON5 format)
├── locales/            # Internationalization files
├── scripts/            # Utility functions and helpers
├── widgets/            # Dashboard widgets
├── filters/            # Data transformation filters
├── types/              # TypeScript type definitions
├── assets/             # Static assets
├── account.ts          # User account management
├── store.ts            # Application state management
├── router.ts           # Application routing
├── init.ts             # Application initialization
└── style.scss          # Global styles
```

### Configuration Files

#### Capacitor Configuration
- `capacitor.config.dev.json` - Development configuration with local server
- `capacitor.config.prod.json` - Production configuration

#### Build Configuration
- `vite.config.ts` - Vite build configuration with custom aliases
- `tsconfig.json` - TypeScript configuration
- `vite.json5.ts` - Custom JSON5 plugin for theme files

#### Code Quality
- `.eslintrc.cjs` - ESLint configuration for Vue 3 + TypeScript
- No test configuration found (Cypress listed in package.json but not configured)

### Environment Variables
```bash
VITE_SERVER_PATH=https://miss-ririca.herokuapp.com/
VITE_ONE_SIGNAL_APP_ID=26c23e85-1fc8-4115-8cf3-f81338427bf3
VITE_NOTIFICATION_TOKEN_ENDPOINT=https://miss-ririca.herokuapp.com/api/setToken
```

## Key Architectural Patterns

### 1. Hybrid Mobile Architecture
- Uses Capacitor WebView for native platform integration
- Responsive design adapts to mobile viewports
- Safe area handling for iOS notch/Dynamic Island
- Platform-specific CSS classes (`ios`, `android`)

### 2. Component-Based UI
- Modular Vue 3 components with TypeScript
- Custom directive system for reusable behaviors
- Widget system for customizable dashboard

### 3. Multi-UI Support
- **Universal**: Default responsive mobile UI
- **Classic**: Traditional Misskey web layout
- **Deck**: TweetDeck-style column layout
- **Visitor**: Login/registration interface
- **Zen**: Minimal distraction-free mode

### 4. State Management
- Custom reactive store implementation (Pizzax)
- Account management with IndexedDB persistence
- Theme system with real-time switching
- Device storage for offline capabilities

### 5. Internationalization
- Multi-language support via Vue I18n
- Dynamic language detection from device
- Locale-specific formatting for dates, numbers

### 6. Push Notification System
- OneSignal integration for cross-platform notifications
- Device ID tracking for targeted notifications
- Background notification handling

## Database & Backend

### Client-Side Storage
- **IndexedDB**: Account data, offline cache
- **LocalStorage**: Preferences, temporary data
- **Device Storage**: Native mobile storage via Capacitor

### Backend Integration
- **Misskey API**: Full integration with Misskey server instances
- **WebSocket Streaming**: Real-time updates via Misskey's streaming API
- **Push Service**: Custom backend for notification token management

## Development Workflow

### Setup
1. Clone repository
2. Install dependencies: `npm install`
3. Configure environment variables in `.env`
4. Start development server: `npm run dev`

### Mobile Development
1. Build web assets: `npm run build`
2. Sync with native platforms: `npx cap sync`
3. Open native IDE: `npm run ios` or `npm run android`

### Code Quality
- ESLint for code linting
- Vue 3 recommended practices
- TypeScript strict mode enabled
- Component composition API preferred

## Important Notes

### Mobile-Specific Modifications
- The project applies patches to base Misskey code (see `patch.diff`, `mypatch.patch`)
- iOS-specific safe area handling
- Touch-optimized interactions
- Mobile viewport optimizations

### Theme System
- JSON5-based theme definitions in `src/themes/`
- Dynamic theme switching
- Dark/light mode with system sync
- Custom CSS property system

### Performance Considerations
- Lazy loading for route components
- Image optimization and caching
- Virtual scrolling for large lists
- Efficient state management

### Deployment
- Supports both development and production Capacitor configurations
- Environment-specific build processes
- App store deployment ready (iOS App Store, Google Play)

## Troubleshooting

### Common Issues
1. **Build Failures**: Check TypeScript errors with `npm run lint`
2. **Mobile Preview**: Ensure Capacitor sync is up to date
3. **Theme Loading**: Verify JSON5 syntax in theme files
4. **Push Notifications**: Confirm OneSignal configuration

### Development Tips
- Use browser dev tools with `npm run dev` for web testing
- Use native device debugging for mobile-specific features
- Check Capacitor logs for native plugin issues
- Monitor network requests for API integration problems

---

**Note**: This project is based on Misskey v13 client code with modifications for mobile app functionality. Refer to the original Misskey documentation for core concepts and API details.
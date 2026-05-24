---
layout: default
title: Privacy Policy - Toki
permalink: /privacy-en/
---

# Privacy Policy

**Last updated: May 24, 2026**
**Applies to: Toki v1.0 and later**

Toki ("the App") respects user privacy and handles your data with care.
This policy explains what data the App collects, processes, and stores,
and the purposes for which it is used.

---

## 1. About the App

Toki is a floating circle clock app for macOS that integrates with Google
Calendar to display your events on a circular clock face.

---

## 2. Data We Collect

### 2.1 Google Calendar Data

When you sign in with your Google account, the App retrieves the following
data via the Google Calendar API:

- Event titles
- Event start / end times
- Event locations
- Attendee information
- Event descriptions
- Event URLs (Google Meet / Calendar detail)

### 2.2 Authentication Information

- Google OAuth access / refresh tokens

### 2.3 App Settings

- Visual preferences (theme color, font size, opacity, etc.)
- Behavior settings (display time range, etc.)

### 2.4 Crash Reports / Diagnostics

Apple's MetricKit framework may send the following to Apple servers:

- Crash diagnostic information
- App performance metrics

These are anonymized by Apple before being provided to the developer.
No personally identifiable information is included.

---

## 3. Purposes of Data Use

| Data | Purpose |
|---|---|
| Google Calendar events | Drawing on the circle clock / showing details / opening external links (Meet / Calendar) |
| OAuth tokens | Authenticating with Google Calendar API |
| App settings | Persisting user-specified visual / behavior preferences |
| Crash reports | Improving app quality |

---

## 4. Data Storage Locations

| Data | Storage | Persistence |
|---|---|---|
| Google Calendar events | Mac memory only | Lost on app quit |
| OAuth tokens | macOS Keychain | Until app deletion / sign-out |
| App settings | macOS UserDefaults | Until app deletion |
| Crash reports | Apple servers (retained per Apple policy then deleted) | – |

---

## 5. Third-Party Sharing

The App does **not** share user data with any third party other than Apple
and Google (the API provider).

- Ad networks: not used
- Analytics tools (Google Analytics etc.): not used
- Custom servers: none

---

## 6. How to Delete Your Data

### 6.1 Local Data Deletion

- Deleting Toki from the macOS Applications folder removes data in
  UserDefaults and Keychain.

### 6.2 Revoke Google Access

- Remove Toki's access at your [Google Account permissions page](https://myaccount.google.com/permissions).

### 6.3 Stop Crash Report Sharing

- Open macOS System Settings > Privacy & Security > Analytics & Improvements
  > turn off "Share Mac Analytics" to stop sending crash reports to Apple.

---

## 7. Contact

For questions about data handling, please open a [GitHub Issue](https://github.com/NaokiOouchi/toki/issues/new/choose).

---

## 8. Revision History

- **May 24, 2026**: Initial version (released with Toki v1.0)

This policy may be revised without prior notice. Significant changes will be
announced via in-app notification or GitHub release notes.

---

<sub>[← Back to Toki home](../) / [日本語版](../privacy/)</sub>

# Floating AI Widget Integration Guide

## Overview
The floating AI widget is integrated into BitBinder using the app's existing AI services and local app persistence. Firebase is no longer part of the widget architecture.

## Current Architecture
- `FloatingAIWidgetView.swift` presents the floating chat experience.
- `ChatMessage` models widget conversation entries inside the app.
- Existing app services handle AI requests and persistence.
- Conversation history is stored with the app's local data model instead of Firebase.

## What Changed
- Removed all Firebase-specific messaging, analytics, and Realtime Database guidance.
- Removed Cloud Functions proxy assumptions from the widget setup.
- Updated the guide to reflect the current source-of-truth: in-app services and local persistence.

## Integration Notes
- Keep widget state local to the view model or shared app services.
- Persist messages using the existing SwiftData-backed models and service layer.
- Route AI requests through the app's current backend/service abstractions.
- Use app-native analytics or logging only where they already exist.

## Usage Expectations
Users can:
1. Open the floating AI widget from the main app UI.
2. Send and receive messages through the configured AI service.
3. See prior conversation state restored from app-managed persistence when supported by the current implementation.

## Maintenance Checklist
- Do not add Firebase dependencies back to the app or backend workspace.
- Prefer existing services under `thebitbinder/Services/` for any widget enhancements.
- Keep documentation aligned with the shipped implementation rather than historical experiments.

## Status
This guide has been simplified to remove outdated Firebase instructions and avoid pointing contributors toward unsupported infrastructure.

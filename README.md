# 🧐 Cyte

[![Xcode - Build and Analyze](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml/badge.svg)](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) 
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cataddict42.svg?style=social&label=%20%40CatAddict42)](https://twitter.com/cataddict42)

A background screen recorder for easy history search. There is an [optional companion app](https://github.com/shaunnarayan/cytev2-explore), which enables GPT features when running in background.

## Uses

### 🧠 Train-of-thought recovery

Autosave isn’t always an option, in those cases you can easily recover your train of thought, a screenshot to use as a stencil, or extracted copy from memories recorded.

### 🌏 Search across applications

A lot of research involves collating information from multiple sources; internal tools like confluence, websites like wikipedia, pdf and doc files etc; When searching for something we don’t always remember the source (or it's at the tip of your tongue)

## Features

> - Completely private, data is stored on disk only, no outside connections are made
> - Pause/Restart recording easily
> - Set applications that are not to be recorded (while taking keystrokes)
> - Chat your data; ask questions about work you've done

## Development

Happy to accept PRs related to any of the following

### Issues

- Searching results in some episodes without interval highlighting (Pretty sure this was due to low confidence tags being saved; pending validation)
- App sandbox is disabled to allow file tracking; [instead should request document permissions](https://stackoverflow.com/a/70972475)
- Timeline slider not updating while video playing (timeJumped notification not sent until pause)
- Thumbnails flash when regenerated (update pixel buffer only instead of tearing down each time)
- Scrolling lags while loading videos/processing vision
- Chatlog updates published var from non main actor context

### Refactor

- Extract usage and search bars to own views from ContentView
- Extract episode slider from EpisodeTimelineView into own view
- Duplicate code in vision analysis handlers and get active interval (timeline views)

### Feature requests
- Keyboard events
- Streaming responses from GPT
- Swift ReAct Agent
- Predefined blacklist
- Filter incognito and safari private windows from capture
- Chat to get video results inline
- Easily copy code blocks in chat
- Reduce color space for raw videos
- Set default playback speed 2.0
- Fallback to object recognition
- Encryption e.g. Filevault?
- Search improvement: term expansion, stemming, local embedding... 
- Audio support

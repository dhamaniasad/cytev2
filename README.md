# 🧐 Cyte

[![Xcode - Build and Analyze](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml/badge.svg)](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) 
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cataddict42.svg?style=social&label=%20%40CatAddict42)](https://twitter.com/cataddict42)

🚧 Work in progress - this is beta software, use with care

A background screen recorder for easy history search. 
If you choose to supply an OpenAI key, it can act as a knowledge base. Be aware that transcriptions will then be sent to OpenAI when you chat.

![Cyte Screenshot](assets/images/cyte.gif)

## Uses

### 🧠 Train-of-thought recovery

Autosave isn’t always an option, in those cases you can easily recover your train of thought, a screenshot to use as a stencil, or extracted copy from memories recorded.

### 🌏 Search across applications

A lot of research involves collating information from multiple sources; internal tools like confluence, websites like wikipedia, pdf and doc files etc; When searching for something we don’t always remember the source (or it's at the tip of your tongue)

## Features

> - When no OpenAI key is supplied, Cyte is completely private, data is stored on disk only, no outside connections are made
> - Pause/Restart recording easily
> - Set applications that are not to be recorded (while taking keystrokes)
> - Chat your data; ask questions about work you've done

## Development

Happy to accept PRs related to any of the following

### Issues

- App sandbox is disabled to allow file tracking; [instead should request document permissions](https://stackoverflow.com/a/70972475)
- Timeline slider not updating while video playing (timeJumped notification not sent until pause)
- Build process fails on Github (Needs signing cert installed to sign embedded content?)

### Refactor

- Extract usage and search bars to own views from ContentView
- Extract episode slider from EpisodeTimelineView into own view
- Duplicate code in vision analysis handlers and get active interval (timeline views)

### Feature requests
- Keyboard navigation events: Return to open selected episode, escape to pop timeline view
- Remove close matches from prompt context stuffer
- Incremental index building on embedding store instead of full recompile at query time
    * Ideally, wrap FAISS for swift
- Wrap tiktoken in Swift for more accurate context stuffing
- Swift ReAct Agent
- Filter incognito and safari private windows from capture
- Easily copy code blocks in chat
- Fallback to object recognition
- Encryption e.g. Filevault?


## Release Notes
### Version 0.2 (beta)
- While the application is running (but not while it is active), it records the users screen
- Recordings are labelled according to the first window bought into focus for a given app
- Save recordings as favorites and easily view them from the home screen
- Show usage statistics by application for shown recordings
- Select applications to blacklist which will prevent the application from being recorded
- Search the full text content of screenshots by keywords
- View any instant in time on a sequential timeline showing back to back recordings
- View thumbnails for moments around the current instant in timeline view
- Delete individual episodes through a context menu
- Filter search results by preset time ranges
- User supplied OpenAI key with GPT4 access allows user to ask questions in natural language
- When GPT responds, the source information provided is displayed under the response
- Use arrow keys to navigate recordings
- While Cyte is minimised, pressing Command + Period will bring Cyte into focus
- Pause/resume recording at any time using the Menu Bar icon
- Show files that have been edited with click to reopen
- Intel support with frames every 4 seconds, fast OCR path with no corrections and disabled file tracking
- Right click to reveal recordings in finder
- Right click on feed to batch delete memories
- Right click on feed to export results as timelapse
- Allow user-specified storage directory
- Automatically delete memories older than user specified length
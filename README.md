# Cyte

[![Xcode - Build and Analyze](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml/badge.svg)](https://github.com/shaunnarayan/cytev2/actions/workflows/swift-xcode.yml)

A background screen recorder for easy history search. There is an [optional companion app](https://github.com/shaunnarayan/cytev2-explore), which enables GPT features when running in background.

## Uses

### Train-of-thought recovery

Autosave isn’t always an option, in those cases you can easily recover your train of thought, a screenshot to use as a stencil, or extracted copy from memories recorded.

### Search across applications

A lot of research involves collating information from multiple sources; internal tools like confluence, websites like wikipedia, pdf and doc files etc; When searching for something we don’t always remember the source (or it's at the tip of your tongue)

## Features

> - Completely private, data is stored on disk only, no outside connections are made
> - Pause/Restart recording easily
> - Set applications that are not to be recorded (while taking keystrokes)
> - Chat your data; ask questions about work you've done

## Issues

- Searching does not show all intervals for results
- Re-enable app sandbox which is disabled to allow file tracking; instead should request document permissions: https://stackoverflow.com/a/70972475
- Timeline slider not updating while video playing (timeJumped notification not sent until pause)
- Extract usage and search bars to own views from ContentView
- Extract episode slider from EpisodeTimelineView into own view
- Windows matching Excluded bundles should be passed to exclusion list in ScreenCaptureKit
    * Maybe not though, we can't do this retrospectively for other eps so does it make sense to do it live?
- Duplicate code in vision analysis handlers and get active interval (timeline views)
- Thumbnails flash when regenerated (update pixel buffer only instead of tearing down each time)


## Feature requests

- Chat to get video results inline
- Easily copy code blocks in chat
- Reduce color space for raw videos
- Prefix episode titles with a summary of window names used in session
- Set default playback speed 2.0
- Keyword autoblacklist
- Filter incognito and chrome tabs from capture
- Investivate SQLite vs CoreData efficiency at scale
- Fallback to object recognition
- Generate and Save medium granularity features as MP4 metadata
    * Extract the main text from OCR results, embed/index it, and store the raw text as ranged meta
- Encryption e.g. Filevault?
- NL Embedding search 
- Search improvement: term expansion, stemming, verbs... 
- Audio support

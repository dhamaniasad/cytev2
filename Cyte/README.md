
## Perceive

Largely based on Apples ScreenCaptureKit sample[https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos] for Swift. Minor changes to add hooks into Retain module.

Currently supports visual context across monitors.

## Retain

DAL for CoreData model definition, plus logic to handle tracking application context, indexing, file usage and blacklisting. Largely based on Cyte V1.

## Classify

OCR followed by POS tagging for incoming frames providing compressed features for free text search.

## Support

Used for tracking global hotkey events, wrapping NSWorkspace and NSRunningApplication for bundle handling.

## Reason

Handles the intersection between indexing and querying: 
- Creates medium granularity features (OpenAI ada embeddings for documents and web content stored in FAISS index)
- Natural language knowledge base querying using GPT to reason about embedding clusters rooted around the input query

This is currently done in a support app built in Python to leverage langchain until it has more bindings.
Optional module, and the app falls back gracefully to low granularity feature search when not available.

## Views

- Heading: Search bar with foldable view for application and file filtering and screen time stacked bar chart
- Settings: List of selectable (encountered) applications to restrict recording
- Feed: Grid view of video previews for episodes with navigation to anchored Timeline
- Timeline: Scroll across episodes with a large preview

# Cyte

A background screen recorder for easy history search.

## Issues
- Bookmarking, episode closing and some other model state changes not causing the feed to update
- Instances of halting in ContentView due to episodes without start/end (maybe red herring)
- Scrolling videos fast in timeline can cause timeline to reset to reference date
- file change tracking hangs the UI
- Need to move some memory functions off the main thread
- Timeline not showing selected video on open (off by 1 on interval matching? Floating point error?)
- nil thumbnails cause rendering issues
    
## Feature requests

- Interleaved timeline view
- Highlight text results
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

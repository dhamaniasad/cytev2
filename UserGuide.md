# User guide

## Feed

- When no search terms or filters are applied, shows the last 30 days of recordings, from latest to oldest
- Each item in the grid has a full video preview player that can play, seek, and copy test
- Tapping the expand icon will take you to the timeline view, at the start of the recording
- Tapping the star icon will prevent the recording being deleted by any means until the star is tapped again
- The title of the recording is the title of the first window you opened in that application
- Right click the title to delete the memory
- Right click the tile to show the original recording file in the Finder. Do not delete/move this file from the finder, make a copy for your use.

## Search

- [Search is supported by SQLite’s FTS5.](https://github.com/shaunnarayan/cytev2/blob/main/Cyte/Retain/Memory.swift#:~:text=func%20search)
- Any search of at least 3 characters will be run as an [FTS query](https://www.sqlite.org/fts5.html#full_text_query_syntax), otherwise all results are returned. 
- To run a search, press return after typing, or tap the button
- To clear your search filters, press the refresh button
- Tap the star to show only your starred recordings


### Semantic search
- You can add one or more ‘>’ characters to the start of your search to run an [inexact search](https://github.com/shaunnarayan/cytev2/blob/main/Cyte/Retain/Memory.swift#:~:text=expanding%20+=%201). 
- Each charater adds one alternative to every [verb/noun in the search term](https://developer.apple.com/documentation/naturallanguage/identifying_parts_of_speech)
- Alternatives are picked using [word embeddings](https://developer.apple.com/documentation/naturallanguage/nlembedding)


### Advanced search

- Click the dropdown button to filter results by date range or application/website
- Tap any application/website icon or text to apply it as a filter. Tap it again to remove.
- The total time recorded for the given filters and search is displayed
- You can then tap the delete icon to batch delete all the currently displayed recordings
- You can also tap the timelapse button to generate a 1 minute timelapse from the currently displayed recordings, if the total recording time displayed is less than 40 hours. Cancel the export by tapping the stop button next to the progress bar

## Timeline

- Displays the screenshot taken closest to any time in your history
- Scroll through time by dragging the slider underneath the screenshot
- Drag right to move back in time, left to go forward
- Once you arrive at your latest/oldest recording, you cannot drag any further
- The slider visually displays segments for each application/website used, using a colored bar with icon overlay
- Below the slider, the currently shown time is on the left, with how long ago it was on the right
- If Cyte was able to detect the document/link active, there will be a button in the toolbar on the right hand side to open the file/url

## Chat

- Any query ending with a '?' is communicated to your LLM if enabled
- Add 'chat ' before your question for a private, ChatGPT-like experience (no recording data is supplied to the LLM in this mode)
- Non chat requests will supply the currently displayed results to the LLM as context. if there are too many to fit the LLM's context and provide a response, results further down in the feed are ignored
- Press return in the top left of the chat window to return to the home screen

## Settings

- You can select where Cyte stores all data (except user preferences) by tapping the folder icon
- By default, all recordings and metadata are stored in your Application Support folder
- You can select how long Cyte retains recordings before automatically deleting them. Note this feature will not delete starred recordings.
- To enable chat your data, You can either;
- - paste your OpenAI API key if you want to enable GPT4 as your LLM. Your key is stored in Apples keychain and taken out of application memory once you press return or tap the tick icon
- - Paste the full path to a llama.cpp model file on your hard drive
- Enabling browser awareness for Chrome and Safari will prevent incognito and Private browsing windows from being recorded
- Browser awareness will also attempt to track websites and divide your recordings by domain (e.g. all Twitter activity gets grouped under twitter.com)
- Tick any application/website in the disable recording section to prevent it being recorded, and also automatically delete any existing data stored for it
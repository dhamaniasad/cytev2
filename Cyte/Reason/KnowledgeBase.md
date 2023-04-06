# Tips for using Cyte as a knowledge base

To get the most out of Cyte, it's worth getting to know how search operates and some of the common limitations.

Once you have a question, perform a search as you normally would to gather information to answer your question. For example, if your question is "what did I do on my python project today", we can apply a time range filter (today), as well as app filters for those I use for work (excluding unrelated content, like spotify). Furthermore, I know I worked on two things, but I'm mainly interested in an overview for one. So, I can add a keyword search for "python", to exclude my non-python work.

Then, you can ask your question. Phrase it with the assumption that the assistant will need to answer your question given screen transcriptions, so you couldn't ask something like; "how many circles did I draw in Figma?". You also should consider if all the information needed to answer the question is actually shown in the feed (maybe you did some work on another device?)

Now, you can ask your question. In my case, I'd ask: "What have I worked on?" since the time range is implicit in the sources provided. Another consideration is, can the assistant process all the results? If there are too many results, there will be too much text for the model to fit in it's context, which is rather small: around 2-40 results depending on the model. The first results are supplied until context is full, so say you use GPT4 32k, and ask a question on 100 results, the last 60 or so will not actually be considered in the models output. 

## Time filter

Start by specifying time range best you can

## Context filter

Exclude any unrelated applications

## FTS

Normal search engine style search

## Term expansion

Uses english language word embeddings to generalize 


# Work

Supply current result set as part of query to limit query context
EITHER:
- Use top N ranked results to stuff
- Quantize results if too large to fit in context
- - First model simple decimation?
- - Next mode summarize in peices then recombine. Summarize heirachically, and embed summaries
Allow chaining results, e.g. refining results down over time to eventually execute code, with context retained over time (via summarization)
Only tool is the ability to replay user actions from a remix of time intervals (actions might be lossy compressed to relative, readable actions)
Button from timeline to results view showing the time around the playhead +- 1 episode each side

Agent needs an interface to query and dictate intervals, as part of chain. Intervals can be specific to percept, or react
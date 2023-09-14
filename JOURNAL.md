# 2023-9-14 Thu

Now that the litmus tests are all passing, I need to come up with a priority list of what needs to happen next.

Calendars and contacts are still the big goals, but I _also_ like the idea that the dav server is actually compliant; after having seen the shitshow that was the golang stdlib internals for their implementation, I really like the thought of this one being as compliant as we can be.

## open projects

### compliance

getting to full compliance will be hard; it looks like the outside world has pretty much settled on litmus being the test suite that everyone tests against, but I _know_ there are things from the specs that we're not handling:

- error responses
- lock discovery in propfind

- [ ] test suite, section by section from the RFCs?

### principals

Before I can handle calendaring, I need some concept of principals, because the caldav stuff requires the ability to look up calendar sets by the current principal.

One interesting thing is that there's no expectation of a user-visible authentication flow, which means that we can't rely on tokens/oauth/etc. for authentication, but instead need to be able to give device specific passwords, which is a whole _waves vaguely in the air_.

This is a question for @Amanda.

Additionally, we need at least some thought aroud how the circles/groups concept interacts with the RFCs per principals, and if there's anything that is going to be awkward. Not there quite yet.

- [ ] basic user management & authentication
- [ ] swag design for groups, and how that interacts with principals per RFC
- [ ] product decisions around how we want to manage device passwords

### calendars & contacts

My conception of how to manage calendars and contacts is to let the `collection` controller handle basically everything, except to have `PUT` requests _also_ throw the resouce data into an additional **indexer**, which can add properties, write to a different database table, etc.

Then, an `ical` indexer would be able to parse iCal files, keep a separate set of database tables for the events, and be able to respond to `REPORT` requests, while not having to reimplement properties or anything else that doesn't know the CalDAV server is something other than a WebDAV server.

- [ ] ical indexer
- [ ] vcard indexer

## group chat

I was thinking about our current D&D kids slack, as well as a couple of other minor hangouts I'm with, and it got me thinking about GroupMe, Signal, etc in the group chat sense, which I think would be a good fit for some of what we're thinking about.

What if, instead of going for completely tech agnostic (chat via SMS, existing stuff) you could get people to install something like GroupMe. You've got a group of pals, with chat, calendar, but then what other kind of stuff makes sense there? Is that different enough from the "hard-nosed" living together type problems I'd like to solve? Do I want to use this tool to plan Ace's birthday party? That's all happening via GroupMe anyway. Hmm...
# 2023-9-18 Mon

Took a few days off, getting back into the code review feedback I got from Super:

* general typos
  * [x] fix select list for `at_path`
  * [x] make clear `resource_reader` is not an iterator, but a rack body wrapper
  * [ ] split `properties_at` for `pid` and `rid` independence
  * [-] `each_with_object` in `properties_at` might be cleaner with a defaulted hash
    * turns out that this doesn't work; we're relying on the fact that we ceate the row
      even if the pid/rid of the property is nil; otherwise we just don't report the path
  * [x] `SQL.uuid` in grant lock
  * [-] `lock_grant` is hitting the repo's connection directly
    * I want to tackle this with the paths repo object change; fetching locks by id isn't
      really what that usage was about, more about checking tht the lock isn't shared;

* router
  * seems long; is there a better way to break it up?
  * in fact, pattern matching on the Pathname (dirname, basename) tuple might make things much clearer

* paths repo
  * length; is there value in breaking out resources/properties as their own repos?
  * use more objects, `Data.define`, and fewer magic symbol hashes
    * personally, I think switching to sequel Model objects is too heavyweight (I don't want `Paths.find()` style methods),
      but there's got to be a way to define a hash wrapper that's consistently returned by the repos

* collection controller
  * actually parse the XML, rather than doing all the path searches inline - it's pretty confusing as it stands
    * something to note; we're going to have to figure out how to handle arbitrary `REPORT` bodies, so this might be big

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

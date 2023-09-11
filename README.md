# GroupWare

A `*DAV` server, supporting:

- [x] WebDAV against a sqlite db
  - [x] core RFCs (resources, properties, locks)
  - [ ] ACLs & Users
- [ ] CalDAV
- [ ] CardDAV

# Relevant RFCs

- [x] [RFC 2518 - WebDAV (old)](http://www.webdav.org/specs/rfc2518.html)
- [x] [RFC 4918 - WebDAV (newer)](http://www.webdav.org/specs/rfc4918.html)
- [ ] [RFC 3474 - WebDAV ACLs](http://www.webdav.org/specs/rfc3744.html)
- [ ] [RFC 4791 - CalDAV over WebDAV](https://datatracker.ietf.org/doc/html/rfc4791)
- [ ] [RFC 6352 - CardDAV over WebDAV](https://datatracker.ietf.org/doc/html/rfc6352)

I do _not_ plan on supporting any of:
- [RFC 3253 - WebDAV Versioning](http://www.webdav.org/specs/rfc3253.html) not planning on supporting

# Running

* see `.env.development` for configuration
* run migrations: `bundle exec ./bin/migrate`

## `bin/server`

Starts a rackup server, and serves `Dav::Router`

* the router looks up paths in the `Repos::Paths` repository, and then forwards to the path's _controller_
* a path's _controller_ is inherited down the path tree, and allows different "types" of DAV collections
  * eg. address books and calendars
  * currently, only `collection` controller exists
* a _controller_ class exposes the HTTP methods it handles

See:
* [router.rb](./mod/dav/router.rb)
* [collection.rb](./mod/dav/controllers/collection.rb)

## `bin/console`

Starts an IRB console, with the system finalized.

`main#get` is a shortcut for `System::Container.[]`, eg:

```ruby
paths = get("repos.paths")
paths.at_path("/testpath")
```

## `bin/sqlite`, `bin/migrate`

Because we use a customized database connection, we can't use the built-in
`sequel` CLI for migrations, or the `sqlite3` cli for running SQL.

These tools run migrations and a database console in the context of the
customized connection.

In these tools, the following SQL functions are available:

* `uuid()`
* `escape_url()`
* `unescape_url()`

# Technical

`System::Container` is a dependency injection root for the whole system, built
on top of the excellent [dry-system](https://dry-rb.org/gems/dry-system) gem.

An application starts by calling `System::Container.finalize!`, which auto-registers
components in the `mod` directory, making them available via the container.

Auto-registered components get their dependencies automatically filled, making the
resulting object graph pretty straightforward.

# Integration Tests

Currently, we're testing against the [WebDAV.org Litmus Compliance Suite](http://www.webdav.org/neon/litmus/).

1. download the source code [litmus-0.13.tar.gz](http://www.webdav.org/neon/litmus)
1. extract it somewhere
1. run `./configure`
1. run `make URL="http://localhost:5000" check` to run tests

# License

Copyright 2023 Jon Raphaelson, Accidental.cc LLC
This is proprietary, for the time being.

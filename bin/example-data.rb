#!/usr/bin/env ruby

require_relative '../system/app'
App::Container.finalize!

uuid = Sequel.function(:uuid)
repo = App::Container['db.resource_repo']

fam = repo.resources.insert_select(id: uuid, path: "wolfsont-raphaelson")
repo.resources.insert(id: uuid, pid: fam[:id], path: "jon")
repo.resources.insert(id: uuid, pid: fam[:id], path: "sarah")
repo.resources.insert(id: uuid, pid: fam[:id], path: "ezra")

mir = repo.resources.insert_select(id: uuid, pid: fam[:id], path: "mirah")
repo.resources.insert(id: uuid, pid: mir[:id], path: "teddy")
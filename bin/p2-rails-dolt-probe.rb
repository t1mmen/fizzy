#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage:
#   bin/rails runner bin/p2-rails-dolt-probe.rb
#
# Purpose (P2): Prove the Rails process can reach Beads by connecting directly
# to the local Dolt SQL server using the same `trilogy` adapter Rails uses for
# MySQL (SQL-based data path candidate for Q-S-001).

require "active_record"

beads_port_path = Rails.root.join(".beads", "dolt-server.port")
port = Integer(File.read(beads_port_path).strip)

class BeadsDolt < ActiveRecord::Base
  self.abstract_class = true
end

BeadsDolt.establish_connection(
  adapter: "trilogy",
  host: "127.0.0.1",
  port: port,
  username: "root",
  database: "fizzy",
  pool: 1,
)

issues_count = BeadsDolt.connection.select_value("select count(*) from issues")
sample = BeadsDolt.connection.select_rows("select id, title, status, priority from issues order by updated_at desc limit 5")

puts "OK: connected to Dolt SQL server (trilogy) at 127.0.0.1:#{port}/fizzy"
puts "OK: issues.count=#{issues_count}"
puts "Sample (most recently updated):"
sample.each_with_index do |row, idx|
  id, title, status, priority = row
  puts "  #{idx + 1}. #{id} [#{status} P#{priority}] — #{title}"
end


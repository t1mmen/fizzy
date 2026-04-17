#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage:
#   bin/rails runner bin/p2-rails-bd-probe.rb
#
# Purpose (P2): Prove the Rails process can reach Beads by shelling out to `bd`
# and parsing the result (CLI-based data path candidate for Q-S-001).

require "json"
require "open3"

def run!(argv)
  stdout, stderr, status = Open3.capture3(*argv)
  unless status.success?
    raise "command failed (#{status.exitstatus}): #{argv.join(" ")}\n#{stderr}"
  end
  stdout
end

context_json = run!(%w[bd context --json])
context = JSON.parse(context_json)

export_jsonl = run!(%w[bd export --no-memories])
lines = export_jsonl.lines.map(&:strip).reject(&:empty?)
issues = lines.map { |l| JSON.parse(l) }

puts "OK: bd context backend=#{context.fetch("backend")} dolt_mode=#{context.fetch("dolt_mode")} host=#{context.fetch("server_host")} port=#{context.fetch("server_port")} db=#{context.fetch("database")}"
puts "OK: bd export issues=#{issues.size}"

issues.first(5).each_with_index do |issue, idx|
  puts "  #{idx + 1}. #{issue.fetch("id")} — #{issue.fetch("title")}"
end


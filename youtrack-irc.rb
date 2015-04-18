#!/usr/bin/env ruby
require "cinch"
require "cinch/plugins/identify"
require "youtrack"
require "yaml"
require "json"

$conf = YAML.load_file("config.yml")

client = Youtrack::Client.new do |c|
	c.url = $conf["youtrack"]["url"]
	c.login = $conf["youtrack"]["user"]
	c.password = $conf["youtrack"]["password"]

	# c.debug = true
end

client.connect!

$project = client.projects
$issue = client.issues

def field(issue, name)
	field = issue["field"].find { |f| f["name"] == name }
	return "" if field.nil?
	field["value"]
end

def get_url(issue)
	$conf["youtrack"]["url"] + "issue/#{issue["id"]}"
end

def get_comment_url(issue, comment)
	get_url(issue) + "#comment=#{comment["id"]}"
end

def get_issue(id)
	$issues_cache[id]
end

$cc = 3.chr
$pink = $cc + "13"
$grey = $cc + "15"
$blue = $cc + "12"

def format_new_issue(issue)
	description = field issue, "description"
	description = description.split("\n")[0..1].map { |l| l[0..400] }.join("\n")
	description += " #{$grey}[truncated]#{$cc}" if description != field(issue, "description")
	return "[#{$pink + issue["id"] + $cc}] #{field issue, "summary"}
Subsystem: #{$grey + field(issue, "Subsystem")[0] + $cc} Reporter: #{ $grey + field(issue, "reporterName") + $cc} URL: #{ $blue + get_url(issue) + $cc}
#{description}"
end

def format_new_comment(issue, comment)
	text = comment["text"]
	text = text.split("\n")[0..1].map { |l| l[0..400] }.join("\n")
	text += " #{$grey}[truncated]#{$cc}" if text != comment["text"]
	return "New comment by #{ $grey + comment["author"] + $cc} on #{ $pink + issue["id"] + $cc}: #{field issue, "summary"}
#{ $blue + get_comment_url(issue, comment) + $cc}
#{text}"
end

def get_issues_for(project_name)
	raw_issues = $project.get_issues_for(project_name, max:99999)

	$issues_cache = {}
	raw_issues.each { |i| $issues_cache[i["id"]] = i }
end

def get_issues_hash
	Hash[
		$conf["projects"].map do |project_name|
			[project_name, get_issues_for(project_name).map { |issue| issue["id"] }]
		end
	]
end

def get_comments_hash(issues_hash)
	hash = {}
	issues_hash.each do |_, issues|
		issues.each do |id|
			hash[id] = get_issue(id)["comment"]
		end
	end
	hash
end

$seen_comments = []
$issues_cache = {}
$old_issues = get_issues_hash
$old_comments = get_comments_hash($old_issues)
def poll_messages
	messages = []

	issues = get_issues_hash
	issues.each do |project, issues|
		new_issues = issues - $old_issues[project]
		new_issues.each{ |id| messages << format_new_issue(get_issue(id)) }
	end
	
	comments = get_comments_hash(issues)
	comments.each do |id, comments|

		old_comments = $old_comments[id]

		next if old_comments.nil?

		new_comments = comments - old_comments
		new_comments.each { |comment| messages << format_new_comment(get_issue(id), comment) unless $seen_comments.include?(comment["id"])}

		comments.each do |comment|
			$seen_comments << comment["id"] unless $seen_comments.include?(comment["id"])
		end
	end
	
	$old_issues = issues
	$old_comments = comments

	messages
end

# loop do
# 	poll_messages.each { |msg| puts msg }
# 	sleep 10
# end

bot = Cinch::Bot.new do
	configure do |c|
		c.server = $conf["irc"]["server"]
		c.port = $conf["irc"]["port"] || 6667
		
		c.nick = $conf["irc"]["nick"]
		c.user = c.nick
		c.channels = $conf["irc"]["channels"]

		c.realname = "Youtrack-IRC"

		if $conf["irc"]["nickserv"]
			c.plugins.plugins << Cinch::Plugins::Identify
			c.plugins.options[Cinch::Plugins::Identify] = {
				username: $conf["irc"]["nickserv"]["username"],
				password: $conf["irc"]["nickserv"]["password"],
				type: :nickserv
			}
		end
	end

	on :connect do
		loop do
			messages = poll_messages
			messages.each do |message|
				$conf["irc"]["channels"].each do |channel|
					Channel(channel).send(message)
				end
				sleep 1
			end
			sleep 10
		end
	end

	on :identified do
		$conf["irc"]["channels"].each do |channel|
			bot.join channel
		end
	end
end

bot.start

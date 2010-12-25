#!/usr/bin/env ruby

require "rubygems"
require "eventmachine"
require "em-mongo"
require "em-http-request"
require "json"
require "ap"

url = "https://stream.twitter.com/1/statuses/filter.json"

user = ARGV[0]
pass = ARGV[1]

EventMachine.run do
  http = EventMachine::HttpRequest.new(url)
  mongodb = EventMachine::Mongo::Connection.new("localhost")

  tweetdb = mongodb.db("tweets").collection
  urldb = mongodb.db("urls").collection

  keywords = [ "http", "https" ]
  #keywords = [ "soccer" ]
  req = http.post :body => { "track" => keywords.join(",") },
                  :head => { "Authorization" => [ user, pass ] }

  buffer = BufferedTokenizer.new
  count = 0
  bytes = 0
  start = Time.now
  req.stream do |chunk|
    buffer.extract(chunk).each do |line|
      tweet = JSON.parse(line)
      count += 1
      bytes += line.size
      if count % 100 == 0
        duration = Time.now - start
        ap :tweet_rate => (count / duration), :byte_rate => (bytes / duration)
      end

      tweetdb.insert(tweet)
      urls = tweet["entities"]["urls"] rescue []

      urls.each do |urlent|
        urldb.update({ "url" => urlent["url"] },
                     { "$inc" => { "hits" => 1 } },
                     { :upsert => true })
      end

      puts tweet["id_str"]
    end # buffer.extract
  end # req.stream

  req.callback {
    $stderr.puts http.response_header.awesome_inspect
    #EventMachine.stop_event_loop
  }

  req.errback do
    $stderr.puts "Error."
    EventMachine.stop_event_loop
  end
end # EventMachine.run


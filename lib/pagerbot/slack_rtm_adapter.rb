require 'json'
require 'sinatra/base'
require 'slack-ruby-client'

module PagerBot
  class SlackRTMAdapter
    include SemanticLogger::Loggable

    def self.run!
      PagerBot::SlackRTMAdapter.new().run!
    end

    def initialize
      # Load slack API token
      Slack.configure do |config|
        config.token = configatron.bot.slack.api_token
      end
      @client = Slack::RealTime::Client.new
      @user_cache = {}
    end

    def run!
      @client.on :message do |data|
        if data.type == 'message' && data.subtype == 'message_changed'
          process_message data.message, data.channel
        elsif data.type == 'message' && data.subtype.nil?
          process_message data, data.channel
        end
      end
      @client.start!
    end

    def find_user(user_id)
      @user_cache[user_id] ||= @client.users.fetch(user_id)
      @user_cache[user_id]
    end

    def process_message(message, channel)
      # Ignore messages from bots and self.
      return if message.subtype == 'bot_message'
      return if message.user == @client.self.id

      extra_data = {
        nick: find_user(message.user).name,
        adapter: :slack
      }

      usernames = [@client.self.name, "<@#{@client.self.id}>"]
      # In direct messages, don't require the bot name.
      if channel.start_with? 'D'
        usernames.push nil
      end

      text = PagerBot::Parsing.strip_names message.text, usernames
      return if text.nil? # Not addressed to this user.

      logger.info "Received a query.", nick: usernames, query: text
      response = PagerBot.process text, extra_data
      if response[:private_message]
        dm_channel = "@#{find_user(message.user).name}"
        send_message response.fetch(:private_message), dm_channel
      else
        send_message response.fetch(:message), channel
      end
    end

    def send_message(message, channel)
      logger.info "Responding.", channel: channel, text: message
      @client.web_client.chat_postMessage channel: channel, text: message, as_user: true, unfurl_links: false
    end
  end
end

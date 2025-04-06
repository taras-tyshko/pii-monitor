# Quick Start Guide for PII Monitor

## Setting up API Keys

To make the application work, you need to configure API keys in the `.env` file:

1. **Slack API Token**:
   - Go to [Slack API](https://api.slack.com/apps)
   - Create a new app (or use an existing one)
   - Add the following permissions (oauth scopes):
     - `channels:history` - for reading message history
     - `channels:read` - for accessing channel lists
     - `chat:write` - for sending messages
     - `im:write` - for sending private messages
     - `users:read` - for getting user information
     - `chat:write.customize` - for extended interaction capabilities
     - `channels:write` - for deleting messages (required for full functionality)
     - `groups:write` - for working with private channels (if needed)
   - Install the app to your workspace
   - Copy the "Bot User OAuth Token" to `.env` as `SLACK_API_TOKEN`
   - **IMPORTANT**: add the bot as an administrator to the channels it monitors, otherwise message deletion won't work

2. **Notion API Key**:
   - Go to [Notion Developers](https://www.notion.so/my-integrations)
   - Create a new integration
   - Copy the "Internal Integration Token" to `.env` as `NOTION_API_KEY`
   - In Notion, connect this integration to the databases you want to monitor:
     - Open the database
     - Click "Share" (top right corner)
     - In the "Connections" section, add your integration
   - Add the database ID to `.env` as `NOTION_MONITORED_DATABASES` (comma-separated)

3. **OpenAI API Key**:
   - Go to [OpenAI API](https://platform.openai.com/api-keys)
   - Create a new API key
   - Copy it to `.env` as `OPENAI_API_KEY`
   - Make sure your account has sufficient quota or add payment information

## Starting the Application

After setting up all the keys:

1. Make sure you have Elixir and Phoenix installed
2. Install dependencies: `mix deps.get`
3. Start the application: `./start.sh`

## Testing Functionality

1. **Slack Test**:
   - Send a message with PII to the monitored channels (e.g., "My email is test@example.com")
   - The message should be deleted, and you'll receive a DM with a warning
   - **Note**: for message deletion, the bot must have administrative privileges in the channel

2. **Notion Test**:
   - Add a page with PII to the monitored database
   - The page should be archived, and you'll receive a DM in Slack
   - Make sure the integration has access to the database via "Share" → "Connections"

## Common Errors and Solutions

1. **cant_delete_message**:
   - **Problem**: The bot cannot delete messages in the channel
   - **Solution**: 
     - Add the `channels:write` and `chat:write.customize` permissions to the bot
     - Make the bot an administrator of the channel
     - Or change the bot's logic to not delete messages, but only mark them

2. **not_in_channel**:
   - **Problem**: The bot does not have access to the channel
   - **Solution**: Add the bot to the channel with the `/invite @bot_name` command

3. **OpenAI API error "insufficient_quota"**:
   - **Problem**: Insufficient quota for using the OpenAI API
   - **Solution**: Add payment information to your OpenAI account or use a different API key

4. **Notion API errors**:
   - **Problem**: The integration does not have access to the database
   - **Solution**: Check that the integration is added to Connections in Notion

## Changing Monitoring Logic

If you want to change how the system responds to PII detection:

1. For **Slack**: modify `lib/pii_monitor/slack_client.ex`
2. For **Notion**: modify `lib/pii_monitor/notion_client.ex`
3. For **PII analysis**: modify `lib/pii_monitor/pii_analyzer.ex` 
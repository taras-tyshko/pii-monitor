# PII Monitor

Application for monitoring personal identifiable information (PII) in Slack messages and Notion pages.

## Description

PII Monitor automatically scans specified Slack channels and Notion databases for personal identifiable information (PII). If PII is detected, the application:

1. Deletes the message/page with PII
2. Sends a private message (DM) to the author with the content of the deleted message/page and a request to send it again without PII

The application analyzes:
- Text content of messages and pages
- Images
- PDF files
- Other attachments

## Installation

### Prerequisites

- Elixir 1.14 or newer
- Phoenix 1.7.20 or newer
- Access to Slack API with permissions to read messages and delete them
- Access to Notion API with permissions to read and modify pages
- Access to OpenAI API for content analysis

### Setting up environment variables

Create a `.env` file in the root directory of the project with the following variables:

```
# Slack API token (with permissions for reading messages, deletion, etc.)
SLACK_API_TOKEN=xoxb-your-slack-token

# Slack channels for monitoring (comma-separated)
SLACK_MONITORED_CHANNELS=general,random,support

# Notion API key
NOTION_API_KEY=secret_your_notion_key

# Notion database IDs for monitoring (comma-separated)
NOTION_MONITORED_DATABASES=db1,db2,db3

# OpenAI API key for PII analysis
OPENAI_API_KEY=sk-your-openai-key

# Monitoring interval in milliseconds (default 1000)
MONITORING_INTERVAL_MS=1000
```

### Installing dependencies and running

```bash
# Installing dependencies
mix deps.get

# Compilation
mix compile

# Running in development mode
mix phx.server

# OR running in interactive mode
iex -S mix phx.server
```

## Testing

To verify the application's operation:

1. **Slack Test:**
   - Send a message with personal data (e.g., phone number or email) to one of the monitored channels
   - Make sure the message is deleted, and you received a DM with a warning
   - Send a message without PII and make sure it remains in the channel

2. **Notion Test:**
   - Create a page with PII in a monitored database
   - Make sure the page is archived, and you received a DM in Slack
   - Create a page without PII and make sure it remains in the database

## Architecture

The application is built using Elixir/Phoenix and consists of the following components:

- **PiiMonitor.Monitoring** - the main GenServer that coordinates monitoring
- **PiiMonitor.SlackClient** - module for interacting with Slack API
- **PiiMonitor.NotionClient** - module for interacting with Notion API
- **PiiMonitor.PiiAnalyzer** - module for analyzing content for PII using OpenAI

## Libraries Used

Main project dependencies:
- **HTTPoison** - HTTP client for API interaction
- **Poison** - JSON parser for working with API responses
- **Phoenix** - web application framework

## Developer Settings

- Change the monitoring interval in config/config.exs
- Configure the list of channels and databases in the configuration or through environment variables
- If necessary, change the PII detection logic in the PiiAnalyzer module

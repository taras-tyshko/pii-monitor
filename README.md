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

## Developer Settings

- Change the monitoring interval in config/config.exs
- Configure the list of channels and databases in the configuration or through environment variables
- If necessary, change the PII detection logic in the PiiAnalyzer module

## Code Quality and Security

### Credo

The project uses [Credo](https://github.com/rrrene/credo) for static code analysis to maintain code quality. Credo checks for style consistency, code smells, and other issues.

To run code analysis:

```bash
# Run standard code analysis
mix lint

# Run analysis with suggestions for improvements
mix lint.fix
```

Key improvements implemented with Credo:
- Enhanced code readability by formatting large numbers (e.g., 10_000 instead of 10000)
- Alphabetized module aliases 
- Removed debug IO.inspect calls
- Optimized code by replacing Enum.map |> Enum.join with Enum.map_join
- Standardized code style throughout the project

### Sobelow

For security analysis, the project employs [Sobelow](https://github.com/nccgroup/sobelow), a security-focused static analysis tool for Phoenix applications.

To run security analysis:

```bash
# Run security check
mix security.scan 
```

Security improvements implemented:
- Added Content-Security-Policy headers to the browser pipeline
- Configured HTTPS enforcement in production using force_ssl
- Implemented secure file handling to prevent directory traversal attacks:
  - Added path validation for file operations (read, write, delete)
  - Restricted file operations to temporary directories only
  - Created dedicated secure functions for file management

## Deployment

### Deploying to Fly.io

The application is configured for easy deployment to [Fly.io](https://fly.io/) using GitHub Actions:

1. **Prerequisites**:
   - GitHub repository with this code
   - Fly.io account
   - Fly CLI installed locally for initial setup

2. **Initial setup**:
   ```bash
   # Login to Fly.io
   fly auth login
   
   # Create a new Fly.io app (only once)
   fly launch --no-deploy
   ```

3. **Setting up secrets**:
   Store sensitive information using Fly.io secrets:
   ```bash
   fly secrets set SLACK_API_TOKEN=your_slack_token
   fly secrets set NOTION_API_KEY=your_notion_key
   fly secrets set OPENAI_API_KEY=your_openai_key
   fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
   ```

4. **GitHub Actions integration**:
   - Create a Fly.io API token:
     ```bash
     fly auth token
     ```
   - Add the token to your GitHub repository secrets as `FLY_API_TOKEN`
   
5. **Deployment**:
   - Automatic deployment will occur when changes are pushed to the `master` branch
   - Manual deployment can be triggered through GitHub Actions interface

### Configuration

The deployment configuration is defined in two files:
- `fly.toml` - Fly.io configuration including regions, resources, and environment variables
- `.github/workflows/fly.yml` - GitHub Actions workflow that runs tests and deploys the application

## Libraries Used

Main project dependencies:
- **HTTPoison** - HTTP client for API interaction
- **Poison** - JSON parser for working with API responses
- **Phoenix** - web application framework

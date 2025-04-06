defmodule PiiMonitor.SlackClient do
  @moduledoc """
  Module for interacting with Slack API.
  Provides functions for retrieving messages, deleting messages, and sending DMs to users.
  """

  require Logger
  alias PiiMonitor.PiiAnalyzer

  @slack_api_base "https://slack.com/api"

  @doc """
  Gets a list of messages from a channel for a specific period.
  """
  def get_channel_messages(channel_id, oldest \\ nil) do
    params = %{
      channel: channel_id,
      limit: 100
    }

    params = if oldest, do: Map.put(params, :oldest, oldest), else: params

    case call_slack_api("conversations.history", params) do
      {:ok, %{"ok" => true, "messages" => messages}} ->
        {:ok, messages}

      {:ok, %{"ok" => false, "error" => error}} ->
        Logger.error("Slack API error when retrieving messages: #{error}")
        {:error, error}

      {:error, error} ->
        Logger.error("Error when retrieving messages from Slack: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Deletes a message from a channel.
  """
  def delete_message(channel_id, ts) do
    params = %{
      channel: channel_id,
      ts: ts
    }

    case call_slack_api("chat.delete", params) do
      {:ok, %{"ok" => true}} ->
        Logger.info("Message successfully deleted from channel #{channel_id}, ts: #{ts}")
        :ok

      {:ok, %{"ok" => false, "error" => error}} ->
        Logger.error("Slack API error when deleting message: #{error}")
        {:error, error}

      {:error, error} ->
        Logger.error("Error when deleting message: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Sends a DM to a user.
  """
  def send_dm(user_id, text) do
    # First open an IM channel with the user
    case call_slack_api("conversations.open", %{users: user_id}) do
      {:ok, %{"ok" => true, "channel" => %{"id" => channel_id}}} ->
        # Send the message
        case call_slack_api("chat.postMessage", %{
               channel: channel_id,
               text: text,
               as_user: true
             }) do
          {:ok, %{"ok" => true}} ->
            Logger.info("DM successfully sent to user #{user_id}")
            :ok

          {:ok, %{"ok" => false, "error" => error}} ->
            Logger.error("Slack API error when sending DM: #{error}")
            {:error, error}

          {:error, error} ->
            Logger.error("Error when sending DM: #{inspect(error)}")
            {:error, error}
        end

      {:ok, %{"ok" => false, "error" => error}} ->
        Logger.error("Slack API error when opening IM channel: #{error}")
        {:error, error}

      {:error, error} ->
        Logger.error("Error when opening IM channel: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Downloads a file from URL.
  """
  def download_file(url) do
    token = Application.get_env(:pii_monitor, :slack_api_token, System.get_env("SLACK_API_TOKEN"))

    headers = [{"Authorization", "Bearer #{token}"}]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Error when downloading file: status #{status_code}")
        {:error, "HTTP error: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error when downloading file: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Find user by email.
  """
  def find_user_by_email(email) do
    case call_slack_api("users.list", %{}) do
      {:ok, %{"ok" => true, "members" => members}} ->
        user =
          Enum.find(members, fn member ->
            get_in(member, ["profile", "email"]) == email
          end)

        if user do
          {:ok, user}
        else
          {:error, :user_not_found}
        end

      {:ok, %{"ok" => false, "error" => error}} ->
        Logger.error("Slack API error when getting user list: #{error}")
        {:error, error}

      {:error, error} ->
        Logger.error("Error when searching for user by email: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Checks a message for PII and takes necessary actions if PII is found.
  """
  def process_message(channel_id, message) do
    has_pii = false

    # Check message text
    has_pii =
      if Map.has_key?(message, "text") && message["text"] != "" do
        case PiiAnalyzer.analyze_text(message["text"]) do
          {:ok, true} -> true
          _ -> has_pii
        end
      else
        has_pii
      end

    # Check files in the message
    has_pii =
      if !has_pii && Map.has_key?(message, "files") && length(message["files"]) > 0 do
        Enum.reduce_while(message["files"], has_pii, fn file, acc ->
          file_has_pii = check_file_for_pii(file)
          if file_has_pii, do: {:halt, true}, else: {:cont, acc}
        end)
      else
        has_pii
      end

    # If PII is found, delete the message and send a DM
    if has_pii do
      with :ok <- delete_message(channel_id, message["ts"]),
           :ok <- notify_user_about_pii_message(message) do
        {:ok, :message_processed}
      else
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, :no_pii_found}
    end
  end

  @doc """
  Makes API request to Slack.
  """
  def call_slack_api(method, params) do
    token = Application.get_env(:pii_monitor, :slack_api_token, System.get_env("SLACK_API_TOKEN"))
    url = "#{@slack_api_base}/#{method}"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json; charset=utf-8"}
    ]

    case HTTPoison.post(url, Poison.encode!(params), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Poison.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Slack API error: status #{status_code}, body: #{body}")
        {:error, "API error: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Checks a file for PII
  defp check_file_for_pii(file) do
    file_type = Map.get(file, "filetype", "")

    cond do
      Enum.member?(["jpg", "jpeg", "png", "gif"], file_type) ->
        # Check image
        case PiiAnalyzer.analyze_image(file["url_private"]) do
          {:ok, has_pii} -> has_pii
          _ -> false
        end

      file_type == "pdf" ->
        # Download and check PDF
        with {:ok, file_content} <- download_file(file["url_private"]),
             {:ok, temp_path} <- write_temp_file(file_content, "pdf"),
             {:ok, has_pii} <- PiiAnalyzer.analyze_pdf(temp_path) do
          # Delete temporary file
          delete_temp_file(temp_path)
          has_pii
        else
          _ -> false
        end

      true ->
        # For other file types, just check the name
        case PiiAnalyzer.analyze_text(file["name"]) do
          {:ok, has_pii} -> has_pii
          _ -> false
        end
    end
  end

  # Writes data to a temporary file
  defp write_temp_file(content, extension) do
    # Generate a secure random filename in the temp directory
    temp_dir = System.tmp_dir!()
    # Sanitize the extension to prevent command injection
    safe_extension = extension |> String.replace(~r/[^a-zA-Z0-9]/, "")
    # Use secure randomization for filename
    random_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    filename = "pii_monitor_#{random_id}.#{safe_extension}"
    temp_path = Path.join(temp_dir, filename)

    # Additional security checks
    canonical_temp_path = Path.expand(temp_path)
    canonical_temp_dir = Path.expand(temp_dir)

    # Ensure the path is still in the temp directory (prevent path traversal)
    if Path.dirname(canonical_temp_path) != canonical_temp_dir do
      Logger.error("Path traversal attempt detected: #{temp_path}")
      {:error, :invalid_path}
    else
      # Use binary mode to ensure consistent file handling
      file_mode = [:write, :binary]

      case File.open(temp_path, file_mode) do
        {:ok, file} ->
          try do
            case IO.binwrite(file, content) do
              :ok -> {:ok, temp_path}
              {:error, reason} -> {:error, reason}
            end
          after
            File.close(file)
          end

        {:error, reason} ->
          Logger.error("Could not open file for writing: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Safely delete a temporary file
  defp delete_temp_file(temp_path) when is_binary(temp_path) do
    # Ensure the file is in the temp directory
    temp_dir = System.tmp_dir!()
    # Canonicalize paths before comparison
    canonical_temp_path = Path.expand(temp_path)
    canonical_temp_dir = Path.expand(temp_dir)

    if String.starts_with?(canonical_temp_path, canonical_temp_dir) and
         Path.dirname(canonical_temp_path) == canonical_temp_dir do
      # Verify file exists before attempting to delete
      case File.stat(temp_path) do
        {:ok, %{type: :regular}} ->
          # Only delete regular files, not directories or other special files
          File.rm(temp_path)

        {:ok, _} ->
          Logger.error("Not a regular file, will not delete: #{temp_path}")
          {:error, :not_regular_file}

        {:error, reason} ->
          Logger.error("Error accessing file to delete: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Attempted to delete file outside of temp directory: #{temp_path}")
      {:error, :invalid_path}
    end
  end

  # Sends a message to the user about a deleted message with PII
  defp notify_user_about_pii_message(message) do
    user_id = message["user"]

    text = """
    Hello! I detected that your message contains personal identifiable information (PII).
    This message has been automatically deleted to protect confidentiality.

    Here is the content of your message:
    ```
    #{message["text"]}
    ```

    Please send the message again, but without personal data.
    """

    send_dm(user_id, text)
  end
end

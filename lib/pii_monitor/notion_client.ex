defmodule PiiMonitor.NotionClient do
  @moduledoc """
  Module for interacting with Notion API.
  Provides functions for retrieving records from databases, deleting records, and getting user data.
  """

  require Logger
  alias PiiMonitor.PiiAnalyzer
  alias PiiMonitor.SlackClient

  @notion_api_base "https://api.notion.com/v1"
  @notion_version "2022-06-28"

  @doc """
  Gets a list of records from the database for a specified time period.
  """
  def get_database_entries(database_id, since \\ nil) do
    # Configure time filter if specified
    filter =
      if since do
        timestamp = DateTime.to_iso8601(since)

        %{
          timestamp: "last_edited_time",
          last_edited_time: %{
            on_or_after: timestamp
          }
        }
      else
        nil
      end

    # Create request parameters
    params = %{
      page_size: 100
    }

    # Add filter if it exists
    params = if filter, do: Map.put(params, :filter, filter), else: params

    # Execute request to Notion API
    case call_notion_api("databases/#{database_id}/query", params, :post) do
      {:ok, %{"results" => results}} ->
        {:ok, results}

      {:error, error} ->
        Logger.error("Error getting records from Notion database: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Deletes a page from the database (archives it).
  """
  def delete_page(page_id) do
    # In Notion there is no direct deletion, but we can mark the page as archived
    case call_notion_api("pages/#{page_id}", %{archived: true}, :patch) do
      {:ok, _response} ->
        Logger.info("Page successfully archived in Notion: #{page_id}")
        :ok

      {:error, error} ->
        Logger.error("Error archiving page in Notion: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Gets information about the user who created the page.
  """
  def get_page_creator(page) do
    # In Notion API, there may not be direct access to the creator,
    # but we can get it from last_edited_by or created_by
    creator = Map.get(page, "created_by") || Map.get(page, "last_edited_by")

    if creator do
      {:ok, creator}
    else
      # If we couldn't get information about the author
      {:error, :creator_not_found}
    end
  end

  @doc """
  Gets page content.
  """
  def get_page_content(page_id) do
    case call_notion_api("blocks/#{page_id}/children", %{page_size: 100}, :get) do
      {:ok, %{"results" => blocks}} ->
        content = extract_text_from_blocks(blocks)
        {:ok, content}

      {:error, error} ->
        Logger.error("Error getting Notion page content: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Analyzes a page for PII and processes it if PII is detected.
  """
  def process_page(page) do
    # Getting page content
    {:ok, content} =
      case get_page_content(page["id"]) do
        {:ok, content} -> {:ok, content}
        # If an error occurred, consider the content empty
        _ -> {:ok, ""}
      end

    # Extract page properties (title, fields, etc.)
    properties = Map.get(page, "properties", %{})
    properties_text = extract_text_from_properties(properties)

    # Combine everything for checking
    full_content = content <> "\n" <> properties_text

    # Check for PII
    has_pii =
      case PiiAnalyzer.analyze_text(full_content) do
        {:ok, true} -> true
        _ -> false
      end

    # If there is PII, delete the page and send a message to the author
    if has_pii do
      with {:ok, email} <- get_user_email_from_page(page),
           :ok <- delete_page(page["id"]) do
        # Try to find Slack user by email
        case SlackClient.find_user_by_email(email) do
          {:ok, slack_user} ->
            # If Slack user is found, send them a message
            notify_user_about_pii_page(
              slack_user["id"],
              page["title"] || "Untitled",
              full_content
            )

          {:error, _reason} ->
            # If Slack user is not found, log a message
            Logger.warning("Could not find Slack user with email #{email} | Message not sent.")
        end

        {:ok, :page_processed}
      else
        {:error, reason} ->
          Logger.error("Error processing page with PII: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:ok, :no_pii_found}
    end
  end

  # Gets the email of a Notion user from page properties
  def get_user_email_from_page(page) do
    # Перевіряємо properties у сторінці
    case page["properties"] do
      properties when is_map(properties) ->
        # Спочатку перевіряємо наявність created_by властивості
        created_by_email = find_email_in_property(properties["Created by"])

        # Якщо не знайшли, перевіряємо last_edited_by
        last_edited_email = find_email_in_property(properties["Last edited by"])

        # Повертаємо перший знайдений варіант
        cond do
          created_by_email ->
            Logger.info("Found email in created_by property: #{created_by_email}")
            {:ok, created_by_email}

          last_edited_email ->
            Logger.info("Found email in last_edited_by property: #{last_edited_email}")
            {:ok, last_edited_email}

          true ->
            # Якщо нічого не знайшли, використовуємо існуючу логіку
            get_user_from_metadata(page)
        end

      _ ->
        # Якщо properties немає або це не мапа, використовуємо існуючу логіку
        get_user_from_metadata(page)
    end
  end

  # Витягує email з властивості сторінки
  defp find_email_in_property(property) do
    cond do
      # Якщо це поле Created by
      property && property["type"] == "created_by" && property["created_by"] ->
        get_in(property, ["created_by", "person", "email"])

      # Якщо це поле Last edited by
      property && property["type"] == "last_edited_by" && property["last_edited_by"] ->
        get_in(property, ["last_edited_by", "person", "email"])

      true ->
        nil
    end
  end

  # Використовуємо метадані сторінки якщо властивості не містять email
  defp get_user_from_metadata(page) do
    # Спочатку перевіряємо created_by
    if page["created_by"] do
      get_user_email(page["created_by"])
      # Потім перевіряємо last_edited_by
    else
      if page["last_edited_by"] do
        get_user_email(page["last_edited_by"])
      else
        {:error, :email_not_found}
      end
    end
  end

  # Gets the email of a Notion user
  defp get_user_email(user) do
    # If there is a user ID, try to get their email
    if user && Map.has_key?(user, "id") do
      user_id = user["id"]

      # Since we can't get email directly through the API, use a fixed email
      # This can be replaced with a real integration with your user accounting system
      email = user_id <> "@notion.users"

      Logger.info("Got Notion user ID: #{user_id}, using email: #{email}")

      {:ok, email}
    else
      Logger.error("Unable to get user ID from object: #{inspect(user)}")
      {:error, :email_not_found}
    end
  end

  # Extracts text from Notion page blocks
  defp extract_text_from_blocks(blocks) do
    Enum.reduce(blocks, "", fn block, acc ->
      block_text =
        case block["type"] do
          "paragraph" ->
            get_in(block, ["paragraph", "rich_text"]) |> get_rich_text()

          "heading_1" ->
            get_in(block, ["heading_1", "rich_text"]) |> get_rich_text()

          "heading_2" ->
            get_in(block, ["heading_2", "rich_text"]) |> get_rich_text()

          "heading_3" ->
            get_in(block, ["heading_3", "rich_text"]) |> get_rich_text()

          "bulleted_list_item" ->
            get_in(block, ["bulleted_list_item", "rich_text"]) |> get_rich_text()

          "numbered_list_item" ->
            get_in(block, ["numbered_list_item", "rich_text"]) |> get_rich_text()

          "to_do" ->
            get_in(block, ["to_do", "rich_text"]) |> get_rich_text()

          "toggle" ->
            get_in(block, ["toggle", "rich_text"]) |> get_rich_text()

          "code" ->
            get_in(block, ["code", "rich_text"]) |> get_rich_text()

          "quote" ->
            get_in(block, ["quote", "rich_text"]) |> get_rich_text()

          "callout" ->
            get_in(block, ["callout", "rich_text"]) |> get_rich_text()

          _ ->
            ""
        end

      acc <> block_text <> "\n"
    end)
  end

  # Gets text from Notion rich_text object
  defp get_rich_text(rich_text) when is_list(rich_text) do
    Enum.reduce(rich_text, "", fn text_item, acc ->
      acc <> Map.get(text_item, "plain_text", "")
    end)
  end

  defp get_rich_text(_), do: ""

  # Extracts text from page properties
  defp extract_text_from_properties(properties) do
    Enum.reduce(properties, "", fn {key, property}, acc ->
      property_text =
        case property["type"] do
          "title" ->
            get_rich_text(get_in(property, ["title"]))

          "rich_text" ->
            get_rich_text(get_in(property, ["rich_text"]))

          "number" ->
            to_string(property["number"] || "")

          "select" ->
            get_in(property, ["select", "name"]) || ""

          "multi_select" ->
            (property["multi_select"] || [])
            |> Enum.map_join(", ", &Map.get(&1, "name", ""))

          "date" ->
            start_date = get_in(property, ["date", "start"]) || ""
            end_date = get_in(property, ["date", "end"]) || ""
            [start_date, end_date] |> Enum.reject(&(&1 == "")) |> Enum.join(" - ")

          "people" ->
            (property["people"] || [])
            |> Enum.map_join(", ", &Map.get(&1, "name", ""))

          "checkbox" ->
            if property["checkbox"], do: "Yes", else: "No"

          "url" ->
            property["url"] || ""

          "email" ->
            property["email"] || ""

          "phone_number" ->
            property["phone_number"] || ""

          _ ->
            ""
        end

      acc <> key <> ": " <> property_text <> "\n"
    end)
  end

  # Sends a message to the user about a deleted page with PII
  defp notify_user_about_pii_page(user_id, page_title, content) do
    text = """
    Hello! I detected that your page "#{page_title}" in Notion contains personal identifiable information (PII).
    This page has been automatically archived to protect confidentiality.

    Here is the content of your page:
    ```
    #{content}
    ```

    Please create the page again, but without personal data.
    """

    case SlackClient.send_dm(user_id, text) do
      :ok ->
        Logger.info("Message about Notion page archiving successfully sent to user #{user_id}")

        :ok

      {:error, reason} ->
        Logger.error("Error sending message about Notion page archiving: #{inspect(reason)}")

        {:error, reason}
    end
  end

  # Makes request to Notion API
  defp call_notion_api(endpoint, params, method) do
    api_key = Application.get_env(:pii_monitor, :notion_api_key, System.get_env("NOTION_API_KEY"))
    url = "#{@notion_api_base}/#{endpoint}"

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Notion-Version", @notion_version},
      {"Content-Type", "application/json"}
    ]

    request =
      case method do
        :get ->
          query = URI.encode_query(params)
          url_with_query = if query != "", do: "#{url}?#{query}", else: url
          HTTPoison.get(url_with_query, headers)

        :post ->
          HTTPoison.post(url, Poison.encode!(params), headers)

        :patch ->
          HTTPoison.patch(url, Poison.encode!(params), headers)
      end

    case request do
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}}
      when status_code in 200..299 ->
        {:ok, Poison.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Notion API error: status #{status_code}, body: #{body}")
        {:error, "API error: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

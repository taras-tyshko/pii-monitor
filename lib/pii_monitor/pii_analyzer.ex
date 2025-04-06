defmodule PiiMonitor.PiiAnalyzer do
  @moduledoc """
  Module for analyzing content for personal identifiable information (PII).
  Uses HTTP requests to external API for analysis.
  """

  require Logger

  @openai_api_url "https://api.openai.com/v1/chat/completions"

  @doc """
  Analyzes text content for PII.
  Returns `{:ok, true}` if PII is found, `{:ok, false}` if not found,
  or `{:error, reason}` in case of an error.
  """
  def analyze_text(text) when is_binary(text) do
    prompt = """
    Analyze the following text for personal identifiable information (PII), such as:
    - Full names
    - Email addresses
    - Phone numbers
    - Home addresses
    - Bank card numbers
    - Passport numbers
    - Social security numbers
    - Birth dates
    - ID numbers (driver's licenses, etc.)
    - Other confidential information that can identify a person

    Text for analysis:
    #{text}

    Your response should be only "true" if PII is found or "false" if PII is not found.
    """

    body = %{
      model: "gpt-3.5-turbo",
      messages: [
        %{
          role: "system",
          content:
            "You are an analyst looking for personal identifiable information (PII) in text."
        },
        %{role: "user", content: prompt}
      ],
      temperature: 0.0
    }

    case make_openai_request(body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => "true"}} | _]}} ->
        {:ok, true}

      {:ok, %{"choices" => [%{"message" => %{"content" => "false"}} | _]}} ->
        {:ok, false}

      {:ok, %{"choices" => [%{"message" => %{"content" => response}} | _]}} ->
        # Handling ambiguous response
        cond do
          String.downcase(response) =~ "true" ->
            {:ok, true}

          String.downcase(response) =~ "false" ->
            {:ok, false}

          true ->
            Logger.warning("Ambiguous response from API: #{response}")
            # To be safe, consider that PII is present
            {:ok, true}
        end

      {:error, error} ->
        Logger.error("Error when analyzing PII: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Analyzes images for PII.
  """
  def analyze_image(image_url) when is_binary(image_url) do
    prompt = """
    Analyze this image for any personal identifiable information (PII), such as:
    - Full names
    - Email addresses
    - Phone numbers
    - Home addresses
    - Bank card numbers
    - Passport numbers
    - Social security numbers
    - Birth dates
    - ID numbers (driver's licenses, etc.)
    - Other confidential information that can identify a person

    Your response should be only "true" if PII is found or "false" if PII is not found.
    """

    body = %{
      model: "gpt-4-vision-preview",
      messages: [
        %{
          role: "system",
          content:
            "You are an analyst looking for personal identifiable information (PII) in images."
        },
        %{
          role: "user",
          content: [
            %{type: "text", text: prompt},
            %{type: "image_url", image_url: %{url: image_url}}
          ]
        }
      ],
      temperature: 0.0
    }

    case make_openai_request(body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => "true"}} | _]}} ->
        {:ok, true}

      {:ok, %{"choices" => [%{"message" => %{"content" => "false"}} | _]}} ->
        {:ok, false}

      {:ok, %{"choices" => [%{"message" => %{"content" => response}} | _]}} ->
        # Handling ambiguous response
        cond do
          String.downcase(response) =~ "true" ->
            {:ok, true}

          String.downcase(response) =~ "false" ->
            {:ok, false}

          true ->
            Logger.warning("Ambiguous response from API for image: #{response}")
            # To be safe, consider that PII is present
            {:ok, true}
        end

      {:error, error} ->
        Logger.error("Error when analyzing PII in image: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Analyzes PDF documents for PII.
  In this implementation we use a simple approach - extract text from first few pages
  """
  def analyze_pdf(pdf_path) when is_binary(pdf_path) do
    # Validate the file path is in the allowed directory (temp directory)
    temp_dir = System.tmp_dir!()
    # Canonicalize paths before comparison to prevent directory traversal
    canonical_pdf_path = Path.expand(pdf_path)
    canonical_temp_dir = Path.expand(temp_dir)

    if String.starts_with?(canonical_pdf_path, canonical_temp_dir) and
       Path.dirname(canonical_pdf_path) == canonical_temp_dir do
      # Verify the file exists and is readable before attempting to read it
      case File.stat(pdf_path) do
        {:ok, %{access: access}} when access in [:read, :read_write] ->
          # Use a more secure file reading approach with explicit path validation
          read_and_analyze_pdf(pdf_path)

        {:ok, _} ->
          Logger.error("Cannot read PDF file: #{pdf_path} - insufficient permissions")
          {:error, :insufficient_permissions}

        {:error, reason} ->
          Logger.error("Error accessing PDF file: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.error("Invalid file path: #{pdf_path} - not in temp directory")
      {:error, :invalid_path}
    end
  end

  # Private function to safely read and analyze PDF content
  defp read_and_analyze_pdf(pdf_path) do
    case File.read(pdf_path) do
      {:ok, content} ->
        # Use limited amount of text to avoid issues with large files
        analyze_text(String.slice(content, 0, 10_000))

      {:error, reason} ->
        Logger.error("Error when reading PDF file: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Makes request to OpenAI API
  defp make_openai_request(body) do
    api_key = Application.get_env(:pii_monitor, :openai_api_key, System.get_env("OPENAI_API_KEY"))

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post(@openai_api_url, Poison.encode!(body), headers,
           timeout: 30_000,
           recv_timeout: 30_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Poison.decode!(response_body)}

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("OpenAI API error: status #{status_code}, body: #{response_body}")
        {:error, "API error: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

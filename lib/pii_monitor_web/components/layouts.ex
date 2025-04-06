defmodule PiiMonitorWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  For simplicity, we're using plain text output now.
  """

  def render("root.html", assigns) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <title>PII Monitor</title>
      </head>
      <body>
        #{assigns[:inner_content] || "PII Monitor Content"}
      </body>
    </html>
    """
  end
end

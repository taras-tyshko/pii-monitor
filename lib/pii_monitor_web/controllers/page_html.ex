defmodule PiiMonitorWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use Phoenix.Controller

  # Simple text-based render function
  def render(_, _) do
    "PII Monitor - Welcome"
  end
end

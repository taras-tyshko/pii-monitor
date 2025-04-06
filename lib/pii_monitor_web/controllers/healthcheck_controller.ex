defmodule PiiMonitorWeb.HealthcheckController do
  use PiiMonitorWeb, :controller

  @doc """
  Simple healthcheck endpoint that returns 200 OK with status information.
  Used for monitoring and health checks by deployment platforms.
  """
  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      service: "pii_monitor",
      version: Application.spec(:pii_monitor, :vsn),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end
end

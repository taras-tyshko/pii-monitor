defmodule PiiMonitor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PiiMonitorWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:pii_monitor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PiiMonitor.PubSub},
      # Start Finch HTTP client for API requests
      {Finch, name: PiiMonitor.Finch},
      # Start our PII Monitoring service
      PiiMonitor.Monitoring,
      # Start to serve requests, typically the last entry
      PiiMonitorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PiiMonitor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PiiMonitorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

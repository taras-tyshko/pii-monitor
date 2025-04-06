defmodule PiiMonitorWeb.Router do
  use PiiMonitorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {PiiMonitorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers,
      %{
        "content-security-policy" => "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-src 'self'; object-src 'none'; base-uri 'self'"
      }
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PiiMonitorWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", PiiMonitorWeb do
  #   pipe_through :api
  # end
end

defmodule PiiMonitorWeb.HealthcheckControllerTest do
  use PiiMonitorWeb.ConnCase

  test "GET /api/healthcheck", %{conn: conn} do
    conn = get(conn, ~p"/api/healthcheck")

    assert json_response(conn, 200)["status"] == "ok"
    assert json_response(conn, 200)["service"] == "pii_monitor"
    assert json_response(conn, 200)["version"]
    assert json_response(conn, 200)["timestamp"]
  end
end

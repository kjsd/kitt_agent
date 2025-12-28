defmodule KittAgentWeb.FallbackController do
  use KittAgentWeb, :controller

  require Logger

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: KittAgentWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, nil), do: call(conn, {:error, :not_found})

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: KittAgentWeb.ErrorJSON)
    |> render(:"400")
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: KittAgentWeb.ErrorJSON)
    |> render(:"403")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: KittAgentWeb.ErrorJSON)
    |> render(:"401")
  end

  def call(conn, {:error, :unprocessable_entity}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: KittAgentWeb.ErrorJSON)
    |> render(:"422")
  end

  def call(conn, {:error, :invalid_format}),
    do: call(conn, {:error, :unprocessable_entity})

  def call(conn, {:error, %Ecto.Changeset{} = c} = e) do
    e |> inspect |> Logger.error()

    conn
    |> put_status(:unprocessable_entity)
    |> put_view(KittAgentWeb.ErrorJSON)
    |> render(:"422", changeset: c)
  end

  def call(conn, {:error, e}) do
    e |> inspect |> Logger.error()

    conn
    |> put_status(:internal_server_error)
    |> put_view(json: KittAgentWeb.ErrorJSON)
    |> render(:"500")
  end
end

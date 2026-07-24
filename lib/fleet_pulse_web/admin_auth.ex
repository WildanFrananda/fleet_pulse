defmodule FleetPulseWeb.AdminAuth do
  @moduledoc """
  Plugs and a LiveView `on_mount` hook that gate the dispatch console.

  The signed session cookie carries only the admin id. It cannot be forged,
  but there is no server-side session store, so a session lives until its
  cookie expires and cannot be revoked remotely. Acceptable for an internal
  console; revisit if remote logout is ever needed.
  """

  use FleetPulseWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias FleetPulse.Accounts
  alias FleetPulse.Accounts.Admin
  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  @session_key "admin_id"

  @spec log_in_admin(Plug.Conn.t(), Admin.t()) :: Plug.Conn.t()
  def log_in_admin(conn, %Admin{} = admin) do
    conn
    |> renew_session()
    |> put_session(@session_key, admin.id)
    |> redirect(to: ~p"/dispatch")
  end

  @spec log_out_admin(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out_admin(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  @spec fetch_current_admin(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_admin(conn, _opts) do
    assign(conn, :current_admin, load_admin(get_session(conn, @session_key)))
  end

  @spec require_authenticated_admin(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_authenticated_admin(conn, _opts) do
    gate(conn.assigns[:current_admin], conn)
  end

  @spec on_mount(:ensure_authenticated, map(), map(), Socket.t()) :: {:cont | :halt, Socket.t()}
  def on_mount(:ensure_authenticated, _params, session, socket) do
    mount_gate(load_admin(session[@session_key]), socket)
  end

  @spec load_admin(term()) :: Admin.t() | nil
  defp load_admin(admin_id) when is_integer(admin_id) and admin_id > 0 do
    case Accounts.get_admin(admin_id) do
      {:ok, admin} -> admin
      {:error, :not_found} -> nil
    end
  end

  defp load_admin(_other), do: nil

  @spec gate(Admin.t() | nil, Plug.Conn.t()) :: Plug.Conn.t()
  defp gate(%Admin{}, conn), do: conn

  defp gate(nil, conn) do
    conn
    |> put_flash(:error, "You must log in to access the dispatch console.")
    |> redirect(to: ~p"/admin/log_in")
    |> halt()
  end

  @spec mount_gate(Admin.t() | nil, Socket.t()) :: {:cont | :halt, Socket.t()}
  defp mount_gate(%Admin{} = admin, socket) do
    {:cont, Component.assign(socket, :current_admin, admin)}
  end

  defp mount_gate(nil, socket) do
    {:halt,
     socket
     |> LiveView.put_flash(:error, "You must log in to access the dispatch console.")
     |> LiveView.redirect(to: ~p"/admin/log_in")}
  end

  @spec renew_session(Plug.Conn.t()) :: Plug.Conn.t()
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end

defmodule KittAgentWeb.HomeLive do
  use KittAgentWeb, :live_view

  def mount(_params, _session, socket) do
    # ダミーデータの作成
    users = [
      %{
        id: 1,
        name: "Hart Hagerty",
        email: "hart@example.com",
        role: "Desktop Support Technician",
        status: "Active",
        last_login: "2023-10-01",
        avatar_url: "https://img.daisyui.com/images/profile/demo/2@94.webp"
      },
      %{
        id: 2,
        name: "Brice Swyre",
        email: "brice@example.com",
        role: "Tax Accountant",
        status: "Offline",
        last_login: "2023-09-28",
        avatar_url: "https://img.daisyui.com/images/profile/demo/3@94.webp"
      },
      %{
        id: 3,
        name: "Marjy Ferencz",
        email: "marjy@example.com",
        role: "Office Assistant",
        status: "Active",
        last_login: "2023-10-02",
        avatar_url: "https://img.daisyui.com/images/profile/demo/4@94.webp"
      }
    ]

    {:ok, assign(socket, users: users)}
  end
end

defmodule KittAgentWeb.KittLiveTest do
  use KittAgentWeb.ConnCase

  import Phoenix.LiveViewTest
  alias KittAgent.Kitts

  @create_attrs %{
    "name" => "some name",
    "model" => "some model",
    "vendor" => "some vendor",
    "birthday" => "2023-01-01",
    "hometown" => "some hometown",
    "biography" => %{"personality" => "some personality"}
  }
  @update_attrs %{
    "name" => "some updated name",
    "model" => "some updated model",
    "vendor" => "some updated vendor",
    "birthday" => "2023-01-02",
    "hometown" => "some updated hometown",
    "biography" => %{"personality" => "some updated personality"}
  }

  defp create_kitt(_) do
    {:ok, kitt} = Kitts.create_kitt(@create_attrs)
    %{kitt: kitt}
  end

  describe "Index" do
    setup [:create_kitt]

    test "lists all kitts", %{conn: conn, kitt: kitt} do
      {:ok, _index_live, html} = live(conn, ~p"/kitt-web/kitts")

      assert html =~ "Listing Kitts"
      assert html =~ kitt.name
    end

    test "saves new kitt", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/kitt-web/kitts")

      assert index_live |> element("a", "New Kitt") |> render_click() =~
               "New Kitt"

      assert_patch(index_live, ~p"/kitt-web/kitts/new")

      assert index_live
             |> form("#kitt-form", kitt: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/kitt-web/kitts")

      html = render(index_live)
      assert html =~ "Kitt created successfully"
      assert html =~ "some name"
    end

    test "updates kitt in listing", %{conn: conn, kitt: kitt} do
      {:ok, index_live, _html} = live(conn, ~p"/kitt-web/kitts")

      assert index_live |> element("#kitts-#{kitt.id} a", "Edit") |> render_click() =~
               "Edit Kitt"

      assert_patch(index_live, ~p"/kitt-web/kitts/#{kitt}/edit")

      assert index_live
             |> form("#kitt-form", kitt: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/kitt-web/kitts")

      html = render(index_live)
      assert html =~ "Kitt updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes kitt in listing", %{conn: conn, kitt: kitt} do
      {:ok, index_live, _html} = live(conn, ~p"/kitt-web/kitts")

      assert index_live |> element("#kitts-#{kitt.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#kitts-#{kitt.id}")
    end
  end
end

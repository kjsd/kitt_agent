defmodule KittAgentWeb.KittLive.FormComponent do
  use KittAgentWeb, :live_component

  alias KittAgent.Kitts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage kitt records.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="kitt-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:model]} type="text" label="Model" />
        <.input field={@form[:vendor]} type="text" label="Vendor" />
        <.input field={@form[:birthday]} type="date" label="Birthday" />
        <.input field={@form[:hometown]} type="text" label="Hometown" />
        <.input
          field={@form[:lang]}
          type="select"
          label="Lang"
          options={@languages}
        />
        <.input
          field={@form[:timezone]}
          type="select"
          label="Timezone"
          options={@timezones}
        />

        <div>
          <label class="block text-sm font-semibold leading-6 text-zinc-800">Voice Sample</label>
          <div class="mt-2 flex items-center gap-4">
            <%= if @kitt.audio_path do %>
              <audio controls src={@kitt.audio_path} class="h-8">
                Your browser does not support the audio element.
              </audio>
            <% end %>
            <.live_file_input upload={@uploads.audio} />
          </div>
          <%= for entry <- @uploads.audio.entries do %>
            <article class="mt-2 text-sm text-zinc-500">
              <progress value={entry.progress} max="100">{entry.progress}%</progress>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                phx-target={@myself}
              >
                &times;
              </button>
            </article>
          <% end %>
        </div>

        <.inputs_for :let={bio_form} field={@form[:biography]}>
          <.input field={bio_form[:personality]} type="textarea" label="Personality" />
        </.inputs_for>

        <:actions>
          <.button phx-disable-with="Saving...">Save Kitt</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{kitt: kitt} = assigns, socket) do
    changeset = Kitts.change_kitt(kitt)
    timezones = Tzdata.zone_list()

    languages = [
      "Arabic",
      "Chinese",
      "Dutch",
      "English",
      "French",
      "German",
      "Hindi",
      "Indonesian",
      "Italian",
      "Japanese",
      "Korean",
      "Portuguese",
      "Russian",
      "Spanish",
      "Swahili",
      "Thai",
      "Turkish",
      "Vietnamese"
    ]

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:timezones, timezones)
     |> assign(:languages, languages)
     |> allow_upload(:audio, accept: ~w(.mp3 .wav .m4a .ogg), max_entries: 1)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"kitt" => kitt_params}, socket) do
    changeset =
      socket.assigns.kitt
      |> Kitts.change_kitt(kitt_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  def handle_event("save", %{"kitt" => kitt_params}, socket) do
    save_kitt(socket, socket.assigns.action, kitt_params)
  end

  defp save_kitt(socket, :edit, kitt_params) do
    kitt_params = put_audio_path(socket, kitt_params)

    case Kitts.update(socket.assigns.kitt, kitt_params) do
      {:ok, kitt} ->
        notify_parent({:saved, kitt})

        {:noreply,
         socket
         |> put_flash(:info, "Kitt updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_kitt(socket, :new, kitt_params) do
    kitt_params = put_audio_path(socket, kitt_params)

    case Kitts.create_kitt(kitt_params) do
      {:ok, kitt} ->
        notify_parent({:saved, kitt})

        {:noreply,
         socket
         |> put_flash(:info, "Kitt created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp put_audio_path(socket, kitt_params) do
    {completed, []} = uploaded_entries(socket, :audio)

    case completed do
      [entry | _] ->
        ext = Path.extname(entry.client_name)
        filename = "#{Ecto.UUID.generate()}#{ext}"
        dest = Path.join("/app/uploads", filename)

        consume_uploaded_entries(socket, :audio, fn %{path: path}, _entry ->
          File.cp!(path, dest)
          {:ok, ~p"/uploads/#{filename}"}
        end)
        |> case do
          [url | _] -> Map.put(kitt_params, "audio_path", url)
          [] -> kitt_params
        end

      [] ->
        kitt_params
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end

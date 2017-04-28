defmodule RemoteRetro.RetroChannel do
  use RemoteRetro.Web, :channel

  alias RemoteRetro.{Presence, PresenceUtils, Idea, Emails, Mailer, Retro}
  alias Phoenix.Socket

  def join("retro:" <> retro_id, _, socket) do
    socket = Socket.assign(socket, :retro_id, retro_id)

    send self(), :after_join
    {:ok, socket}
  end

  def handle_info(:after_join, %{assigns: assigns} = socket) do
    PresenceUtils.track_timestamped(socket)

    retro = Repo.get!(Retro, assigns.retro_id) |> Repo.preload(:ideas)
    push socket, "retro_state", retro
    {:noreply, socket}
  end

  def handle_in("enable_edit_state", %{"id" => id}, socket) do
    broadcast! socket, "enable_edit_state", %{"id" => id}
    {:noreply, socket}
  end

  def handle_in("disable_edit_state", %{"id" => id}, socket) do
    broadcast! socket, "disable_edit_state", %{"id" => id}
    {:noreply, socket}
  end

  def handle_in("idea_live_edit", %{"id" => id, "liveEditText" => live_edit_text}, socket) do
    broadcast! socket, "idea_live_edit", %{"id" => id, "liveEditText" => live_edit_text}
    {:noreply, socket}
  end

  def handle_in("idea_edited", %{"id" => id, "body" => body}, socket) do
    idea =
      Repo.get(Idea, id)
      |> Idea.changeset(%{body: body})
      |> Repo.update!

    broadcast! socket, "idea_edited", idea
    {:noreply, socket}
  end

  def handle_in("delete_idea", id, socket) do
    idea = Repo.delete!(%Idea{id: id})

    broadcast! socket, "idea_deleted", idea
    {:noreply, socket}
  end

  def handle_in("proceed_to_next_stage", %{"stage" => "action-item-distribution"}, socket) do
    retro_id = socket.assigns.retro_id
    persist_retro_update!(retro_id, "action-item-distribution")
    Emails.action_items_email(retro_id) |> Mailer.deliver_now

    broadcast! socket, "proceed_to_next_stage", %{"stage" => "action-item-distribution"}
    {:noreply, socket}
  end

  def handle_in("proceed_to_next_stage", %{"stage" => stage}, socket) do
    persist_retro_update!(socket.assigns.retro_id, stage)

    broadcast! socket, "proceed_to_next_stage", %{"stage" => stage}
    {:noreply, socket}
  end

  intercept ["presence_diff"]
  def handle_out("presence_diff", _msg, socket) do
    new_state = Presence.list(socket) |> PresenceUtils.give_facilitator_role_to_longest_tenured

    push socket, "presence_state", new_state
    {:noreply, socket}
  end

  defp persist_retro_update!(retro_id, stage) do
    Repo.get(Retro, retro_id)
    |> Retro.changeset(%{stage: stage})
    |> Repo.update!
  end
end

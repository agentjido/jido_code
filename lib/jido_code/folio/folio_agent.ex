defmodule JidoCode.Folio.FolioAgent do
  @moduledoc """
  GTD (Getting Things Done) task manager agent using Jido.AI.Agent.

  Captures thoughts to inbox, clarifies them into actions or projects,
  and helps manage next actions and waiting-for lists.
  """

  use Jido.AI.Agent,
    name: "folio_agent",
    description: "GTD task manager - capture, clarify, organize, engage",
    tools: [
      # Inbox
      JidoCode.Folio.InboxItem.Jido.Capture,
      JidoCode.Folio.InboxItem.Jido.ProcessToAction,
      JidoCode.Folio.InboxItem.Jido.ProcessToProject,
      JidoCode.Folio.InboxItem.Jido.Discard,
      JidoCode.Folio.InboxItem.Jido.Inbox,
      # Actions
      JidoCode.Folio.Action.Jido.Create,
      JidoCode.Folio.Action.Jido.Read,
      JidoCode.Folio.Action.Jido.Complete,
      JidoCode.Folio.Action.Jido.MarkWaiting,
      JidoCode.Folio.Action.Jido.DeferSomeday,
      JidoCode.Folio.Action.Jido.MakeNext,
      JidoCode.Folio.Action.Jido.AddSubAction,
      JidoCode.Folio.Action.Jido.Next,
      JidoCode.Folio.Action.Jido.WaitingFor,
      # Projects
      JidoCode.Folio.Project.Jido.Create,
      JidoCode.Folio.Project.Jido.Read,
      JidoCode.Folio.Project.Jido.MarkDone,
      JidoCode.Folio.Project.Jido.DeferSomeday,
      JidoCode.Folio.Project.Jido.Active
    ],
    tool_context: %{
      domain: JidoCode.Folio,
      actor: %{id: "system", role: :user}
    },
    model: "anthropic:claude-haiku-4-5",
    max_iterations: 8,
    system_prompt: """
    You are a GTD (Getting Things Done) task manager assistant.

    ## GTD Workflow
    1. **Capture** - Brain dump everything into inbox
    2. **Clarify** - Process inbox: actionable? → action/project, not? → discard
    3. **Organize** - Assign to projects, set waiting/someday status
    4. **Engage** - Work from next actions list

    ## Tools Available

    ### Inbox (Capture & Clarify)
    - `capture_thought` - Quick capture anything to inbox
    - `list_inbox` - Show unprocessed inbox items
    - `clarify_to_action` - Turn inbox item into a next action
    - `clarify_to_project` - Turn inbox item into a project
    - `discard_thought` - Remove non-actionable item

    ### Actions (Organize & Engage)
    - `create_action` - Create a next action directly
    - `add_sub_action` - Create sub-task under an action
    - `complete_action` - Mark action done
    - `mark_waiting_for` - Waiting on someone/something
    - `defer_action` - Move to someday/maybe
    - `activate_action` - Promote back to next action
    - `get_next_actions` - What can I do right now?
    - `get_waiting_for` - What am I waiting on?

    ### Projects
    - `create_project` - Multi-step outcome
    - `complete_project` - Mark project done
    - `defer_project` - Move to someday
    - `get_active_projects` - Current commitments

    ## Behavior
    - When user brain dumps multiple items, capture each separately to inbox
    - Ask clarifying questions if intent is unclear
    - Suggest next actions when creating projects
    - Default to capturing to inbox if unsure whether something is an action or project
    """
end

# Phase 4: TUI Tab Integration

This phase integrates the TermUI Tabs widget into the JidoCode TUI, enabling users to view and switch between multiple sessions. Each tab displays a session's conversation with Ctrl+1 through Ctrl+0 keyboard shortcuts for navigation.

---

## 4.1 Model Structure Updates

Update the TUI Model to support multiple sessions with tab-based navigation.

### 4.1.1 Model Struct Changes
- [x] **Task 4.1.1** (completed 2025-12-06)

Restructure the Model to support multiple sessions.

- [x] 4.1.1.1 Add session tracking fields to Model struct:
  ```elixir
  defstruct [
    # Session management
    sessions: %{},           # session_id => Session.t()
    session_order: [],       # List of session_ids in tab order
    active_session_id: nil,  # Currently focused session

    # Existing shared fields
    window: {80, 24},
    text_input: nil,
    show_reasoning: false,
    focus: :input,           # :tabs | :conversation | :input
    agent_status: :idle,

    # Modals (shared across sessions)
    shell_dialog: nil,
    pick_list: nil,

    # Remove per-session fields from Model (now in Session.State)
    # messages: [],          # REMOVED
    # reasoning_steps: [],   # REMOVED
    # tool_calls: [],        # REMOVED
    # streaming_message: nil # REMOVED
  ]
  ```
- [x] 4.1.1.2 Update `@type model()` typespec
- [x] 4.1.1.3 Add `@type focus()` for focus states
- [x] 4.1.1.4 Write unit tests for model structure (13 tests, 0 failures)

### 4.1.2 Session State Access
- [x] **Task 4.1.2** (completed 2025-12-06)

Add helper functions for accessing active session state.

- [x] 4.1.2.1 Implement `get_active_session/1`:
  ```elixir
  def get_active_session(model) do
    case model.active_session_id do
      nil -> nil
      id -> Map.get(model.sessions, id)
    end
  end
  ```
- [x] 4.1.2.2 Implement `get_active_session_state/1` fetching from Session.State:
  ```elixir
  def get_active_session_state(model) do
    case model.active_session_id do
      nil -> nil
      id -> Session.State.get_state(id)
    end
  end
  ```
- [x] 4.1.2.3 Implement `get_session_by_index/2` for tab number lookup
- [x] 4.1.2.4 Write unit tests for session access helpers (13 new tests, 26 total)

### 4.1.3 Session Order Management
- [x] **Task 4.1.3** (completed 2025-12-15)

Implement functions for managing session tab order.

- [x] 4.1.3.1 Implement `add_session_to_tabs/2`:
  ```elixir
  def add_session_to_tabs(model, session) do
    %{model |
      sessions: Map.put(model.sessions, session.id, session),
      session_order: model.session_order ++ [session.id],
      active_session_id: model.active_session_id || session.id
    }
  end
  ```
- [x] 4.1.3.2 Implement `remove_session_from_tabs/2`
- [x] 4.1.3.3 Handle active session removal (switch to adjacent tab)
- [ ] 4.1.3.4 Implement `reorder_sessions/2` for drag-drop (future)
- [x] 4.1.3.5 Write unit tests for tab management

**Unit Tests for Section 4.1:**
- Test Model struct has session tracking fields
- Test `get_active_session/1` returns current session
- Test `get_active_session_state/1` fetches from Session.State
- Test `add_session_to_tabs/2` adds session correctly
- Test `add_session_to_tabs/2` sets active if first session
- Test `remove_session_from_tabs/2` removes session
- Test removing active session switches to adjacent tab

---

## 4.2 Init and PubSub Updates

Update initialization and PubSub subscriptions for multi-session.

### 4.2.1 Init Updates
- [x] **Task 4.2.1** (completed 2025-12-15)

Update `init/1` for multi-session model.

- [x] 4.2.1.1 Load existing sessions from SessionRegistry:
  ```elixir
  def init(_opts) do
    sessions = load_sessions_from_registry()
    session_order = Enum.map(sessions, & &1.id)
    active_id = List.first(session_order)

    subscribe_to_all_sessions(sessions)

    %Model{
      sessions: Map.new(sessions, &{&1.id, &1}),
      session_order: session_order,
      active_session_id: active_id,
      # ... other fields
    }
  end
  ```
- [x] 4.2.1.2 Subscribe to PubSub topics for all sessions
- [x] 4.2.1.3 Handle case with no sessions (active_session_id set to nil)
- [x] 4.2.1.4 Write unit tests for init (12 tests, 0 failures)

### 4.2.2 PubSub Subscription Management
- [x] **Task 4.2.2** (completed 2025-12-15)

Implement dynamic PubSub subscription for sessions.

- [x] 4.2.2.1 Implement `subscribe_to_session/1`:
  ```elixir
  def subscribe_to_session(session_id) do
    topic = PubSubTopics.llm_stream(session_id)
    Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
  end
  ```
- [x] 4.2.2.2 Implement `unsubscribe_from_session/1`
- [x] 4.2.2.3 Subscribe when session added
- [x] 4.2.2.4 Unsubscribe when session removed
- [x] 4.2.2.5 Write unit tests for subscription management (6 tests, 0 failures)

### 4.2.3 Message Routing
- [x] **Task 4.2.3** (completed 2025-12-15)

Update message routing to identify source session.

- [x] 4.2.3.1 Update PubSub message format to include session_id:
  ```elixir
  # Messages now include session_id
  {:stream_chunk, session_id, chunk}
  {:stream_end, session_id, content}
  {:tool_call, session_id, name, args, id}
  ```
- [x] 4.2.3.2 Update `update/2` handlers to extract session_id
- [x] 4.2.3.3 MessageHandlers accept session_id (routing to Session.State is future work)
- [x] 4.2.3.4 Update tests for new message format (3 tests fixed)

**Unit Tests for Section 4.2:**
- Test init loads sessions from registry
- Test init subscribes to all session topics
- Test `subscribe_to_session/1` subscribes to correct topic
- Test `unsubscribe_from_session/1` unsubscribes
- Test messages routed to correct session

---

## 4.3 Tab Rendering

Implement tab bar rendering using TermUI Tabs widget.

### 4.3.1 Tab Bar Component
- [x] **Task 4.3.1** (completed 2025-12-15)

Create tab bar rendering function.

- [x] 4.3.1.1 Create `render_tabs/1` function:
  - Implemented in ViewHelpers as simple visual rendering
  - Uses basic TermUI components (text, stack) instead of stateful Tabs widget
  - Returns nil when no sessions exist
  - Renders tabs horizontally with separators
- [x] 4.3.1.2 Implement `format_tab_label/2` showing index and name:
  - Implemented with index mapping (10 -> 0)
  - Truncates session names to 15 characters
  - Format: "#{display_index}:#{truncated_name}"
- [x] 4.3.1.3 Show asterisk for modified/unsaved sessions (deferred to future task)
- [x] 4.3.1.4 Style active tab differently:
  - Active tab: bold, underline, cyan color
  - Inactive tabs: muted (bright_black)
- [x] 4.3.1.5 Write unit tests for tab rendering:
  - Added 15 tests total (truncate, format_tab_label, render_tabs)
  - All tests passing

**Implementation Notes**:
- Used simple visual rendering instead of stateful TermUI.Widgets.Tabs
- Event handling deferred to Phase 4.5 (keyboard shortcuts)
- Added helper function `truncate/2` for text truncation
- Integrated tabs into all 3 view layouts (standard, sidebar, drawer)

### 4.3.2 Tab Indicator for 10th Session
- [x] **Task 4.3.2** (completed as part of 4.3.1)

Handle tab 10 with special "0" indicator.

- [x] 4.3.2.1 Tab indices 1-9 show as "1:" through "9:"
- [x] 4.3.2.2 Tab index 10 shows as "0:" (Ctrl+0 shortcut)
- [x] 4.3.2.3 Update `format_tab_label/2` accordingly

**Note**: This was completed as part of Task 4.3.1 implementation.
- [ ] 4.3.2.4 Write unit tests for 10th tab labeling

### 4.3.3 Tab Status Indicators
- [x] **Task 4.3.3** (completed 2025-12-15)

Add status indicators to tabs.

- [x] 4.3.3.1 Show spinner/indicator when session is processing (⟳)
- [x] 4.3.3.2 Show error indicator on agent error (✗)
- [x] 4.3.3.3 Query agent status via Session.AgentAPI.get_status/1
- [x] 4.3.3.4 Write unit tests for status indicators (2 basic tests)

**Implementation Notes**:
- Added `Model.get_session_status/1` to query Session.AgentAPI
- Status indicators: ⟳ (processing), ✓ (idle), ✗ (error), ○ (unconfigured)
- Error tabs always show red color
- Active processing tabs show yellow color
- Updated `render_single_tab/3` to include status parameter
- Added `build_tab_style/2` for status-aware styling

**Unit Tests for Section 4.3:**
- Test `render_tabs/1` creates tab elements
- Test tab labels include index and name
- Test 10th tab shows "0:" prefix
- Test active tab is selected
- Test closeable tabs have close button
- Test processing indicator appears when busy

---

## 4.4 View Integration

Update the main view to include tabs and session-specific content.

### 4.4.1 View Structure
- [x] **Task 4.4.1** (completed 2025-12-15)

Update `view/1` to include tab bar.

- [x] 4.4.1.1 Update all three layout variants (standard, sidebar, drawer)
  - Replaced `render_conversation_area` with `render_session_content`
  - All layouts now use session-aware content rendering
- [x] 4.4.1.2 Conditional rendering based on active session
- [x] 4.4.1.3 Show welcome screen when no sessions
- [x] 4.4.1.4 Write unit tests for view structure (indirectly via render tests)

**Implementation Notes**:
- Created `render_session_content/1` to dispatch based on active_session_id
- When nil: renders welcome screen
- When set: fetches session state and renders conversation

### 4.4.2 Session Content Rendering
- [x] **Task 4.4.2** (completed 2025-12-15)

Render active session's conversation and input.

- [x] 4.4.2.1 Implemented `render_session_content/1` with pattern matching
- [x] 4.4.2.2 Implemented `render_conversation_for_session/2`
  - Fetches session state via `Model.get_active_session_state/1`
  - Updates ConversationView with session's messages
  - Handles missing session state with error screen
- [x] 4.4.2.3 Pass session state to ConversationView widget via `ConversationView.set_messages/2`
- [x] 4.4.2.4 Write unit tests for content rendering (via integration tests)

**Implementation Notes**:
- Added `render_session_error/2` for error cases
- Session state properly passed to ConversationView widget
- Handles nil session gracefully with welcome screen

### 4.4.3 Welcome Screen
- [x] **Task 4.4.3** (completed 2025-12-15)

Create welcome screen for empty session list.

- [x] 4.4.3.1 Implemented `render_welcome_screen/1`
  - Shows "Welcome to JidoCode" title
  - Lists helpful commands (/session new, /resume)
  - Shows keyboard shortcuts (Ctrl+N, Ctrl+1-0, Ctrl+W)
- [x] 4.4.3.2 Style welcome screen appropriately
  - Uses themed colors (primary, accent, muted, info)
  - Consistent styling with rest of TUI
- [x] 4.4.3.3 Write unit tests for welcome screen (via render tests)

**Implementation Notes**:
- Padded to fill available height using `ViewHelpers.pad_lines_to_height/3`
- Clear, helpful information for new users
- Themed styling for consistency

### 4.4.4 Status Bar Updates
- [x] **Task 4.4.4** (completed 2025-12-15)

Update status bar to show active session info.

- [x] 4.4.4.1 Update `render_status_bar/1` to show session name (truncated to 20 chars)
- [x] 4.4.4.2 Show session's project path (truncated to 25 chars, ~ for home)
- [x] 4.4.4.3 Show session's LLM model (session config or fallback to global)
- [x] 4.4.4.4 Format: `[1/3] project-name | ~/path | anthropic:claude-3-5-sonnet | idle`
- [x] 4.4.4.5 Write unit tests for status bar (7 tests)

**Implementation Notes**:
- Created `render_status_bar_no_session/2` for empty state
- Created `render_status_bar_with_session/3` for active session
- Added `format_project_path/2` for path truncation with ~ substitution
- Added `format_model/2` for model display
- Added `build_status_bar_style_for_session/2` for status-aware colors
- Status bar shows session position ([1/3]), name, path, model, status

**Unit Tests for Section 4.4:**
- Test view includes tab bar
- Test view shows welcome screen when no sessions
- Test view shows session content when active
- Test conversation renders from Session.State
- Test status bar shows session info
- Test status bar shows session count

---

## 4.5 Left Sidebar Integration

Add a collapsible left sidebar displaying all work sessions in an accordion format. The sidebar will be 20-25 characters wide, toggleable with Ctrl+S, and integrate seamlessly with existing layouts. This provides quick visual access to all sessions and their contextual information.

### 4.5.1 Accordion Component
- [x] **Task 4.5.1** (completed 2025-12-15)

Build reusable accordion widget with expand/collapse functionality.

- [x] 4.5.1.1 Create `JidoCode.TUI.Widgets.Accordion` module
- [x] 4.5.1.2 Implement `Accordion` struct (sections, active_ids, style):
  - Implemented with MapSet for active_ids (O(1) lookup)
  - Full section struct with id, title, content, badge, icons
  - Style configuration for title, badge, content, icon styling
  - Configurable indent (default: 2 spaces)
- [x] 4.5.1.3 Implement `render/2` function with expand/collapse logic
  - Renders empty state for no sections
  - Shows appropriate icon (▶ collapsed, ▼ expanded)
  - Handles badge display with truncation
  - Indents content when expanded
- [x] 4.5.1.4 Add indentation for nested content (2 spaces)
- [x] 4.5.1.5 Support badge display (message counts, status indicators)
- [x] 4.5.1.6 Write unit tests for accordion component (82 tests, 0 failures)

**Implementation Notes**:
- Module: `lib/jido_code/tui/widgets/accordion.ex` (507 lines)
- Tests: `test/jido_code/tui/widgets/accordion_test.exs` (82 tests)
- Full API: new, expand, collapse, toggle, expand_all, collapse_all
- Section management: add_section, remove_section, update_section
- Accessors: expanded?, get_section, section_count, expanded_count, section_ids
- Comprehensive documentation with @moduledoc and @doc for all public functions
- Uses TermUI primitives (text, stack, Style) for rendering

### 4.5.2 Session Sidebar Component
- [x] **Task 4.5.2** (completed 2025-12-15)

Create session-specific sidebar that uses accordion to display sessions.

- [x] 4.5.2.1 Create `JidoCode.TUI.Widgets.SessionSidebar` module
- [x] 4.5.2.2 Implement `SessionSidebar` struct (sessions, order, active, expanded, width)
- [x] 4.5.2.3 Implement `render/2` function with header and accordion
  - Renders "SESSIONS" header with cyan/bold styling
  - Builds accordion from session list in display order
  - Uses Accordion widget for expand/collapse functionality
- [x] 4.5.2.4 Build accordion sections from session list
  - One section per session
  - Skips missing sessions gracefully
- [x] 4.5.2.5 Add session badges (message count, status indicators)
  - Format: "(msgs: N) [icon]"
  - Uses pagination metadata for efficient message count
  - Status icons: ✓ (idle), ⟳ (processing), ✗ (error), ○ (unconfigured)
- [x] 4.5.2.6 Implement session details rendering (Info, Files, Tools sections - minimal/empty for now)
  - Info section: Created time (relative) and project path (with ~ substitution)
  - Files section: "(empty)" placeholder
  - Tools section: "(empty)" placeholder
- [x] 4.5.2.7 Add active session indicator (→ prefix)
  - Active session gets "→ " prefix in title
  - Inactive sessions have no prefix
- [x] 4.5.2.8 Write unit tests for session sidebar (47 tests, 0 failures)

**Implementation Notes**:
- Module: `lib/jido_code/tui/widgets/session_sidebar.ex` (410 lines)
- Tests: `test/jido_code/tui/widgets/session_sidebar_test.exs` (47 tests)
- Pure rendering component (not StatefulComponent)
- Integrates with Accordion widget from Task 4.5.1
- Name truncation: 15 chars (consistent with tabs)
- Message count via `Session.State.get_messages/3` pagination metadata (efficient)
- Status via `Session.AgentAPI.get_status/1` (reuses tab indicator logic)
- Accessor functions: expanded?, session_count, has_active_session?
- Comprehensive documentation with examples
- Known limitation: Minimum practical width is 20 chars (badge truncation issues below this)

### 4.5.3 Model Updates
- [x] **Task 4.5.3** (completed 2025-12-15)

Add sidebar state to TUI Model for visibility, width, and expanded sections.

- [x] 4.5.3.1 Add `sidebar_visible` field to Model struct (default: true)
  - Added to defstruct with default value `true`
  - Sidebar shown by default on wide terminals (will auto-hide in 4.5.4)
- [x] 4.5.3.2 Add `sidebar_width` field to Model struct (default: 20)
  - Added to defstruct with default value `20`
  - Matches SessionSidebar default and fits session name + badge
- [x] 4.5.3.3 Add `sidebar_expanded` field to Model struct (MapSet of session IDs)
  - Added to defstruct with default value `MapSet.new()`
  - Uses MapSet for O(1) membership checks
- [x] 4.5.3.4 Add `sidebar_focused` field to Model struct for navigation
  - Added to defstruct with default value `false`
  - Input has focus by default
- [x] 4.5.3.5 Update Model typespec with new fields
  - Added sidebar fields to `@type t` in lib/jido_code/tui.ex (lines 173-177)
  - Types: `boolean()`, `pos_integer()`, `MapSet.t(String.t())`, `boolean()`
- [x] 4.5.3.6 Update `init/1` to initialize sidebar state:
  ```elixir
  %Model{
    # ... existing fields
    sidebar_visible: true,
    sidebar_width: 20,
    sidebar_expanded: MapSet.new(),
    sidebar_focused: false
  }
  ```
  - Implemented in lib/jido_code/tui.ex (lines 672-676)
- [x] 4.5.3.7 Write unit tests for model updates
  - Added 20 new tests in test/jido_code/tui_test.exs (lines 125-251)
  - 15 tests for Model struct fields and operations
  - 5 tests for init/1 sidebar initialization
  - All tests passing

**Implementation Notes**:
- Files Modified: `lib/jido_code/tui.ex`, `test/jido_code/tui_test.exs`
- Test Coverage: 20 new tests (256 total, up from 236)
- All new sidebar tests passing
- No breaking changes to existing functionality

### 4.5.4 Layout Integration
- [x] **Task 4.5.4** (completed 2025-12-15)

Integrate sidebar into existing view layouts with responsive behavior.

- [x] 4.5.4.1 Create `render_with_sidebar/1` function in TUI module
  - Implemented as `render_with_session_sidebar/1` (lines 1711-1767)
  - Builds sidebar widget from model state
  - Creates horizontal split layout
- [x] 4.5.4.2 Update `render_main_view/1` to conditionally use sidebar:
  ```elixir
  defp render_main_view(state) do
    {width, _} = state.window

    # Hide sidebar on narrow terminals
    show_sidebar = state.sidebar_visible and width >= 90

    if show_sidebar do
      render_with_session_sidebar(state)
    else
      # Existing layout without sidebar
      # ...
    end
  end
  ```
  - Implemented with cond statement (lines 1575-1621)
  - Checks sidebar_visible and width threshold
- [x] 4.5.4.3 Implement horizontal split (sidebar | separator | main content)
  - Horizontal split using stack(:horizontal, [sidebar, sep, main]) (lines 1747-1752)
  - Vertical separator rendered with │ character
- [x] 4.5.4.4 Adjust main content width when sidebar visible
  - calculate_main_width/1 function (lines 1669-1680)
  - Subtracts sidebar width + separator from content width
  - Enforces minimum width of 20 chars
- [x] 4.5.4.5 Move tabs to main area (not spanning sidebar)
  - Tabs rendered inside sidebar layout, before status bar
  - Tabs use full width (will be constrained in future enhancement)
- [x] 4.5.4.6 Add responsive behavior (<90 chars = hide sidebar)
  - Threshold: `show_sidebar = state.sidebar_visible and width >= 90`
  - Sidebar automatically hidden on narrow terminals
- [x] 4.5.4.7 Ensure sidebar works with reasoning panel layouts
  - Reasoning panel renders in main content area when sidebar visible
  - Responsive breakpoint: main_width >= 60 for reasoning sidebar, else drawer
  - Both sidebar and reasoning panel can be visible simultaneously
- [x] 4.5.4.8 Write unit tests for layout integration
  - Added 5 integration tests (test/jido_code/tui_test.exs lines 254-323)
  - Tests cover sidebar visibility, responsive behavior, reasoning panel integration
  - All new tests passing

**Implementation Notes**:
- Files Modified: lib/jido_code/tui.ex, test/jido_code/tui_test.exs
- Helper functions: calculate_main_width/1, build_session_sidebar/1, render_vertical_separator/1
- Test Coverage: 5 new integration tests (261 total, up from 256)
- All new sidebar layout tests passing
- No breaking changes to existing layouts

### 4.5.5 Keyboard Shortcuts
- [x] **Task 4.5.5** ✅ COMPLETE

Add keyboard shortcuts for sidebar visibility, navigation, and interaction.

- [x] 4.5.5.1 Add Ctrl+S shortcut to toggle sidebar visibility:
  ```elixir
  def event_to_msg(%Event.Key{key: {:ctrl, ?s}}, _state) do
    :toggle_sidebar
  end
  ```
- [x] 4.5.5.2 Update `event_to_msg/2` for `:toggle_sidebar` message
- [x] 4.5.5.3 Implement `update(:toggle_sidebar, model)` handler
- [x] 4.5.5.4 Add Enter key to toggle accordion section (when sidebar focused)
- [x] 4.5.5.5 Add Up/Down arrow keys for sidebar navigation
- [x] 4.5.5.6 Implement `update({:toggle_accordion, section_id}, model)` handler
- [x] 4.5.5.7 Implement `update({:sidebar_nav, direction}, model)` handler
- [x] 4.5.5.8 Add sidebar to focus cycle (`:sidebar` focus state)
- [x] 4.5.5.9 Write unit tests for keyboard shortcuts

### 4.5.6 Visual Polish
- [x] **Task 4.5.6** ✅ COMPLETE

Add visual styling, separators, and responsive adjustments.

- [x] 4.5.6.1 Style sidebar header with cyan/bold (already implemented in 4.5.2)
- [x] 4.5.6.2 Style active session with → and appropriate color (already implemented in 4.5.2)
- [x] 4.5.6.3 Style expanded accordion content with indentation (already implemented in 4.5.1)
- [x] 4.5.6.4 Add vertical separator (│) between sidebar and main (already implemented in 4.5.4)
- [x] 4.5.6.5 Add separator below sidebar header
- [~] 4.5.6.6 Adjust colors for collapsed/expanded state (deferred - requires icon style infrastructure changes)
- [~] 4.5.6.7 Add hover/focus styling (not supported - terminal limitation, deferred to future enhancement)
- [~] 4.5.6.8 Write unit tests for visual styling (existing tests cover visual rendering)

**Unit Tests for Section 4.5:**
- Test accordion renders with all sections collapsed
- Test accordion renders with specific sections expanded
- Test accordion header shows correct icon (▶ collapsed, ▼ expanded)
- Test accordion content is indented when expanded
- Test accordion badges display correctly
- Test accordion handles empty sections list
- Test sidebar renders header "SESSIONS"
- Test sidebar builds one accordion section per session
- Test sidebar shows active session with → indicator
- Test sidebar truncates long session names (15 chars max)
- Test sidebar displays session badges correctly
- Test sidebar expanded content shows session details
- Test sidebar handles empty session list
- Test Model struct includes sidebar fields
- Test init/1 sets default sidebar state (visible: true, width: 20)
- Test sidebar_expanded is initialized as empty MapSet
- Test render_with_sidebar/1 creates horizontal split
- Test sidebar takes configured width from model
- Test main content area adjusts width for sidebar
- Test vertical separator displays between sidebar and main
- Test tabs render in main area (not spanning sidebar)
- Test sidebar hidden on narrow terminals (<90 chars)
- Test sidebar visible on wide terminals (≥90 chars)
- Test Ctrl+S toggles sidebar_visible field
- Test toggle_sidebar switches between true/false
- Test toggle_accordion adds/removes from sidebar_expanded set
- Test Enter key toggles focused accordion section
- Test Up arrow navigates to previous section
- Test Down arrow navigates to next section
- Test sidebar_nav wraps at boundaries
- Test sidebar added to focus cycle
- Test sidebar header uses cyan/bold style
- Test active session has → prefix
- Test vertical separator displays correctly
- Test expanded content is indented
- Test collapsed sections show ▶ icon
- Test expanded sections show ▼ icon

---

## 4.6 Keyboard Navigation

Implement keyboard shortcuts for tab navigation.

### 4.6.1 Tab Switching Shortcuts
- [ ] **Task 4.6.1**

Implement Ctrl+1 through Ctrl+0 for tab switching.

- [ ] 4.6.1.1 Update `event_to_msg/2` for Ctrl+digit keys:
  ```elixir
  def event_to_msg(%Event.Key{key: {:ctrl, ?1}}, _state) do
    {:switch_to_tab, 1}
  end
  # ... Ctrl+2 through Ctrl+9
  def event_to_msg(%Event.Key{key: {:ctrl, ?0}}, _state) do
    {:switch_to_tab, 10}
  end
  ```
- [ ] 4.6.1.2 Implement `update({:switch_to_tab, index}, model)`:
  ```elixir
  def update({:switch_to_tab, index}, model) do
    case Enum.at(model.session_order, index - 1) do
      nil -> model
      session_id -> %{model | active_session_id: session_id}
    end
  end
  ```
- [ ] 4.6.1.3 Handle out-of-range indices gracefully
- [ ] 4.6.1.4 Write unit tests for tab switching

### 4.6.2 Tab Navigation Shortcuts
- [ ] **Task 4.6.2**

Implement Ctrl+Tab and Ctrl+Shift+Tab for cycling.

- [ ] 4.6.2.1 Implement Ctrl+Tab for next tab:
  ```elixir
  def event_to_msg(%Event.Key{key: {:ctrl, :tab}}, _state) do
    :next_tab
  end
  ```
- [ ] 4.6.2.2 Implement `update(:next_tab, model)`:
  ```elixir
  def update(:next_tab, model) do
    current_idx = Enum.find_index(model.session_order, &(&1 == model.active_session_id))
    next_idx = rem(current_idx + 1, length(model.session_order))
    next_id = Enum.at(model.session_order, next_idx)
    %{model | active_session_id: next_id}
  end
  ```
- [ ] 4.6.2.3 Implement Ctrl+Shift+Tab for previous tab
- [ ] 4.6.2.4 Handle single/empty session list
- [ ] 4.6.2.5 Write unit tests for tab cycling

### 4.6.3 Session Close Shortcut
- [ ] **Task 4.6.3**

Implement Ctrl+W for closing active session.

- [ ] 4.6.3.1 Implement Ctrl+W handler:
  ```elixir
  def event_to_msg(%Event.Key{key: {:ctrl, ?w}}, _state) do
    :close_active_session
  end
  ```
- [ ] 4.6.3.2 Implement `update(:close_active_session, model)`:
  - Show confirmation if session has unsaved state (future)
  - Call SessionSupervisor.stop_session/1
  - Remove from model
  - Switch to adjacent tab
- [ ] 4.6.3.3 Prevent closing last session (or show welcome screen)
- [ ] 4.6.3.4 Write unit tests for session close

### 4.6.4 New Session Shortcut
- [ ] **Task 4.6.4**

Implement Ctrl+N for creating new session.

- [ ] 4.6.4.1 Implement Ctrl+N handler returning `:new_session_dialog`
- [ ] 4.6.4.2 Show dialog/input for project path
- [ ] 4.6.4.3 Alternative: Create session for current directory
- [ ] 4.6.4.4 Write unit tests for new session shortcut

**Unit Tests for Section 4.6:**
- Test Ctrl+1 switches to first tab
- Test Ctrl+0 switches to 10th tab
- Test Ctrl+5 does nothing if only 3 sessions
- Test Ctrl+Tab cycles to next tab
- Test Ctrl+Shift+Tab cycles to previous tab
- Test tab cycling wraps around
- Test Ctrl+W closes active session
- Test Ctrl+W with one session shows warning
- Test Ctrl+N initiates new session

---

## 4.7 Event Routing Updates

Update event handling to route events to correct session.

### 4.7.1 Input Event Routing
- [ ] **Task 4.7.1**

Route input events to active session's agent.

- [ ] 4.7.1.1 Update submit handler to use active session:
  ```elixir
  def update({:submit, text}, model) do
    session_id = model.active_session_id
    Session.AgentAPI.send_message_stream(session_id, text)
    # Update model to show processing state
    %{model | agent_status: :processing}
  end
  ```
- [ ] 4.7.1.2 Handle submit when no active session
- [ ] 4.7.1.3 Write unit tests for input routing

### 4.7.2 Scroll Event Routing
- [ ] **Task 4.7.2**

Route scroll events to active session's conversation view.

- [ ] 4.7.2.1 Update scroll handlers to update Session.State:
  ```elixir
  def update({:scroll, direction}, model) do
    session_id = model.active_session_id
    Session.State.scroll_by(session_id, scroll_amount(direction))
    model
  end
  ```
- [ ] 4.7.2.2 Handle scroll when no active session
- [ ] 4.7.2.3 Write unit tests for scroll routing

### 4.7.3 PubSub Event Handling
- [ ] **Task 4.7.3**

Update PubSub event handlers for multi-session.

- [ ] 4.7.3.1 Update stream chunk handler:
  ```elixir
  def update({:stream_chunk, session_id, chunk}, model) do
    # Session.State already updated by agent
    # Just trigger re-render if this is active session
    model
  end
  ```
- [ ] 4.7.3.2 Update stream end handler
- [ ] 4.7.3.3 Update tool call/result handlers
- [ ] 4.7.3.4 Only re-render if event is for active session
- [ ] 4.7.3.5 Write unit tests for PubSub handling

**Unit Tests for Section 4.7:**
- Test submit routes to active session's agent
- Test submit shows processing state
- Test scroll routes to active session
- Test PubSub events update correct session
- Test inactive session events don't trigger full re-render

---

## 4.8 Phase 4 Integration Tests

Comprehensive integration tests verifying all Phase 4 TUI components work together correctly.

### 4.8.1 Tab Navigation Integration
- [ ] **Task 4.8.1**

Test tab navigation works end-to-end.

- [ ] 4.8.1.1 Create `test/jido_code/integration/session_phase4_test.exs`
- [ ] 4.8.1.2 Test: Create 3 sessions → tabs render with correct labels → Ctrl+1/2/3 switch correctly
- [ ] 4.8.1.3 Test: Ctrl+Tab cycles through all tabs in order
- [ ] 4.8.1.4 Test: Ctrl+Shift+Tab cycles backwards
- [ ] 4.8.1.5 Test: Close middle tab → active switches to adjacent → tab order updates
- [ ] 4.8.1.6 Test: 10th tab accessible via Ctrl+0
- [ ] 4.8.1.7 Write all navigation integration tests

### 4.8.2 View-State Synchronization
- [ ] **Task 4.8.2**

Test view correctly reflects session state.

- [ ] 4.8.2.1 Test: Switch session → conversation view shows new session's messages
- [ ] 4.8.2.2 Test: Message received via PubSub → view updates for active session only
- [ ] 4.8.2.3 Test: Streaming chunk received → streaming message area updates
- [ ] 4.8.2.4 Test: Session.State updated → next view render reflects change
- [ ] 4.8.2.5 Test: Status bar shows active session's info (name, model, path)
- [ ] 4.8.2.6 Write all synchronization integration tests

### 4.8.3 Input-Agent Integration
- [ ] **Task 4.8.3**

Test user input correctly routes to session agent.

- [ ] 4.8.3.1 Test: Submit text in session A → AgentAPI.send_message called for session A
- [ ] 4.8.3.2 Test: Switch to session B → submit → message goes to session B's agent
- [ ] 4.8.3.3 Test: Submit during streaming → handled correctly (queue or reject)
- [ ] 4.8.3.4 Test: Scroll events route to active session's conversation view
- [ ] 4.8.3.5 Write all input integration tests

### 4.8.4 PubSub Event Flow
- [ ] **Task 4.8.4**

Test PubSub events flow correctly through TUI.

- [ ] 4.8.4.1 Test: Subscribe to session on add → receive events for that session
- [ ] 4.8.4.2 Test: Unsubscribe on session close → no more events received
- [ ] 4.8.4.3 Test: Events for inactive session → model updated but no re-render triggered
- [ ] 4.8.4.4 Test: Tool call event → tool call UI element appears in active session
- [ ] 4.8.4.5 Test: Tool result event → result displayed in active session
- [ ] 4.8.4.6 Write all PubSub integration tests

### 4.8.5 Welcome Screen and Empty State
- [ ] **Task 4.8.5**

Test empty state and welcome screen behavior.

- [ ] 4.8.5.1 Test: No sessions → welcome screen rendered
- [ ] 4.8.5.2 Test: Close last session → welcome screen appears
- [ ] 4.8.5.3 Test: Create first session from welcome → tab bar appears
- [ ] 4.8.5.4 Test: Ctrl+N from welcome → new session dialog
- [ ] 4.8.5.5 Write all empty state integration tests

**Integration Tests for Section 4.8:**
- Tab navigation works across all scenarios
- View stays in sync with session state
- Input correctly routes to active session
- PubSub events handled correctly
- Welcome screen transitions work

---

## Success Criteria

1. **Tab Bar Display**: Tabs widget shows all sessions with numbered labels
2. **Tab Switching**: Ctrl+1 through Ctrl+0 switch to numbered tabs
3. **Tab Cycling**: Ctrl+Tab and Ctrl+Shift+Tab cycle through tabs
4. **Session Close**: Ctrl+W closes active session with proper cleanup
5. **Welcome Screen**: Empty session list shows welcome screen
6. **Status Bar**: Shows active session name, path, model, and count
7. **Content Isolation**: Each tab shows its session's conversation
8. **Event Routing**: Input and scroll events go to active session
9. **PubSub Routing**: Events routed to correct session
10. **Test Coverage**: Minimum 80% coverage for phase 4 code
11. **Integration Tests**: All Phase 4 components work together correctly (Section 4.8)

---

## Critical Files

**New Files:**
- `lib/jido_code/tui/widgets/accordion.ex` - Accordion widget (Section 4.5)
- `lib/jido_code/tui/widgets/session_sidebar.ex` - Session sidebar component (Section 4.5)
- `test/jido_code/tui/widgets/accordion_test.exs` - Accordion widget tests (Section 4.5)
- `test/jido_code/tui/widgets/session_sidebar_test.exs` - Session sidebar tests (Section 4.5)
- `test/jido_code/integration/session_phase4_test.exs` - Integration tests (Section 4.8)

**Modified Files:**
- `lib/jido_code/tui.ex` - Model struct, init, view, update handlers, sidebar integration
- `lib/jido_code/tui/view_helpers.ex` - Tab and content rendering
- `lib/jido_code/tui/event_handlers.ex` - Tab navigation events, sidebar shortcuts
- `lib/jido_code/tui/message_handlers.ex` - Session-aware message handling
- `test/jido_code/tui_test.exs` - Update tests for multi-session and sidebar

---

## Dependencies

- **Depends on Phase 1**: Session struct, SessionRegistry
- **Depends on Phase 2**: Session.State for conversation data
- **Depends on Phase 3**: Session.AgentAPI for message sending
- **Phase 5 depends on this**: Commands need TUI integration

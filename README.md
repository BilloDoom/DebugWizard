# DebugWizard

A Godot 4 editor addon for tracking node signals and monitoring runtime values through a visual debug overlay — without writing boilerplate debug code in your scripts.

---

## Installation

1. Copy the `debugWizard` folder into your project's `res://addons/` directory
2. Open **Project → Project Settings → Plugins**
3. Find **DebugWizard** and tick the **Enable** checkbox

Two autoloads will be registered automatically:
- `DebugRegistry` — the runtime data hub, call this from your scripts
- `DebugUi` — the overlay that reads from DebugRegistry, no direct calls needed

---

## The Dock

Once enabled, a **DebugWizard** tab appears at the bottom of the editor alongside Output and Debugger.

**Workflow:**
1. Click any node in the Scene Tree
2. The dock shows all of that node's signals grouped by class (script signals first, then built-in by declaring class)
3. Set an optional display name, type, and color in the top bar
4. Press **Track** next to any signal to register it
5. Registered signals appear in the list at the bottom of the dock and persist across editor restarts

To stop tracking a signal, press **Untrack** in the signal list or **X** in the registered list.

---

## Signal Types

When registering a signal you choose how its data is displayed at runtime:

| Type | Description |
|------|-------------|
| **Label** | Displays the latest emitted value as text |
| **Line** | Plots emitted values over time as a line graph |
| **Step** | Plots emitted values as a stepped graph (good for discrete state changes) |

---

## Tracking Without the UI

You can also send data to the overlay manually from any script — useful when you need to compute or reshape values before displaying them:

```gdscript
# Fire-and-forget event (state changes, one-off triggers)
DebugRegistry.dispatch("state_changed", { state = "Running" })

# Register a polled value (read every frame, no signal needed)
DebugRegistry.watch("speed", func(): return velocity.length())

# Unregister when the node is freed
func _exit_tree() -> void:
    DebugRegistry.unwatch("speed")
```

Manual calls and signal-tracked entries coexist — both feed into the same overlay.

---

## DebugRegistry API

```gdscript
# Events — low frequency, signal-like
DebugRegistry.dispatch(category: String, data: Dictionary)

# Polled values — read each frame by the overlay
DebugRegistry.watch(label: String, getter: Callable)
DebugRegistry.unwatch(label: String)

# Convenience — watch a property directly on a node
DebugRegistry.watch_node(label: String, node: Node, property: String)
```

---

## How Signal Connections Work

Signals registered through the dock are saved as node paths relative to the scene root in `res://addons/debugWizard/signal_registry.cfg`. At runtime, DebugRegistry resolves these paths against the current scene and connects to the real signals automatically.

If a node path can't be found at runtime a warning is printed and that entry is skipped — nothing breaks.

---

## Notes

- Deleting the addon folder without disabling it first will leave stale autoload entries in `project.godot` — always disable via **Project Settings → Plugins** before removing files
- Signal argument types are inferred at connection time; complex or untyped arguments are forwarded as-is
- The `signal_registry.cfg` file is safe to commit to version control — it contains only node paths and display settings, no runtime state

---

## Godot Version

Built for **Godot 4.x**. Not compatible with Godot 3.

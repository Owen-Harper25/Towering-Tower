# Editing the Tree Expedition

The expedition's creative configuration now lives in Godot scenes instead of `arena.gd`.

## Branches and rooms

Open `res://Scenes/Expedition/expedition_director.tscn`.

- Each direct child of `ExpeditionDirector` is one branch.
- Select a branch to edit its name, briefing, guardian scene, palette, floor count, and attack profile.
- Expand a branch's `Rooms` child to edit individual room nodes.
- A room exposes enemy composition bonuses, health/speed scaling, characteristic-drop scaling, and a layout category.
- Reorder room nodes to change their repeating order through that branch.
- Duplicate a room node to add another room type without changing campaign code.

## Traversal map

Open `res://Scenes/UI/tree_traversal_map.tscn`.

- `MapPanel/BranchPaths` contains one editable `Path2D` per branch plus the Crown Nest path.
- Select a path and move its curve points in the 2D editor to change the agent's route.
- Replace `TreePhoto` with finished tree artwork without changing the paths or animation script.
- Transition duration, hold time, path width, labels, frame layout, and all three sound players are editable in the Inspector.

## Guardians

Guardian presentation scenes remain under `res://Scenes/tree_guardian_*.tscn`. Assign a different guardian scene directly on a branch node to swap it.

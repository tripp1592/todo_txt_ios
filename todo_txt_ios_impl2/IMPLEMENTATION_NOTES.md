# Implementation notes

This drop‑in package contains a refactored structure for the `todo_txt_ios` project. Key changes:

## File Organization

- `todo_txt/Models` now contains `TodoTask.swift` with the core task model.
- `todo_txt/Domain` contains `TodoParser.swift` and parsing/serialization logic along with error definitions.
- `todo_txt/Storage` contains:
  - `BookmarkStore.swift` for bookmark management.
  - `SecurityScope.swift` with a helper for security‑scoped resources.
  - `TodoStore.swift` defining a protocol for stores.
  - `TodoFileStore.swift` implementing `TodoStore` and providing external/iCloud file handling.
- `todo_txt/ViewModels` contains `TodoListViewModel.swift` which now accepts a `TodoStore` in its initializer.
- `todo_txt/Views` contains `ContentView.swift` (UI only) and `Sheets.swift` (various sheet views and helpers).

## Injection and Dependency

`TodoListViewModel` now takes a `TodoStore` (defaulting to `TodoFileStore.shared`), improving testability and reducing reliance on singletons.

`ContentView` can be initialized with any `TodoListViewModel`, making it easier to preview with sample data or inject alternative stores.

## UI Tests

`todo_txtUITests/TodoListUITests.swift` demonstrates basic UI flows for adding, toggling, and archiving tasks via the Settings screen.

## Notes

- Xcode project configuration changes will still be needed to remove `.gitignore` and `README.md` from copy phases and add these new files to the appropriate build phases.
- Some minor references to `TodoFileStore.shared` remain in the view layer for sharing and file name display. This keeps the UI simple; more work is needed to fully inject the store into these contexts.
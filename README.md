# todo_txt_ios

`todo_txt_ios` is a SwiftUI iPhone app for working with a plain text `todo.txt` file.

It stays close to the `todo.txt` format instead of introducing a database or proprietary store. Tasks live in a text file, and the app provides a native iOS interface for adding, editing, sorting, filtering, completing, and archiving them.

## Why this app

- Plain text stays portable and easy to inspect
- `todo.txt` works across tools and platforms
- A focused mobile UI is faster than editing raw lines on a phone
- The file remains readable even outside the app

## Features

- Read and write a single `todo.txt` file
- Use the app's local Documents file or choose your own `.txt` file
- Optional iCloud Drive-based workflow
- Strict parsing and serialization for standard `todo.txt` syntax
- Support for:
  - priorities like `(A)`
  - creation dates
  - completion dates
  - projects like `+Project`
  - contexts like `@context`
  - metadata like `due:2026-03-20`
- Sort and filter tasks from the main list
- Edit tasks with a structured sheet instead of rewriting full lines manually
- Archive completed tasks to `done.txt`
- Notification permission flow in Settings

## Example

```text
(A) 2026-03-11 Call Mom +Family @phone due:2026-03-20
Plan trip +Vacation @laptop
x 2026-03-12 2026-03-11 Review pull request +Work @mac
```

## Format notes

This project follows the core `todo.txt` conventions:

- One line equals one task
- Incomplete tasks may start with priority and an optional creation date
- Completed tasks start with `x` followed by a completion date
- Projects use `+...`
- Contexts use `@...`
- Additional metadata uses `key:value`

Reference: [`todo_txt/docs/todo_txt_format.md`](todo_txt/docs/todo_txt_format.md)

## Screenshot

![todo_txt_ios screenshot](todo_txt/Gemini_Generated_Image_34b1ly34b1ly34b1.png)

## Running locally

1. Open the project in Xcode.
2. Select the `todo_txt` app target.
3. Run on an iPhone simulator or device.

On first launch, you can either:

- use a local app-managed `todo.txt` file
- import or choose an existing `.txt` file

## Testing

The project includes both unit and UI tests:

- `todo_txtTests`
- `todo_txtUITests`

The unit tests cover parser behavior, round-trip serialization, filtered deletion behavior, save behavior for unparseable lines, and archive failure recovery.

## Project layout

- `todo_txt/todo_txt/ContentView.swift` contains the main UI, parser, storage logic, settings, and edit flows
- `todo_txt/todo_txt/todo_txtApp.swift` contains the app entry point
- `todo_txt/docs/` contains format and supporting documentation
- `todo_txt/todo_txtTests/` contains unit tests using the `Testing` framework
- `todo_txt/todo_txtUITests/` contains UI automation tests

## Repository

GitHub: <https://github.com/tripp1592/todo_txt_ios>

# Glintboard

**A clipboard that remembers where everything came from.**

Glintboard is a lightweight, open source shelf and mood board for macOS. Capture text, links, images, files, and screenshots with one keystroke or a drag, and every scrap keeps a live reference to its source: the exact passage on a web page, the Mail message, the file. Jump back to the source, paste with attribution, add your own notes, and arrange collections as boards.

> **Status:** early development (milestone M0). Not ready for everyday use yet.

## Principles

- **Reference first.** Every scrap knows where it came from, and tells you when the source changes or disappears.
- **Native and lightweight.** Swift and Apple frameworks only, no third-party dependencies, no idle CPU use.
- **Your files.** Scraps are plain Markdown files in a folder you choose, readable without the app.
- **Private by default.** Nothing leaves your Mac unless you turn on an opt-in feature.

## Build from source

You need a Mac with the Xcode version listed in `.xcode-version`. Nothing else.

```bash
make bootstrap   # checks your setup and runs the core tests
make run         # builds and launches the Dev app
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Documentation

- [Design](docs/design.md): what the app does
- [Architecture](docs/architecture.md): how it's built
- [Milestones](docs/milestones.md): what's planned, with requirements and acceptance criteria
- [Decisions](docs/decisions/): why things are the way they are

## Origin

Inspired by Scott Jenson's talk [Are we really going to use the same Desktop UX forever?](https://www.youtube.com/watch?v=V7AfAcQwLW0) (KDE, 2026).

## License

To be decided (MIT or Apache 2.0) before the first public release.

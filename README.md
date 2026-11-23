# HQPlayerKit

A Swift client for the [HQPlayer](https://www.signalyst.com) control protocol
(XML over TCP port 4321): status and info, transport, volume, and the
filter / shaper / mode / sample-rate settings, plus LAN discovery and saved
profiles. Pure Swift concurrency, no dependencies.

HQPlayerKit is an independent project, not affiliated with or endorsed by
Signalyst. "HQPlayer" is a trademark of Signalyst.

## Requirements

- macOS 14+
- Swift 5.10+
- HQPlayer Desktop or HQPlayer Embedded with network control enabled

## Install

```swift
// Package.swift
.package(url: "https://github.com/majorgreys/HQPlayerKit.git", from: "0.1.0"),
// target dependencies
.product(name: "HQPlayerKit", package: "HQPlayerKit"),
```

## Usage

```swift
import HQPlayerKit

let found = await HQPlayerDiscovery.discover()     // [DiscoveredHQPlayer]
let hqp = HQPlayerClient(host: found.first?.host ?? "192.0.2.20")
try await hqp.connect()

let status = try await hqp.status()
print(status.activeFilter ?? "-", status.activeRate ?? 0)

let filters = try await hqp.getFilters()           // names and values for setFilter
try await hqp.setFilter(value: filters[0].value)
try await hqp.volume(db: -20)
await hqp.disconnect()
```

`HQPlayerProfile` bundles filter, shaper, mode and rate so you can apply them
together with `applyProfile(_:)`. For commands without a wrapper, `send(_:)`
takes a raw `HQPlayerCommand`. Logging goes to `os.Logger` under
`HQPlayerKitLog.subsystem` (default `"HQPlayerKit"`).

## Tests

```bash
swift test
```

## License

MIT. See [LICENSE](LICENSE).

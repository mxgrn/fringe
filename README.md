# Fringe

A macOS menu bar utility that draws colored borders on inactive screens, making it easy to see which display is currently active.

## Install

```
swift build -c release
cp .build/release/fringe /usr/local/bin/
```

## Usage

```
# Start with default orange border
fringe

# Custom color and thickness
fringe --color red --thickness 5
fringe --color '#FF5500' --thickness 2

# Stop
fringe stop
```

### Colors

Named colors: `orange`, `red`, `blue`, `green`, `yellow`, `white`, `cyan`, `pink`, `purple`

Or any hex color: `#FF5500`

## Requirements

- macOS 13+
- Swift 5.9+

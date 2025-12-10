# mcurl - Multi-threaded HTTP/HTTPS File Downloader

A Rust implementation of multi-threaded file downloader that splits downloads into parallel chunks for improved performance.

## Features

- **Parallel Downloads**: Splits files into multiple chunks downloaded simultaneously
- **Smart Thread Detection**: Automatically uses CPU core count for optimal thread count
- **Progress Display**: Real-time progress bar with download speed
- **HTTP Range Support**: Uses HTTP Range requests for efficient chunk downloading
- **Cross-platform**: Works on Linux, macOS, and Windows
- **Error Handling**: Graceful error handling with automatic cleanup

## Installation

### Build from Source

```bash
cd tools/mcurl
cargo build --release
```

The compiled binary will be available at `target/release/mcurl`.

### Install to System

```bash
cd tools/mcurl
cargo install --path .
```

## Usage

### Basic Usage

Download a file with automatic settings (CPU cores as thread count, filename from URL):

```bash
mcurl https://example.com/largefile.zip
```

### Specify Thread Count

Download with a specific number of parallel threads:

```bash
mcurl -s 8 https://example.com/largefile.zip
```

### Specify Output File

Download to a specific output file:

```bash
mcurl -o myfile.zip https://example.com/largefile.zip
```

### Combined Options

```bash
mcurl -s 16 -o output.bin https://example.com/file.bin
```

## Command-line Options

- `-s, --slices <N>` - Number of parallel download threads (default: CPU cores)
- `-o, --output <FILE>` - Output filename (default: derived from URL)
- `-h, --help` - Display help information
- `-V, --version` - Display version information

## Requirements

The target server must support:
- HTTP Range requests
- Content-Length header

## Comparison with Shell Script

This Rust implementation provides several advantages over the original bash script (`mcurl.sh`):

1. **Better Performance**: Native compiled binary with efficient async I/O
2. **Cross-platform**: Works consistently on Linux, macOS, and Windows
3. **Better Error Handling**: Comprehensive error messages and automatic cleanup
4. **Modern Progress Display**: Uses indicatif for professional progress bars
5. **Memory Safety**: Rust's memory safety guarantees prevent common bugs
6. **Concurrent Downloads**: Uses Tokio async runtime for efficient parallelism

## How It Works

1. **Initial Request**: Sends a HEAD request to get file size and verify Range support
2. **Chunk Calculation**: Divides file into equal chunks based on thread count
3. **Parallel Download**: Downloads all chunks simultaneously using async tasks
4. **Merging**: Sequentially merges all chunks into the final output file
5. **Cleanup**: Removes temporary chunk files after successful merge

## Dependencies

- `reqwest` - HTTP client with async support
- `tokio` - Async runtime
- `clap` - Command-line argument parsing
- `indicatif` - Progress bar display
- `num_cpus` - CPU core detection
- `anyhow` - Error handling
- `futures` - Async utilities

## License

Licensed under the Apache License, Version 2.0. See the source file for details.

## Author

Copyright 2016 Wanghong Lin

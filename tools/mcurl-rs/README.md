# mcurl - Multi-threaded Downloader with Proxy Support

A high-performance, multi-threaded file downloader written in Rust with proxy support.

## Features

- **Multi-threaded downloads**: Splits downloads into parallel slices for faster speeds
- **Proxy support**: HTTP, HTTPS, and SOCKS5 proxies
- **Proxy authentication**: Username and password authentication for proxies
- **Environment variable support**: Respects `HTTP_PROXY`, `HTTPS_PROXY`, and `ALL_PROXY` environment variables
- **Progress bar**: Real-time download progress with speed and ETA
- **Range request support**: Efficiently downloads large files in chunks

## Installation

```bash
cd tools/mcurl-rs
cargo build --release
```

The binary will be available at `target/release/mcurl`.

## Usage

### Basic download
```bash
mcurl https://example.com/file.zip
```

### Specify output file
```bash
mcurl -o output.zip https://example.com/file.zip
```

### Use custom number of slices
```bash
mcurl -s 10 https://example.com/file.zip
```

### Download through HTTP proxy
```bash
mcurl --proxy http://proxy.example.com:8080 https://example.com/file.zip
```

### Download through authenticated proxy
```bash
mcurl --proxy http://proxy.example.com:8080 --proxy-user myuser --proxy-pass mypass https://example.com/file.zip
```

### Download through SOCKS5 proxy
```bash
mcurl --proxy socks5://127.0.0.1:1080 https://example.com/file.zip
```

### Short form with proxy
```bash
mcurl -p http://proxy:8080 -o output.zip https://example.com/file.zip
```

### Using environment variables for proxy
```bash
export HTTP_PROXY=http://proxy.example.com:8080
mcurl https://example.com/file.zip
```

## Command-Line Options

- `URL`: The URL to download (required)
- `-o, --output <FILE>`: Output file name (default: derived from URL)
- `-s, --slices <NUM>`: Number of parallel download slices (default: number of CPU cores)
- `-p, --proxy <URL>`: Proxy server URL (supports http://, https://, and socks5://)
- `--proxy-user <USER>`: Proxy authentication username
- `--proxy-pass <PASSWORD>`: Proxy authentication password
- `-h, --help`: Print help information
- `-V, --version`: Print version information

## Environment Variables

The following environment variables are checked if no `--proxy` option is provided:

- `HTTP_PROXY`: Proxy for HTTP requests
- `HTTPS_PROXY`: Proxy for HTTPS requests
- `ALL_PROXY`: Proxy for all requests

## Requirements

- Rust 1.70 or later
- Internet connection
- Server must support HTTP range requests for multi-threaded downloads

## License

Same as the parent repository.

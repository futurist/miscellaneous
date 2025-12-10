# mcurl Usage Examples

This document provides comprehensive examples of using mcurl with various proxy configurations.

## Basic Usage

### Simple download
```bash
mcurl https://example.com/file.zip
```
Downloads the file to the current directory with the filename extracted from the URL.

### Specify output filename
```bash
mcurl -o myfile.zip https://example.com/file.zip
```

### Control number of download threads
```bash
mcurl -s 8 https://example.com/largefile.iso
```
Uses 8 parallel slices for the download.

## Proxy Configuration

### HTTP Proxy

#### Basic HTTP proxy
```bash
mcurl --proxy http://proxy.example.com:8080 https://example.com/file.zip
```

#### Short form
```bash
mcurl -p http://proxy.example.com:8080 https://example.com/file.zip
```

### HTTPS Proxy
```bash
mcurl --proxy https://secure-proxy.example.com:8443 https://example.com/file.zip
```

### SOCKS5 Proxy
```bash
mcurl --proxy socks5://127.0.0.1:1080 https://example.com/file.zip
```

### Authenticated Proxy

#### HTTP proxy with authentication
```bash
mcurl --proxy http://proxy.example.com:8080 \
      --proxy-user myusername \
      --proxy-pass mypassword \
      https://example.com/file.zip
```

#### SOCKS5 proxy with authentication
```bash
mcurl -p socks5://127.0.0.1:1080 \
      --proxy-user admin \
      --proxy-pass secret123 \
      -o output.zip \
      https://example.com/file.zip
```

## Environment Variables

### Using HTTP_PROXY
```bash
export HTTP_PROXY=http://proxy.example.com:8080
mcurl https://example.com/file.zip
```

### Using HTTPS_PROXY
```bash
export HTTPS_PROXY=https://secure-proxy.example.com:8443
mcurl https://secure-site.example.com/file.zip
```

### Using ALL_PROXY (applies to all protocols)
```bash
export ALL_PROXY=socks5://127.0.0.1:1080
mcurl https://example.com/file.zip
```

### Using both HTTP_PROXY and HTTPS_PROXY
```bash
export HTTP_PROXY=http://proxy.example.com:8080
export HTTPS_PROXY=https://secure-proxy.example.com:8443
mcurl https://example.com/file.zip
```
The tool will use HTTPS_PROXY for HTTPS URLs and HTTP_PROXY for HTTP URLs.

## Combined Examples

### Download with custom slices, output, and proxy
```bash
mcurl -s 16 \
      -o downloaded.iso \
      -p http://proxy.example.com:8080 \
      https://mirror.example.com/ubuntu-24.04.iso
```

### Download through authenticated SOCKS5 proxy with custom output
```bash
mcurl -p socks5://127.0.0.1:9050 \
      --proxy-user toruser \
      --proxy-pass torpass \
      -o private-file.zip \
      -s 4 \
      https://secure-site.example.com/file.zip
```

## Error Handling

### Invalid proxy URL
```bash
mcurl --proxy "not-a-valid-url" https://example.com/file.zip
# Error: Failed to send HEAD request
```

### Proxy authentication required but not provided
```bash
mcurl --proxy http://authenticated-proxy.example.com:8080 https://example.com/file.zip
# Error: Server returned error status: 407 Proxy Authentication Required
```

### Invalid URL
```bash
mcurl ftp://example.com/file.zip
# Error: Invalid URL: ftp://example.com/file.zip. URL must start with http:// or https://
```

## Tips

1. **Server support required**: The server must support HTTP range requests for multi-threaded downloads to work.

2. **Proxy precedence**: Command-line proxy (`--proxy`) takes precedence over environment variables.

3. **Environment variable priority**: When no `--proxy` is specified:
   - ALL_PROXY applies to all requests
   - If ALL_PROXY is not set, HTTP_PROXY and HTTPS_PROXY are used based on the URL scheme

4. **Performance**: For optimal performance, the number of slices should match or be slightly higher than your CPU core count.

5. **Large files**: For very large files, increasing the number of slices can significantly improve download speed if your network bandwidth supports it.

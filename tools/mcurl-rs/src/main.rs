use anyhow::{Context, Result};
use clap::Parser;
use futures::stream::{self, StreamExt};
use indicatif::{ProgressBar, ProgressStyle};
use std::fs::File;
use std::io::{Seek, SeekFrom, Write};
use std::sync::Arc;
use tokio::sync::{Mutex, Semaphore};

/// Multi-threaded curl-like downloader with proxy support
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// URL to download
    #[arg(value_name = "URL")]
    url: String,

    /// Output file name (default: derived from URL)
    #[arg(short = 'o', long = "output", value_name = "FILE")]
    output: Option<String>,

    /// Number of parallel download slices (default: number of CPU cores)
    #[arg(short = 's', long = "slices", value_name = "NUM", default_value_t = num_cpus::get())]
    slices: usize,

    /// Proxy server URL (e.g., http://proxy.example.com:8080 or socks5://127.0.0.1:1080)
    #[arg(short = 'p', long = "proxy", value_name = "URL")]
    proxy: Option<String>,

    /// Proxy authentication username
    #[arg(long = "proxy-user", value_name = "USER")]
    proxy_user: Option<String>,

    /// Proxy authentication password
    #[arg(long = "proxy-pass", value_name = "PASSWORD")]
    proxy_pass: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Validate URL
    if !args.url.starts_with("http://") && !args.url.starts_with("https://") {
        anyhow::bail!("Invalid URL: {}. URL must start with http:// or https://", args.url);
    }

    // Determine output filename
    let output_file = match args.output {
        Some(ref name) => name.clone(),
        None => {
            let url_path = args.url.split('?').next().unwrap_or(&args.url);
            url_path
                .split('/')
                .last()
                .filter(|s| !s.is_empty())
                .unwrap_or("downloaded_file")
                .to_string()
        }
    };

    println!("Download {} to {} with {} slices", args.url, output_file, args.slices);

    // Build HTTP client with proxy configuration
    let client = build_client(&args)?;

    // Get content length to support range requests
    let response = client
        .head(&args.url)
        .send()
        .await
        .context("Failed to send HEAD request")?;

    if !response.status().is_success() {
        anyhow::bail!("Server returned error status: {}", response.status());
    }

    let content_length = response
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
        .context("Could not get content length. Server may not support range requests.")?;

    println!("Content length: {} bytes", content_length);

    // Create output file
    let file = File::create(&output_file)
        .context(format!("Failed to create output file: {}", output_file))?;
    file.set_len(content_length)
        .context("Failed to preallocate file")?;
    let file = Arc::new(Mutex::new(file));

    // Calculate slice size
    let slice_size = (content_length + args.slices as u64 - 1) / args.slices as u64;

    // Create progress bar
    let progress = ProgressBar::new(content_length);
    progress.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({bytes_per_sec}, {eta})")
            .unwrap()
            .progress_chars("#>-"),
    );

    // Download slices concurrently
    let semaphore = Arc::new(Semaphore::new(args.slices));
    let client = Arc::new(client);
    let url = Arc::new(args.url.clone());
    let progress = Arc::new(progress);

    let tasks: Vec<_> = (0..args.slices)
        .map(|i| {
            let semaphore = Arc::clone(&semaphore);
            let client = Arc::clone(&client);
            let url = Arc::clone(&url);
            let progress = Arc::clone(&progress);
            let file = Arc::clone(&file);

            async move {
                let _permit = semaphore.acquire().await.unwrap();

                let start = i as u64 * slice_size;
                let end = if i == args.slices - 1 {
                    content_length - 1
                } else {
                    (i as u64 + 1) * slice_size - 1
                };

                let data = download_slice(&client, &url, start, end, &progress).await?;
                
                // Write to file with proper synchronization
                let mut file_guard = file.lock().await;
                file_guard.seek(SeekFrom::Start(start))
                    .context("Failed to seek in file")?;
                file_guard.write_all(&data).context("Failed to write to file")?;
                
                Ok::<(), anyhow::Error>(())
            }
        })
        .collect();

    let results: Vec<Result<()>> = stream::iter(tasks)
        .buffer_unordered(args.slices)
        .collect()
        .await;

    // Check for errors
    for result in results {
        result?;
    }

    progress.finish_with_message("Download complete!");
    println!("\nDownload completed: {}", output_file);

    Ok(())
}

fn build_client(args: &Args) -> Result<reqwest::Client> {
    let mut client_builder = reqwest::Client::builder();

    // Configure proxy if provided
    if let Some(proxy_url) = &args.proxy {
        println!("Using proxy: {}", proxy_url);
        
        let mut proxy = reqwest::Proxy::all(proxy_url)
            .context(format!("Invalid proxy URL: {}", proxy_url))?;

        // Add proxy authentication if provided
        if let (Some(user), Some(pass)) = (&args.proxy_user, &args.proxy_pass) {
            println!("Using proxy authentication with user: {}", user);
            proxy = proxy.basic_auth(user, pass);
        }

        client_builder = client_builder.proxy(proxy);
    } else {
        // Check environment variables for proxy configuration
        if let Ok(http_proxy) = std::env::var("HTTP_PROXY") {
            println!("Using HTTP_PROXY from environment: {}", http_proxy);
            let proxy = reqwest::Proxy::http(&http_proxy)
                .context(format!("Invalid HTTP_PROXY: {}", http_proxy))?;
            client_builder = client_builder.proxy(proxy);
        } else if let Ok(https_proxy) = std::env::var("HTTPS_PROXY") {
            println!("Using HTTPS_PROXY from environment: {}", https_proxy);
            let proxy = reqwest::Proxy::https(&https_proxy)
                .context(format!("Invalid HTTPS_PROXY: {}", https_proxy))?;
            client_builder = client_builder.proxy(proxy);
        } else if let Ok(all_proxy) = std::env::var("ALL_PROXY") {
            println!("Using ALL_PROXY from environment: {}", all_proxy);
            let proxy = reqwest::Proxy::all(&all_proxy)
                .context(format!("Invalid ALL_PROXY: {}", all_proxy))?;
            client_builder = client_builder.proxy(proxy);
        }
    }

    client_builder.build().context("Failed to build HTTP client")
}

async fn download_slice(
    client: &reqwest::Client,
    url: &str,
    start: u64,
    end: u64,
    progress: &ProgressBar,
) -> Result<Vec<u8>> {
    let range = format!("bytes={}-{}", start, end);
    
    let response = client
        .get(url)
        .header(reqwest::header::RANGE, range)
        .send()
        .await
        .context("Failed to send range request")?;

    if !response.status().is_success() {
        anyhow::bail!("Server returned error status: {}", response.status());
    }

    let bytes = response.bytes().await.context("Failed to read response bytes")?;
    progress.inc(bytes.len() as u64);

    Ok(bytes.to_vec())
}

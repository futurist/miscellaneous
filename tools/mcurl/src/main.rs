// Simulate multiple threads downloading by using async tasks
// Copyright 2016 Wanghong Lin
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use anyhow::{anyhow, Context, Result};
use clap::Parser;
use indicatif::{ProgressBar, ProgressStyle};
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Semaphore;

const VERSION: &str = "v0.1.1";

#[derive(Parser)]
#[command(name = "mcurl")]
#[command(about = "Multi-threaded HTTP/HTTPS file downloader", long_about = None)]
#[command(version = VERSION)]
struct Cli {
    /// Number of parallel download threads (default: CPU cores)
    #[arg(short, long, value_name = "N")]
    slices: Option<usize>,

    /// Output filename (default: derived from URL)
    #[arg(short, long, value_name = "FILE")]
    output: Option<PathBuf>,

    /// URL to download
    url: String,
}

struct DownloadInfo {
    url: String,
    size: u64,
    output: PathBuf,
    slices: usize,
}

async fn get_content_length(url: &str) -> Result<u64> {
    let client = reqwest::Client::new();
    let response = client
        .head(url)
        .send()
        .await
        .context("Failed to send HEAD request")?;

    if !response.status().is_success() {
        return Err(anyhow!("Server returned status: {}", response.status()));
    }

    let content_length = response
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
        .ok_or_else(|| anyhow!("Could not get content length, make sure your resource has content length response."))?;

    Ok(content_length)
}

async fn download_chunk(
    url: &str,
    start: u64,
    end: u64,
    output_file: &Path,
    chunk_index: usize,
) -> Result<()> {
    let client = reqwest::Client::new();
    
    let range = if end > start {
        format!("bytes={}-{}", start, end)
    } else {
        format!("bytes={}-", start)
    };

    let response = client
        .get(url)
        .header(reqwest::header::RANGE, range)
        .send()
        .await
        .context("Failed to send GET request for chunk")?;

    if !response.status().is_success() && response.status() != reqwest::StatusCode::PARTIAL_CONTENT {
        return Err(anyhow!("Server returned status: {} for chunk {}", response.status(), chunk_index));
    }

    let bytes = response
        .bytes()
        .await
        .context("Failed to read chunk bytes")?;

    // Write to temporary chunk file
    let chunk_path = format!("{}.{}", output_file.display(), chunk_index);
    let mut file = File::create(&chunk_path)
        .context(format!("Failed to create chunk file: {}", chunk_path))?;
    
    file.write_all(&bytes)
        .context(format!("Failed to write to chunk file: {}", chunk_path))?;

    Ok(())
}

async fn merge_chunks(output_file: &Path, total_slices: usize) -> Result<()> {
    let mut final_file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(output_file)
        .context("Failed to create output file")?;

    for i in 1..=total_slices {
        let chunk_path = format!("{}.{}", output_file.display(), i);
        let chunk_data = std::fs::read(&chunk_path)
            .context(format!("Failed to read chunk file: {}", chunk_path))?;
        
        final_file.write_all(&chunk_data)
            .context(format!("Failed to write chunk {} to output file", i))?;

        // Remove chunk file after merging
        std::fs::remove_file(&chunk_path)
            .context(format!("Failed to remove chunk file: {}", chunk_path))?;
    }

    Ok(())
}

async fn download_file(info: DownloadInfo) -> Result<()> {
    println!(
        "Download {} to {} with {} tasks.",
        info.url, info.output.display(), info.slices
    );

    let size_per_slice = (info.size / info.slices as u64) + 1;
    let start_time = Instant::now();

    // Create progress bar
    let pb = ProgressBar::new(info.size);
    pb.set_style(
        ProgressStyle::default_bar()
            .template("{msg} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({bytes_per_sec})")?
            .progress_chars("#>-"),
    );
    pb.set_message("Downloading");

    // Use semaphore to limit concurrent downloads (not strictly necessary but can help with resource management)
    let semaphore = Arc::new(Semaphore::new(info.slices));
    let mut tasks = vec![];

    for i in 1..=info.slices {
        let start = (i - 1) as u64 * size_per_slice;
        let start = if start != 0 { start + 1 } else { start };
        let end = i as u64 * size_per_slice;
        let end = if end > info.size { info.size - 1 } else { end };

        let url = info.url.clone();
        let output = info.output.clone();
        let permit = semaphore.clone().acquire_owned().await?;
        let pb_clone = pb.clone();

        let task = tokio::spawn(async move {
            let result = download_chunk(&url, start, end, &output, i).await;
            
            // Update progress bar
            let chunk_size = if end > start { end - start + 1 } else { 0 };
            pb_clone.inc(chunk_size);
            
            drop(permit);
            result
        });

        tasks.push(task);
    }

    // Wait for all downloads to complete
    let mut errors = vec![];
    for (idx, task) in tasks.into_iter().enumerate() {
        match task.await {
            Ok(Ok(())) => {},
            Ok(Err(e)) => errors.push(format!("Chunk {} failed: {}", idx + 1, e)),
            Err(e) => errors.push(format!("Task {} panicked: {}", idx + 1, e)),
        }
    }

    pb.finish_with_message("Download complete");

    if !errors.is_empty() {
        // Clean up chunk files on error
        for i in 1..=info.slices {
            let chunk_path = format!("{}.{}", info.output.display(), i);
            let _ = std::fs::remove_file(&chunk_path);
        }
        return Err(anyhow!("Download failed:\n{}", errors.join("\n")));
    }

    println!("Merging chunks...");
    merge_chunks(&info.output, info.slices).await?;

    let duration = start_time.elapsed();
    let speed_mbps = (info.size as f64 / 1024.0 / 1024.0) / duration.as_secs_f64();
    println!(
        "Downloaded {} bytes in {:.2}s ({:.2} MiB/s)",
        info.size,
        duration.as_secs_f64(),
        speed_mbps
    );

    Ok(())
}

fn derive_filename_from_url(url: &str) -> Result<String> {
    // Remove query parameters
    let url_no_query = url.split('?').next().unwrap_or(url);
    
    // Get the last path segment
    let filename = url_no_query
        .split('/')
        .next_back()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("Could not derive filename from URL"))?;
    
    Ok(filename.to_string())
}

fn validate_url(url: &str) -> Result<()> {
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(anyhow!("Invalid URL: must start with http:// or https://"));
    }
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Validate URL
    validate_url(&cli.url)?;

    // Determine number of slices
    let slices = cli.slices.unwrap_or_else(num_cpus::get);

    // Get content length
    let size = get_content_length(&cli.url).await?;

    // Determine output filename
    let output = match cli.output {
        Some(path) => path,
        None => PathBuf::from(derive_filename_from_url(&cli.url)?),
    };

    let info = DownloadInfo {
        url: cli.url,
        size,
        output,
        slices,
    };

    download_file(info).await?;

    Ok(())
}

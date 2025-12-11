# Web PPT Creator

A Python tool that creates beautiful web-based PowerPoint-style presentations from blog posts and articles.

## Features

- 🌐 Fetches content from any URL
- 📄 Parses HTML and extracts structured content
- 🎨 Generates beautiful, animated presentations
- ⌨️ Full keyboard navigation support
- 📱 Responsive design for all devices
- 🎯 Smart content organization

## Installation

```bash
pip install requests beautifulsoup4 lxml
```

## Usage

### Basic Usage

```bash
python3 create-web-ppt.py <url> [output_file]
```

### Examples

```bash
# Create a presentation from a blog post
python3 create-web-ppt.py https://example.com/blog-post presentation.html

# Specific example with VS Code blog
python3 create-web-ppt.py \
  https://code.visualstudio.com/blogs/2025/12/03/introducing-vs-code-insiders-podcast \
  vscode-podcast.html
```

## Keyboard Controls

When viewing a presentation:

- **Arrow Right / →** - Next slide
- **Arrow Left / ←** - Previous slide
- **Space** - Next slide (scrolls content first if slide is scrollable)
- **Home** - Jump to first slide
- **End** - Jump to last slide

## How It Works

1. **Fetch**: Downloads HTML content from the provided URL
2. **Parse**: Extracts headings, paragraphs, lists, quotes, and images
3. **Organize**: Groups content into logical slides based on heading structure
4. **Generate**: Creates a standalone HTML file with embedded CSS and JavaScript
5. **View**: Opens in any modern web browser

## Presentation Features

### Visual Design
- Gradient purple background
- Smooth slide transitions
- Professional typography
- Rounded corners and shadows
- Responsive layout

### Content Support
- Headings (H1, H2, H3)
- Paragraphs
- Bullet lists (unordered)
- Numbered lists (ordered)
- Block quotes
- Images

### Navigation
- Button controls at the bottom
- Keyboard shortcuts
- Slide counter in top-right
- Disabled state for first/last slides

## Example Output

The tool generates a single HTML file that includes:
- All presentation content
- Embedded CSS styles
- JavaScript for navigation
- No external dependencies required

## Sample Presentation

See `vscode-podcast-ppt.html` for a complete example presentation about the VS Code Insiders Podcast.

## Browser Compatibility

Works in all modern browsers:
- Chrome/Edge (latest)
- Firefox (latest)
- Safari (latest)
- Opera (latest)

## Tips

1. **Best Results**: Works best with well-structured blog posts that use headings properly
2. **Local Testing**: Use `python3 -m http.server` to serve the HTML file locally
3. **Mobile Friendly**: Presentations automatically adapt to mobile screens
4. **Offline Ready**: Generated HTML files work offline - no internet required to view

## Troubleshooting

### Cannot fetch URL
- Check internet connection
- Verify the URL is accessible
- Some sites may block automated requests

### Content not parsing well
- The tool works best with semantic HTML
- Check that the blog post uses standard HTML tags
- Try adjusting the parsing logic for specific sites

## License

Part of the miscellaneous tools collection. See repository LICENSE file.

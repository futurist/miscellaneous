#!/usr/bin/env python3
"""
Create a web-based PowerPoint-style presentation from a URL.
This tool fetches content from a URL and generates an HTML presentation using reveal.js.

Usage:
    python3 create-web-ppt.py <url> [output_file]
    
Example:
    python3 create-web-ppt.py https://code.visualstudio.com/blogs/2025/12/03/introducing-vs-code-insiders-podcast vscode-podcast.html
"""

import sys
import re
import requests
from bs4 import BeautifulSoup
from html import escape

def fetch_content(url):
    """Fetch and parse content from the given URL."""
    try:
        response = requests.get(url, timeout=30, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Error fetching URL: {e}", file=sys.stderr)
        return None

def parse_blog_content(html_content):
    """Parse blog content and extract structured information."""
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # Extract title
    title_tag = soup.find('h1') or soup.find('title')
    title = title_tag.get_text().strip() if title_tag else "Presentation"
    
    # Find main content area
    main_content = (
        soup.find('article') or 
        soup.find('main') or 
        soup.find('div', class_=re.compile(r'content|article|post', re.I)) or
        soup.find('body')
    )
    
    if not main_content:
        return {"title": title, "slides": []}
    
    slides = []
    current_slide = {"title": title, "content": []}
    
    # Process content elements
    for element in main_content.find_all(['h1', 'h2', 'h3', 'p', 'ul', 'ol', 'blockquote', 'img']):
        if element.name in ['h1', 'h2', 'h3']:
            # Start a new slide on headings
            if current_slide["content"] or current_slide["title"] != title:
                slides.append(current_slide)
            current_slide = {
                "title": element.get_text().strip(),
                "content": []
            }
        elif element.name == 'p':
            text = element.get_text().strip()
            if text:
                current_slide["content"].append({"type": "text", "value": text})
        elif element.name in ['ul', 'ol']:
            items = [li.get_text().strip() for li in element.find_all('li', recursive=False)]
            if items:
                current_slide["content"].append({"type": "list", "ordered": element.name == 'ol', "items": items})
        elif element.name == 'blockquote':
            text = element.get_text().strip()
            if text:
                current_slide["content"].append({"type": "quote", "value": text})
        elif element.name == 'img':
            src = element.get('src', '')
            alt = element.get('alt', '')
            if src:
                current_slide["content"].append({"type": "image", "src": src, "alt": alt})
    
    # Add the last slide
    if current_slide["content"] or len(slides) == 0:
        slides.append(current_slide)
    
    return {"title": title, "slides": slides}

def generate_html_presentation(data, output_file):
    """Generate an HTML presentation using reveal.js."""
    
    html_template = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title}</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            overflow: hidden;
        }}
        
        .presentation {{
            position: relative;
            width: 100vw;
            height: 100vh;
            overflow: hidden;
        }}
        
        .slide {{
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            padding: 60px;
            opacity: 0;
            transform: translateX(100%);
            transition: all 0.6s cubic-bezier(0.4, 0, 0.2, 1);
        }}
        
        .slide.active {{
            opacity: 1;
            transform: translateX(0);
            z-index: 2;
        }}
        
        .slide.prev {{
            opacity: 0;
            transform: translateX(-100%);
            z-index: 1;
        }}
        
        .slide-content {{
            background: white;
            border-radius: 20px;
            padding: 50px;
            max-width: 900px;
            width: 100%;
            max-height: 85vh;
            overflow-y: auto;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
        }}
        
        .slide-content h1 {{
            font-size: 2.5em;
            color: #2d3748;
            margin-bottom: 30px;
            line-height: 1.2;
        }}
        
        .slide-content h2 {{
            font-size: 2em;
            color: #2d3748;
            margin-bottom: 25px;
            line-height: 1.3;
        }}
        
        .slide-content p {{
            font-size: 1.2em;
            color: #4a5568;
            line-height: 1.8;
            margin-bottom: 20px;
        }}
        
        .slide-content ul, .slide-content ol {{
            font-size: 1.1em;
            color: #4a5568;
            line-height: 1.8;
            margin-left: 30px;
            margin-bottom: 20px;
        }}
        
        .slide-content li {{
            margin-bottom: 10px;
        }}
        
        .slide-content blockquote {{
            border-left: 4px solid #667eea;
            padding-left: 20px;
            margin: 20px 0;
            font-style: italic;
            color: #4a5568;
            font-size: 1.1em;
        }}
        
        .slide-content img {{
            max-width: 100%;
            height: auto;
            border-radius: 10px;
            margin: 20px 0;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }}
        
        .controls {{
            position: fixed;
            bottom: 30px;
            left: 50%;
            transform: translateX(-50%);
            display: flex;
            gap: 15px;
            z-index: 1000;
        }}
        
        .controls button {{
            background: white;
            border: none;
            padding: 15px 25px;
            font-size: 16px;
            border-radius: 30px;
            cursor: pointer;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            transition: all 0.3s;
            font-weight: 600;
            color: #667eea;
        }}
        
        .controls button:hover {{
            transform: translateY(-2px);
            box-shadow: 0 6px 12px rgba(0, 0, 0, 0.15);
        }}
        
        .controls button:disabled {{
            opacity: 0.5;
            cursor: not-allowed;
        }}
        
        .slide-counter {{
            position: fixed;
            top: 30px;
            right: 30px;
            background: white;
            padding: 10px 20px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 600;
            color: #667eea;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            z-index: 1000;
        }}
        
        @media (max-width: 768px) {{
            .slide-content {{
                padding: 30px;
                max-height: 80vh;
            }}
            
            .slide-content h1 {{
                font-size: 1.8em;
            }}
            
            .slide-content h2 {{
                font-size: 1.5em;
            }}
            
            .slide-content p {{
                font-size: 1em;
            }}
        }}
        
        .title-slide .slide-content {{
            text-align: center;
        }}
        
        .title-slide h1 {{
            font-size: 3em;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }}
    </style>
</head>
<body>
    <div class="presentation">
{slides_html}
    </div>
    
    <div class="slide-counter">
        <span id="current-slide">1</span> / <span id="total-slides">{total_slides}</span>
    </div>
    
    <div class="controls">
        <button id="prev-btn" onclick="previousSlide()">← Previous</button>
        <button id="next-btn" onclick="nextSlide()">Next →</button>
    </div>
    
    <script>
        let currentSlide = 0;
        const slides = document.querySelectorAll('.slide');
        const totalSlides = slides.length;
        
        document.getElementById('total-slides').textContent = totalSlides;
        
        function showSlide(n) {{
            slides.forEach((slide, index) => {{
                slide.classList.remove('active', 'prev');
                if (index === n) {{
                    slide.classList.add('active');
                }} else if (index < n) {{
                    slide.classList.add('prev');
                }}
            }});
            
            currentSlide = n;
            document.getElementById('current-slide').textContent = currentSlide + 1;
            document.getElementById('prev-btn').disabled = currentSlide === 0;
            document.getElementById('next-btn').disabled = currentSlide === totalSlides - 1;
        }}
        
        function nextSlide() {{
            if (currentSlide < totalSlides - 1) {{
                showSlide(currentSlide + 1);
            }}
        }}
        
        function previousSlide() {{
            if (currentSlide > 0) {{
                showSlide(currentSlide - 1);
            }}
        }}
        
        // Keyboard navigation
        document.addEventListener('keydown', (e) => {{
            if (e.key === 'ArrowRight' || e.key === ' ') {{
                nextSlide();
            }} else if (e.key === 'ArrowLeft') {{
                previousSlide();
            }}
        }});
        
        // Initialize
        showSlide(0);
    </script>
</body>
</html>"""
    
    # Generate slides HTML
    slides_html = []
    for i, slide in enumerate(data["slides"]):
        is_title = i == 0
        slide_class = "slide title-slide" if is_title else "slide"
        
        content_html = []
        content_html.append(f"<h{'1' if is_title else '2'}>{escape(slide['title'])}</h{'1' if is_title else '2'}>")
        
        for item in slide["content"]:
            if item["type"] == "text":
                content_html.append(f"<p>{escape(item['value'])}</p>")
            elif item["type"] == "list":
                tag = "ol" if item["ordered"] else "ul"
                items = "".join([f"<li>{escape(li)}</li>" for li in item["items"]])
                content_html.append(f"<{tag}>{items}</{tag}>")
            elif item["type"] == "quote":
                content_html.append(f"<blockquote>{escape(item['value'])}</blockquote>")
            elif item["type"] == "image":
                content_html.append(f"<img src=\"{escape(item['src'])}\" alt=\"{escape(item['alt'])}\">")
        
        slide_html = f"""        <div class="{slide_class}">
            <div class="slide-content">
{chr(10).join('                ' + line for line in content_html)}
            </div>
        </div>"""
        slides_html.append(slide_html)
    
    # Generate final HTML
    html = html_template.format(
        title=escape(data["title"]),
        slides_html="\n".join(slides_html),
        total_slides=len(data["slides"])
    )
    
    # Write to file
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html)
    
    print(f"✓ Presentation created: {output_file}")
    print(f"✓ Total slides: {len(data['slides'])}")
    print(f"✓ Open the file in a web browser to view")

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    url = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "presentation.html"
    
    print(f"Fetching content from: {url}")
    html_content = fetch_content(url)
    
    if not html_content:
        print("Failed to fetch content. Exiting.", file=sys.stderr)
        sys.exit(1)
    
    print("Parsing content...")
    data = parse_blog_content(html_content)
    
    print(f"Generating presentation with {len(data['slides'])} slides...")
    generate_html_presentation(data, output_file)

if __name__ == "__main__":
    main()

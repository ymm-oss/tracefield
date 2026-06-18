use anyhow::{Context, Result, bail};
use chrono::Utc;
use reqwest::header::{ACCEPT, ACCEPT_LANGUAGE, CONTENT_TYPE, USER_AGENT};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::time::Duration;

const WEB_INPUT_USER_AGENT: &str =
    "Mozilla/5.0 (compatible; tracefield-web-input/0.1; +https://github.com/ymm-oss/tracefield)";
const WEB_INPUT_FETCH_ATTEMPTS: usize = 3;

#[derive(Debug, Clone)]
pub struct WebInputOptions {
    pub scenario_dir: PathBuf,
    pub urls: Vec<String>,
    pub out_dir: PathBuf,
    pub max_bytes: usize,
    pub force: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebInputResult {
    pub pages: Vec<WebInputPage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebInputPage {
    pub url: String,
    pub title: Option<String>,
    pub content_type: Option<String>,
    pub bytes: usize,
    pub path: String,
}

pub async fn ingest_web_inputs(options: WebInputOptions) -> Result<WebInputResult> {
    if options.urls.is_empty() {
        bail!("at least one --url is required");
    }
    if options.max_bytes == 0 {
        bail!("max_bytes must be at least 1");
    }
    if !options.scenario_dir.is_dir() {
        bail!(
            "scenario dir does not exist or is not a directory: {}",
            options.scenario_dir.display()
        );
    }

    let output_dir = resolve_output_dir(&options.scenario_dir, &options.out_dir)?;
    fs::create_dir_all(&output_dir)
        .with_context(|| format!("failed to create {}", output_dir.display()))?;

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(45))
        .build()
        .context("failed to build web input HTTP client")?;

    let mut pages = Vec::new();
    let mut slugs = BTreeSet::new();
    for (index, url) in options.urls.iter().enumerate() {
        let fetched = fetch_web_page(&client, url, options.max_bytes)
            .await
            .with_context(|| format!("failed to fetch {url}"))?;
        let slug = unique_slug(slug_for_url(url), &mut slugs);
        let relative_path = options.out_dir.join(format!("{:02}-{slug}.md", index + 1));
        let output_path = options.scenario_dir.join(&relative_path);
        if output_path.exists() && !options.force {
            bail!(
                "{} already exists; pass --force to overwrite",
                output_path.display()
            );
        }
        if let Some(parent) = output_path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }

        let content = render_web_input_doc(url, &fetched);
        fs::write(&output_path, content)
            .with_context(|| format!("failed to write {}", output_path.display()))?;

        pages.push(WebInputPage {
            url: url.clone(),
            title: fetched.title,
            content_type: fetched.content_type,
            bytes: fetched.bytes,
            path: relative_path.to_string_lossy().to_string(),
        });
    }

    Ok(WebInputResult { pages })
}

#[derive(Debug, Clone)]
struct FetchedWebPage {
    title: Option<String>,
    content_type: Option<String>,
    bytes: usize,
    text: String,
}

async fn fetch_web_page(
    client: &reqwest::Client,
    url: &str,
    max_bytes: usize,
) -> Result<FetchedWebPage> {
    let mut last_error = None;
    for attempt in 1..=WEB_INPUT_FETCH_ATTEMPTS {
        match fetch_web_page_once(client, url, max_bytes).await {
            Ok(page) => return Ok(page),
            Err(error) if attempt < WEB_INPUT_FETCH_ATTEMPTS => {
                last_error = Some(error);
                tokio::time::sleep(Duration::from_millis(1_500 * attempt as u64)).await;
            }
            Err(error) => return Err(error),
        }
    }

    Err(last_error.unwrap_or_else(|| anyhow::anyhow!("request failed")))
}

async fn fetch_web_page_once(
    client: &reqwest::Client,
    url: &str,
    max_bytes: usize,
) -> Result<FetchedWebPage> {
    let response = client
        .get(url)
        .header(USER_AGENT, WEB_INPUT_USER_AGENT)
        .header(
            ACCEPT,
            "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5",
        )
        .header(ACCEPT_LANGUAGE, "ja,en-US;q=0.9,en;q=0.8")
        .send()
        .await
        .context("request failed")?;
    let status = response.status();
    let content_type = response
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .map(ToOwned::to_owned);
    if !status.is_success() {
        bail!("HTTP {status}");
    }

    let bytes = response
        .bytes()
        .await
        .context("failed to read response body")?;
    let byte_len = bytes.len();
    if byte_len > max_bytes {
        bail!("response body has {byte_len} bytes, above max_bytes={max_bytes}");
    }
    let body = String::from_utf8_lossy(&bytes).to_string();
    let (title, text) = if content_type
        .as_deref()
        .unwrap_or("")
        .to_ascii_lowercase()
        .contains("html")
    {
        html_to_text(&body)
    } else {
        (None, normalize_whitespace(&body))
    };

    Ok(FetchedWebPage {
        title,
        content_type,
        bytes: byte_len,
        text,
    })
}

fn resolve_output_dir(scenario_dir: &Path, out_dir: &Path) -> Result<PathBuf> {
    if out_dir.is_absolute()
        || out_dir
            .components()
            .any(|component| matches!(component, Component::ParentDir | Component::RootDir))
    {
        bail!("--out-dir must be a relative path inside the scenario directory");
    }
    Ok(scenario_dir.join(out_dir))
}

fn render_web_input_doc(url: &str, page: &FetchedWebPage) -> String {
    let fetched_at = Utc::now().to_rfc3339();
    let title = page
        .title
        .as_deref()
        .filter(|title| !title.trim().is_empty())
        .unwrap_or(url);
    format!(
        "---\nkind: web_page\nsource_url: \"{}\"\ntitle: \"{}\"\nfetched_at: \"{}\"\ncontent_type: \"{}\"\nbytes: {}\n---\n\n# {}\n\nSource: {}\nFetched: {}\n\n{}\n",
        yaml_escape(url),
        yaml_escape(title),
        fetched_at,
        yaml_escape(page.content_type.as_deref().unwrap_or("unknown")),
        page.bytes,
        title,
        url,
        fetched_at,
        page.text.trim()
    )
}

fn html_to_text(html: &str) -> (Option<String>, String) {
    let title = extract_title(html);
    let without_hidden = remove_html_block(html, "script");
    let without_hidden = remove_html_block(&without_hidden, "style");
    let without_hidden = remove_html_block(&without_hidden, "noscript");
    let without_hidden = remove_html_block(&without_hidden, "svg");
    let text = strip_html_tags(&without_hidden);
    (title, normalize_whitespace(&decode_entities(&text)))
}

fn extract_title(html: &str) -> Option<String> {
    let lower = html.to_ascii_lowercase();
    let start = lower.find("<title")?;
    let start_close = lower[start..].find('>')? + start + 1;
    let end = lower[start_close..].find("</title>")? + start_close;
    let title = decode_entities(&strip_html_tags(&html[start_close..end]));
    let title = normalize_whitespace(&title);
    if title.is_empty() { None } else { Some(title) }
}

fn remove_html_block(html: &str, tag: &str) -> String {
    let mut output = String::new();
    let mut cursor = 0;
    let lower = html.to_ascii_lowercase();
    let open = format!("<{tag}");
    let close = format!("</{tag}>");

    while let Some(relative_start) = lower[cursor..].find(&open) {
        let start = cursor + relative_start;
        output.push_str(&html[cursor..start]);
        let Some(relative_end) = lower[start..].find(&close) else {
            cursor = html.len();
            break;
        };
        cursor = start + relative_end + close.len();
    }
    output.push_str(&html[cursor..]);
    output
}

fn strip_html_tags(html: &str) -> String {
    let mut output = String::new();
    let mut in_tag = false;
    for ch in html.chars() {
        match ch {
            '<' => {
                in_tag = true;
                output.push(' ');
            }
            '>' => {
                in_tag = false;
                output.push(' ');
            }
            _ if !in_tag => output.push(ch),
            _ => {}
        }
    }
    output
}

fn normalize_whitespace(value: &str) -> String {
    value
        .lines()
        .map(|line| line.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

fn decode_entities(value: &str) -> String {
    value
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
}

fn yaml_escape(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn slug_for_url(url: &str) -> String {
    let without_scheme = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))
        .unwrap_or(url);
    let mut output = String::new();
    let mut last_dash = false;
    for ch in without_scheme.chars() {
        if ch.is_ascii_alphanumeric() {
            output.push(ch.to_ascii_lowercase());
            last_dash = false;
        } else if !last_dash && !output.is_empty() {
            output.push('-');
            last_dash = true;
        }
        if output.len() >= 80 {
            break;
        }
    }
    let output = output.trim_matches('-').to_string();
    if output.is_empty() {
        "web-page".to_string()
    } else {
        output
    }
}

fn unique_slug(slug: String, seen: &mut BTreeSet<String>) -> String {
    if seen.insert(slug.clone()) {
        return slug;
    }
    for index in 2.. {
        let candidate = format!("{slug}-{index}");
        if seen.insert(candidate.clone()) {
            return candidate;
        }
    }
    unreachable!("unbounded loop must return")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn html_to_text_extracts_title_and_discards_hidden_blocks() {
        let html = r#"
            <html>
              <head><title>Agent Orchestration &amp; Tracing</title><style>.x{}</style></head>
              <body><script>alert(1)</script><h1>Agents</h1><p>Handoffs &amp; guardrails.</p></body>
            </html>
        "#;

        let (title, text) = html_to_text(html);

        assert_eq!(title.as_deref(), Some("Agent Orchestration & Tracing"));
        assert!(text.contains("Agents"));
        assert!(text.contains("Handoffs & guardrails."));
        assert!(!text.contains("alert"));
    }

    #[test]
    fn slug_for_url_is_stable_and_filesystem_friendly() {
        assert_eq!(
            slug_for_url("https://example.com/Docs/Agent SDK?x=1#top"),
            "example-com-docs-agent-sdk-x-1-top"
        );
    }

    #[test]
    fn render_web_input_doc_records_provenance() {
        let page = FetchedWebPage {
            title: Some("Example".to_string()),
            content_type: Some("text/html".to_string()),
            bytes: 42,
            text: "Body".to_string(),
        };

        let doc = render_web_input_doc("https://example.com", &page);

        assert!(doc.contains("kind: web_page"));
        assert!(doc.contains("source_url: \"https://example.com\""));
        assert!(doc.contains("# Example"));
        assert!(doc.contains("Body"));
    }
}

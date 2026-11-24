//! Machine translation of repo pages and short strings (descriptions,
//! categories) through any OpenAI-compatible chat API: local Ollama by
//! default, set in wiki.toml `[i18n.translator]`.
//!
//! Results are cached in `translations/<tag>/` and committed with the wiki:
//! one file per page at `<repo>/<path in repo>`, `sources.json` (page ->
//! blob id of the English it was translated from) and `strings.json`
//! (English -> translation). A page is sent again only when its English blob
//! id changed; until the new translation lands, the old one is shown.
//! `WIKI_TRANSLATE=0` (or an unreachable endpoint) builds from the cache alone.
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use anyhow::{Context, Result, anyhow};
use async_openai::Client;
use async_openai::config::OpenAIConfig;
use async_openai::error::OpenAIError;
use async_openai::types::chat::{
    ChatCompletionRequestSystemMessage, ChatCompletionRequestUserMessage, CreateChatCompletionRequestArgs,
    ReasoningEffort,
};
use futures::StreamExt;
use regex::Regex;
use serde::{Deserialize, Serialize};
use text_splitter::{ChunkConfig, MarkdownSplitter};

use crate::warn;

/// wiki.toml `[i18n.translator]`.
#[derive(Deserialize, Serialize, Clone)]
#[serde(default)]
pub struct TranslatorConfig {
    /// OpenAI-compatible API base, e.g. "https://api.openai.com/v1".
    pub base_url: String,
    pub model: String,
    /// Environment variable holding the API key (none needed for Ollama).
    pub api_key_env: Option<String>,
    /// Sent as `reasoning_effort`; "none" turns off thinking on Ollama.
    pub reasoning_effort: Option<ReasoningEffort>,
    /// Requests in flight at once.
    pub jobs: usize,
    /// Largest markdown chunk per request, in characters.
    pub chunk: usize,
}

impl Default for TranslatorConfig {
    fn default() -> Self {
        Self {
            base_url: "http://localhost:11434/v1".into(),
            model: "huihui_ai/qwen3.6-abliterated:35b-a3b".into(),
            api_key_env: None,
            reasoning_effort: None,
            jobs: 2,
            chunk: 4000,
        }
    }
}

/// `translations/<tag>/`.
pub struct Cache {
    dir: PathBuf,
    sources: BTreeMap<String, String>,
    strings: BTreeMap<String, String>,
}

pub struct Cached {
    pub text: String,
    /// Translated from the current English (else from an older version).
    pub current: bool,
}

fn read_json<T: Default + for<'de> Deserialize<'de>>(path: &Path) -> T {
    fs::read(path).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default()
}

fn write_json(path: &Path, value: &impl Serialize) -> Result<()> {
    fs::create_dir_all(path.parent().context("cache file without dir")?)?;
    let mut json = serde_json::to_string_pretty(value)?;
    json.push('\n');
    fs::write(path, json).with_context(|| format!("writing {}", path.display()))
}

impl Cache {
    pub fn load(wiki: &Path, tag: &str) -> Self {
        let dir = wiki.join("translations").join(tag);
        Self { sources: read_json(&dir.join("sources.json")), strings: read_json(&dir.join("strings.json")), dir }
    }

    /// The translation of page `key` ("<repo>/<path>"), whose English has blob id `source_id`.
    pub fn page(&self, key: &str, source_id: &str) -> Option<Cached> {
        let from = self.sources.get(key)?;
        let text = fs::read_to_string(self.dir.join(key)).ok()?;
        Some(Cached { text, current: from == source_id })
    }

    pub fn string(&self, english: &str) -> Option<&str> {
        self.strings.get(english).map(String::as_str)
    }

    fn put_page(&mut self, key: &str, source_id: &str, text: &str) -> Result<()> {
        let path = self.dir.join(key);
        fs::create_dir_all(path.parent().context("page without dir")?)?;
        fs::write(&path, text).with_context(|| format!("writing {}", path.display()))?;
        self.sources.insert(key.to_owned(), source_id.to_owned());
        write_json(&self.dir.join("sources.json"), &self.sources)
    }

    fn put_string(&mut self, english: &str, text: &str) -> Result<()> {
        self.strings.insert(english.to_owned(), text.to_owned());
        write_json(&self.dir.join("strings.json"), &self.strings)
    }

    /// Drop translations of pages under `repos` that are no longer in `pages`,
    /// and strings not in `strings`.
    pub fn prune(&mut self, repos: &BTreeSet<String>, pages: &BTreeSet<String>, strings: &BTreeSet<String>) -> Result<()> {
        let gone: Vec<String> = self
            .sources
            .keys()
            .filter(|key| !pages.contains(*key) && repos.iter().any(|repo| key.starts_with(&format!("{repo}/"))))
            .cloned()
            .collect();
        for key in &gone {
            let _ = fs::remove_file(self.dir.join(key));
            self.sources.remove(key);
        }
        let before = self.strings.len();
        self.strings.retain(|english, _| strings.contains(english));
        if !gone.is_empty() {
            write_json(&self.dir.join("sources.json"), &self.sources)?;
        }
        if self.strings.len() != before {
            write_json(&self.dir.join("strings.json"), &self.strings)?;
        }
        Ok(())
    }
}

pub enum Job {
    /// A markdown or Jinja page: `key` is "<repo>/<path>", `source_id` its blob id.
    Page { key: String, source_id: String, text: String },
    /// A one-line string (description, category).
    String { text: String },
}

impl Job {
    fn name(&self) -> &str {
        match self {
            Job::Page { key, .. } => key,
            Job::String { text } => text,
        }
    }
}

/// Translate `jobs` into `language` (a description for the prompt, e.g.
/// "Traditional Chinese as written in Taiwan"), saving each result to `cache`
/// as it lands, so an interrupted run keeps what it finished.
pub fn run(config: &TranslatorConfig, language: &str, cache: &mut Cache, jobs: Vec<Job>) -> Result<()> {
    if jobs.is_empty() {
        return Ok(());
    }
    if std::env::var("WIKI_TRANSLATE").is_ok_and(|value| value == "0") {
        warn(format_args!("{} untranslated pages/strings for {} (WIKI_TRANSLATE=0)", jobs.len(), cache.dir.display()));
        return Ok(());
    }
    let translator = Translator::new(config, language)?;
    let total = jobs.len();
    let runtime = tokio::runtime::Runtime::new()?;
    runtime.block_on(async {
        let mut results = futures::stream::iter(jobs)
            .map(|job| {
                let translator = &translator;
                async move {
                    let result = match &job {
                        Job::Page { text, .. } => translator.markdown(text).await,
                        Job::String { text } => translator.string(text).await,
                    };
                    (job, result)
                }
            })
            .buffer_unordered(config.jobs.max(1));
        let mut done = 0;
        while let Some((job, result)) = results.next().await {
            done += 1;
            match result {
                Ok(text) => {
                    match &job {
                        Job::Page { key, source_id, .. } => cache.put_page(key, source_id, &text)?,
                        Job::String { text: english } => cache.put_string(english, &text)?,
                    }
                    println!("wiki: translated {done}/{total} {}", job.name());
                }
                Err(Failure::Unreachable(err)) => {
                    warn(format_args!("translator at {} unreachable ({err}); using cached translations", config.base_url));
                    break;
                }
                Err(Failure::Other(err)) => warn(format_args!("translating {}: {err:#}", job.name())),
            }
        }
        anyhow::Ok(())
    })
}

enum Failure {
    Unreachable(OpenAIError),
    Other(anyhow::Error),
}

impl From<OpenAIError> for Failure {
    fn from(err: OpenAIError) -> Self {
        match err {
            OpenAIError::Reqwest(_) => Failure::Unreachable(err),
            other => Failure::Other(other.into()),
        }
    }
}

impl From<anyhow::Error> for Failure {
    fn from(err: anyhow::Error) -> Self {
        Failure::Other(err)
    }
}

struct Translator {
    client: Client<OpenAIConfig>,
    model: String,
    reasoning_effort: Option<ReasoningEffort>,
    chunk: usize,
    page_prompt: String,
    string_prompt: String,
}

static THINK: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<think>.*?</think>").expect("valid regex"));
static FENCED: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?s)^```[a-z]*\n(.*)\n```$").expect("valid regex"));

impl Translator {
    fn new(config: &TranslatorConfig, language: &str) -> Result<Self> {
        let mut openai = OpenAIConfig::new().with_api_base(&config.base_url);
        if let Some(var) = &config.api_key_env {
            openai = openai.with_api_key(std::env::var(var).map_err(|_| anyhow!("${var} (translator API key) is not set"))?);
        }
        Ok(Self {
            client: Client::with_config(openai),
            model: config.model.clone(),
            reasoning_effort: config.reasoning_effort.clone(),
            chunk: config.chunk.max(500),
            page_prompt: format!(
                "You translate software documentation from English into {language}. The input is a fragment of a \
                 Markdown (or Jinja/HTML) file. Translate the prose only. Keep exactly as they are: the Markdown \
                 structure and line breaks, code blocks and inline code, URLs and link targets, HTML tags and \
                 attributes, front matter keys, template tags such as {{{{ ... }}}} and {{% ... %}}, file names, \
                 commands, and product, project and repo names. Reply with the translated fragment only: no \
                 commentary, no surrounding code fence."
            ),
            string_prompt: format!(
                "Translate the user's text from English into {language}. It is a short label or one-sentence \
                 description on a software documentation site. Keep product, project and repo names, file names \
                 and code as they are. Reply with the translation only."
            ),
        })
    }

    async fn chat(&self, system: &str, text: &str) -> Result<String, Failure> {
        let mut request = CreateChatCompletionRequestArgs::default()
            .model(&self.model)
            .messages([ChatCompletionRequestSystemMessage::from(system).into(), ChatCompletionRequestUserMessage::from(text).into()])
            .temperature(0.2_f32)
            .build()?;
        request.reasoning_effort = self.reasoning_effort.clone();
        let response = self.client.chat().create(request).await?;
        let content = response
            .choices
            .into_iter()
            .next()
            .and_then(|choice| choice.message.content)
            .ok_or_else(|| anyhow!("empty reply"))?;
        let content = THINK.replace_all(&content, "");
        let content = content.trim();
        Ok(match FENCED.captures(content) {
            Some(found) if !text.trim_start().starts_with("```") => found[1].to_owned(),
            _ => content.to_owned(),
        })
    }

    async fn string(&self, text: &str) -> Result<String, Failure> {
        self.chat(&self.string_prompt, text).await
    }

    /// Chunk by markdown structure (headings, blocks), translate each chunk,
    /// and put the whitespace around each chunk back so the layout survives.
    async fn markdown(&self, text: &str) -> Result<String, Failure> {
        let splitter = MarkdownSplitter::new(ChunkConfig::new(self.chunk).with_trim(false));
        let mut out = String::with_capacity(text.len() * 2);
        for chunk in splitter.chunks(text) {
            let body = chunk.trim();
            if body.is_empty() {
                out.push_str(chunk);
                continue;
            }
            let lead = &chunk[..chunk.len() - chunk.trim_start().len()];
            let tail = &chunk[chunk.trim_end().len()..];
            out.push_str(lead);
            out.push_str(&self.chat(&self.page_prompt, body).await?);
            out.push_str(tail);
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `markdown` relies on untrimmed chunks covering the text exactly.
    #[test]
    fn chunks_cover_the_text() {
        let text = fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/docs/README.md")).unwrap();
        let splitter = MarkdownSplitter::new(ChunkConfig::new(500).with_trim(false));
        let chunks: Vec<&str> = splitter.chunks(&text).collect();
        assert!(chunks.len() > 3);
        assert_eq!(chunks.concat(), text);
    }
}

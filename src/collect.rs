//! The repos to publish: `pull status --json` merged with wiki.toml.
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::{env, fs};

use anyhow::{Context, Result, bail};
use regex::Regex;
use serde::{Deserialize, Serialize};

use crate::Paths;

/// One repo's table in wiki.toml.
#[derive(Default, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct RepoConfig {
    /// Leave the repo out of the wiki.
    pub skip: bool,
    /// Group label for the wiki header's dropdowns; default: the pull group
    /// (`fossify-ios` for `fossify-ios/notes-ios`), else "Other".
    pub category: Option<String>,
    /// One line for the home page; defaults to the README's first sentence.
    pub description: Option<String>,
    pub rust: Tool,
    pub lua: Tool,
    pub js: Tool,
    /// Machine-translate the README and docs into the wiki.toml `[i18n]`
    /// languages; `{ files = [..] }` limits it to matching paths.
    pub translate: Tool,
}

/// `tool = false` turns a doc tool off; a table configures it.
#[derive(Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Tool {
    Enabled(bool),
    Settings(ToolSettings),
}

impl Default for Tool {
    fn default() -> Self {
        Tool::Enabled(true)
    }
}

impl Tool {
    /// The settings, or None when the tool is turned off.
    pub fn settings(&self) -> Option<ToolSettings> {
        match self {
            Tool::Enabled(false) => None,
            Tool::Enabled(true) => Some(ToolSettings::default()),
            Tool::Settings(settings) => Some(settings.clone()),
        }
    }
}

#[derive(Default, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ToolSettings {
    /// rust: cargo packages (`-p`); default: the workspace's default members.
    pub packages: Vec<String>,
    /// lua/js: pathspecs of tracked files; default: every tracked file of the language.
    /// translate: pathspecs of pages; default: all of them.
    pub files: Vec<String>,
}

#[derive(Deserialize, Default)]
struct WikiToml {
    #[serde(default)]
    repos: BTreeMap<String, RepoConfig>,
}

pub struct Repo {
    pub name: String,
    pub path: PathBuf,
    pub branch: String,
    pub head: String,
    /// https://github.com/owner/repo, from the origin remote.
    pub web: Option<String>,
    /// File name of the README in the repo root.
    pub readme: Option<String>,
    pub config: RepoConfig,
}

#[derive(Deserialize)]
struct Status {
    repos: Vec<StatusRepo>,
}

#[derive(Deserialize)]
struct StatusRepo {
    name: String,
    path: PathBuf,
    cloned: bool,
    branch: Option<String>,
    head: Option<String>,
}

/// Every cloned repo that isn't skipped (wiki.toml `skip` or `$WIKI_SKIP`), sorted by name.
pub fn collect(paths: &Paths) -> Result<Vec<Repo>> {
    let toml_path = paths.wiki.join("wiki.toml");
    let config: WikiToml = toml::from_str(&fs::read_to_string(&toml_path)?)
        .with_context(|| format!("parsing {}", toml_path.display()))?;
    let skipped: Vec<String> = env::var("WIKI_SKIP")
        .unwrap_or_default()
        .split(',')
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
        .collect();

    let output = std::process::Command::new("pull")
        .args(["status", "--json"])
        .current_dir(&paths.root)
        .output()
        .context("running `pull status --json`")?;
    if !output.status.success() {
        bail!("pull status --json: {}", String::from_utf8_lossy(&output.stderr));
    }
    let status: Status = serde_json::from_slice(&output.stdout).context("parsing `pull status --json`")?;

    let github = Regex::new(r"github\.com[:/]([^/]+/[^/]+?)(\.git)?/?$")?;
    let mut repos = Vec::new();
    for repo in status.repos {
        let config = config.repos.get(&repo.name).cloned().unwrap_or_default();
        if !repo.cloned || config.skip || skipped.contains(&repo.name) {
            continue;
        }
        let readme = fs::read_dir(&repo.path)?
            .filter_map(Result::ok)
            .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_file()))
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .find(|name| name.eq_ignore_ascii_case("readme.md"));
        let web = git2::Repository::open(&repo.path)
            .ok()
            .and_then(|git| git.find_remote("origin").ok().and_then(|remote| remote.url().ok().map(str::to_owned)))
            .and_then(|url| github.captures(&url).map(|found| format!("https://github.com/{}", &found[1])));
        repos.push(Repo {
            name: repo.name,
            path: repo.path,
            branch: repo.branch.unwrap_or_else(|| "main".into()),
            head: repo.head.unwrap_or_default(),
            web,
            readme,
            config,
        });
    }
    repos.sort_by_key(|repo| repo.name.to_lowercase());
    Ok(repos)
}

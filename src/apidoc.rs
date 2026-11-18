//! Code reference per repo, by each language's own tool, into
//! `.build/api/<repo>/<tool>/`:
//!   rust: `cargo doc --no-deps` (rustdoc)   lua: LDoc   js: JSDoc
//! A tool that is missing or fails only warns: the site still builds. A
//! reference is rebuilt only when the repo's source id (see [`state`]) or its
//! wiki.toml settings changed.
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::Result;
use regex::Regex;
use serde::{Deserialize, Serialize};

use crate::collect::{Repo, ToolSettings};
use crate::state::{self, ApiState, State};
use crate::{Paths, warn};

/// One code reference page set: `path` is relative to `.build/api/<repo>`.
#[derive(Clone, Serialize, Deserialize)]
pub struct Api {
    pub tool: String,
    pub title: String,
    pub path: String,
}

/// Repo name -> its code references.
pub fn generate(paths: &Paths, repos: &[Repo], state: &mut State) -> Result<BTreeMap<String, Vec<Api>>> {
    let mut apis = BTreeMap::new();
    let mut kept = BTreeMap::new();
    for repo in repos {
        let source = match state::source_id(&repo.path) {
            Ok(id) => id,
            Err(err) => {
                warn(format_args!("{}: {err}", repo.name));
                continue;
            }
        };
        let mut entries = Vec::new();
        let tools = [("rust", &repo.config.rust), ("lua", &repo.config.lua), ("js", &repo.config.js)];
        for (tool, config) in tools {
            let Some(settings) = config.settings() else { continue };
            let id = format!("{}/{tool}", repo.name);
            let key = state::key([source.as_str(), tool, &serde_json::to_string(&settings)?]);
            let dest = paths.build.join("api").join(&repo.name).join(tool);
            let built = match state.apidoc.get(&id) {
                Some(previous) if previous.key == key && (previous.entries.is_empty() || dest.is_dir()) => {
                    previous.entries.clone()
                }
                _ => {
                    let job = Job { paths, repo, settings: &settings, dest: &dest };
                    match tool {
                        "rust" => job.rust(),
                        "lua" => job.lua(),
                        _ => job.js(),
                    }
                }
            };
            entries.extend(built.iter().cloned());
            kept.insert(id, ApiState { key, entries: built });
        }
        if !entries.is_empty() {
            apis.insert(repo.name.clone(), entries);
        }
    }
    state.apidoc = kept;
    Ok(apis)
}

struct Job<'a> {
    paths: &'a Paths,
    repo: &'a Repo,
    settings: &'a ToolSettings,
    dest: &'a Path,
}

impl Job<'_> {
    fn warn(&self, message: impl std::fmt::Display) {
        warn(format_args!("{}: {message}", self.repo.name));
    }

    fn entry(&self, tool: &str, title: &str, path: String) -> Api {
        Api { tool: tool.into(), title: title.into(), path }
    }

    /// Run a doc tool; on failure warn with its output and return false.
    fn run(&self, command: &mut Command, what: &str) -> bool {
        match command.output() {
            Ok(output) if output.status.success() => true,
            Ok(output) => {
                self.warn(format_args!("{what} failed"));
                eprint!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
                false
            }
            Err(err) => {
                self.warn(format_args!("{what} not available ({err}), skipping"));
                false
            }
        }
    }

    fn reset_dest(&self) -> Result<()> {
        if self.dest.exists() {
            fs::remove_dir_all(self.dest)?;
        }
        fs::create_dir_all(self.dest)?;
        Ok(())
    }

    /// Tracked files matching the `files` pathspecs, or the defaults.
    fn tracked_files(&self, defaults: &[&str]) -> Vec<String> {
        let specs: Vec<&str> = if self.settings.files.is_empty() {
            defaults.to_vec()
        } else {
            self.settings.files.iter().map(String::as_str).collect()
        };
        let Ok(repo) = git2::Repository::open(&self.repo.path) else { return Vec::new() };
        let (Ok(index), Ok(pathspec)) = (repo.index(), git2::Pathspec::new(specs.iter().copied())) else {
            return Vec::new();
        };
        index
            .iter()
            .map(|entry| String::from_utf8_lossy(&entry.path).into_owned())
            .filter(|path| pathspec.matches_path(Path::new(path), git2::PathspecFlags::DEFAULT))
            .collect()
    }

    fn any_file_contains(&self, files: &[String], pattern: &Regex) -> bool {
        files.iter().any(|file| fs::read_to_string(self.repo.path.join(file)).is_ok_and(|text| pattern.is_match(&text)))
    }

    fn rust(&self) -> Vec<Api> {
        if !self.repo.path.join("Cargo.toml").is_file() {
            return Vec::new();
        }
        self.try_rust().unwrap_or_else(|err| {
            self.warn(format_args!("rustdoc: {err}"));
            Vec::new()
        })
    }

    fn try_rust(&self) -> Result<Vec<Api>> {
        // The repo's own target dir, so dependency metadata is shared with its builds.
        let metadata = Command::new("cargo")
            .args(["metadata", "--format-version", "1", "--no-deps"])
            .current_dir(&self.repo.path)
            .output()?;
        let metadata: serde_json::Value = serde_json::from_slice(&metadata.stdout)?;
        let target = PathBuf::from(metadata["target_directory"].as_str().unwrap_or("target"));
        let mut cargo = Command::new("cargo");
        cargo.args(["doc", "--no-deps", "--quiet"]).current_dir(&self.repo.path);
        for package in &self.settings.packages {
            cargo.args(["-p", package]);
        }
        if !self.run(&mut cargo, "cargo doc") {
            return Ok(Vec::new());
        }
        self.reset_dest()?;
        copy_dir(&target.join("doc"), self.dest)?;
        let crates_js = fs::read_to_string(self.dest.join("crates.js"))?;
        let list = Regex::new(r"(?m)^window\.ALL_CRATES = (.*);$")?
            .captures(&crates_js)
            .and_then(|found| serde_json::from_str::<Vec<String>>(&found[1]).ok())
            .unwrap_or_default();
        Ok(list.iter().map(|name| self.entry("rust", name, format!("rust/{name}/index.html"))).collect())
    }

    fn lua(&self) -> Vec<Api> {
        // *.x.lua are preprocessed ycode hook scripts, not plain Lua modules.
        let defaulted = self.settings.files.is_empty();
        let files: Vec<String> = self
            .tracked_files(&["*.lua"])
            .into_iter()
            .filter(|file| !(defaulted && file.ends_with(".x.lua")))
            .collect();
        // LDoc only documents `---` comments; without any there is nothing to show.
        let doc_comment = Regex::new(r"(?m)^\s*---").expect("valid regex");
        if files.is_empty() || !self.any_file_contains(&files, &doc_comment) {
            return Vec::new();
        }
        self.try_lua(&files).unwrap_or_else(|err| {
            self.warn(format_args!("ldoc: {err}"));
            Vec::new()
        })
    }

    fn try_lua(&self, files: &[String]) -> Result<Vec<Api>> {
        self.reset_dest()?;
        let name = &self.repo.name;
        let conf = self.dest.with_file_name("config.ld");
        // JSON strings double as Lua string literals. "backtick": Debian ships
        // LDoc without its markdown module, so only `code` spans are formatted.
        let json = |text: &str| serde_json::to_string(text).unwrap_or_default();
        let mut config = format!(
            "project = {}\ntitle = {}\ndir = {}\nformat = \"backtick\"\nfile = {{\n",
            json(name),
            json(&format!("{name} Lua API")),
            json(&self.dest.to_string_lossy()),
        );
        for file in files {
            config.push_str(&format!("  {},\n", json(&self.repo.path.join(file).to_string_lossy())));
        }
        config.push_str("}\n");
        fs::write(&conf, config)?;
        let ok = self.run(Command::new("ldoc").arg("--testing").arg("-c").arg(&conf).arg(".").current_dir(&self.repo.path), "ldoc");
        fs::remove_file(&conf)?;
        Ok(if ok { vec![self.entry("lua", name, "lua/index.html".into())] } else { Vec::new() })
    }

    fn js(&self) -> Vec<Api> {
        if !self.repo.path.join("package.json").is_file() {
            return Vec::new();
        }
        let files = self.tracked_files(&["*.js", "*.mjs"]);
        let doc_comment = Regex::new(r"/\*\*").expect("valid regex");
        if files.is_empty() || !self.any_file_contains(&files, &doc_comment) {
            return Vec::new();
        }
        let jsdoc = self.paths.wiki.join("node_modules/.bin/jsdoc");
        if !jsdoc.is_file() {
            self.warn("jsdoc not installed (just install), skipping");
            return Vec::new();
        }
        if let Err(err) = self.reset_dest() {
            self.warn(err);
            return Vec::new();
        }
        // jsdoc.json drops the generation date, so unchanged code gives unchanged pages.
        let mut command = Command::new(jsdoc);
        command
            .arg("-c")
            .arg(self.paths.wiki.join("jsdoc.json"))
            .arg("-d")
            .arg(self.dest)
            .args(&files)
            .current_dir(&self.repo.path);
        if self.run(&mut command, "jsdoc") {
            vec![self.entry("js", &self.repo.name, "js/index.html".into())]
        } else {
            Vec::new()
        }
    }
}

/// Copy the files under `from` into `to`, keeping the layout.
pub fn copy_dir(from: &Path, to: &Path) -> Result<()> {
    for entry in walkdir::WalkDir::new(from) {
        let entry = entry?;
        let dest = to.join(entry.path().strip_prefix(from)?);
        if entry.file_type().is_dir() {
            fs::create_dir_all(&dest)?;
        } else {
            fs::copy(entry.path(), &dest)?;
        }
    }
    Ok(())
}
